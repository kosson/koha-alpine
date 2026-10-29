#!/bin/bash
umask 077
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_file="$SCRIPT_DIR/opensearch_installer_vars.cfg"

if [ -f "$config_file" ]; then
    source "$config_file"
    # Root CA key creation
    openssl genrsa -out $OS_CERTS_PATH/root-ca-key.pem 2048
    openssl req -new -x509 -sha256 -key $OS_CERTS_PATH/root-ca-key.pem -subj "$CERT_DN/CN=$LOCAL_ROOT_CA" -out $OS_CERTS_PATH/root-ca.pem -days 730
    # TSL certificate for the administrator
    openssl genrsa -out $OS_CERTS_PATH/$ADMIN_CA-key-temp.pem 2048
    openssl pkcs8 -inform PEM -outform PEM -in $OS_CERTS_PATH/$ADMIN_CA-key-temp.pem -topk8 -nocrypt -v1 PBE-SHA1-3DES -out $OS_CERTS_PATH/$ADMIN_CA-key.pem
    openssl req -new -key $OS_CERTS_PATH/$ADMIN_CA-key.pem -subj "$CERT_DN/CN=$ADMIN_CA" -out $OS_CERTS_PATH/$ADMIN_CA.csr
    openssl x509 -req -in $OS_CERTS_PATH/$ADMIN_CA.csr -CA $OS_CERTS_PATH/root-ca.pem -CAkey $OS_CERTS_PATH/root-ca-key.pem -CAcreateserial -sha256 -out $OS_CERTS_PATH/$ADMIN_CA.pem -days 730
    # TLS certificate for the nodes
    for NODE_NAME in "os01" "os02" "os03" "os04" "os05" "client" "dashboards"
    do
        openssl genrsa -out $OS_CERTS_PATH/$NODE_NAME-key-temp.pem 2048
        openssl pkcs8 -inform PEM -outform PEM -in $OS_CERTS_PATH/$NODE_NAME-key-temp.pem -topk8 -nocrypt -v1 PBE-SHA1-3DES -out $OS_CERTS_PATH/$NODE_NAME-key.pem
        openssl req -new -key $OS_CERTS_PATH/$NODE_NAME-key.pem -subj $CERT_DN/CN=$NODE_NAME -out $OS_CERTS_PATH/$NODE_NAME.csr
        echo "subjectAltName=DNS:$NODE_NAME" > $OS_CERTS_PATH/$NODE_NAME.ext
        openssl x509 -req -in $OS_CERTS_PATH/$NODE_NAME.csr -CA $OS_CERTS_PATH/root-ca.pem -CAkey $OS_CERTS_PATH/root-ca-key.pem -CAcreateserial -sha256 -out $OS_CERTS_PATH/$NODE_NAME.pem -days 730 -extfile $OS_CERTS_PATH/$NODE_NAME.ext
        rm $OS_CERTS_PATH/$NODE_NAME-key-temp.pem $OS_CERTS_PATH/$NODE_NAME.csr $OS_CERTS_PATH/$NODE_NAME.ext
        chown -R 1000:1000 $OS_CERTS_PATH/$NODE_NAME-key.pem $OS_CERTS_PATH/$NODE_NAME.pem
    done
else
    echo "$config_file not found."    
fi

rm -f $OS_CERTS_PATH/$ADMIN_CA.csr $OS_CERTS_PATH/$ADMIN_CA-key-temp.pem
rm -f $OS_CERTS_PATH/root-ca.srl

# ENV_FILE is used by both the compliance-salt section and the hash section below.
ENV_FILE="$SCRIPT_DIR/.env"

# --- Compliance salt and SQL datasource master key ---------------------------------
# Both values must be identical on every node. Generated once here and written to
# .env; opensearch.yml files reference them as ${OS_COMPLIANCE_SALT} /
# ${OS_QUERY_MASTERKEY} so OpenSearch substitutes them at container startup.
#
# WARNING: Do NOT regenerate the SQL masterkey after the cluster has been used to
# store datasource credentials — re-running this script on an existing cluster will
# produce a new key and make any previously stored encrypted credentials unreadable.
# Run this script only when setting up a fresh cluster (after restart-to-clear-cluster.sh).

COMPLIANCE_SALT="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)"
SQL_MASTERKEY="$(openssl rand -hex 16)"

# Write (or update) OS_COMPLIANCE_SALT and OS_QUERY_MASTERKEY in .env.
# The opensearch.yml files reference these as ${OS_COMPLIANCE_SALT} and
# ${OS_QUERY_MASTERKEY}; OpenSearch substitutes them from the container
# environment at startup (all containers use env_file: .env).
# Writing here instead of patching the yml files means git pull can never
# clobber the values — .env is gitignored and machine-local.
_upsert_env() {
    local key="$1" value="$2" file="$3"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

_upsert_env "OS_COMPLIANCE_SALT" "$COMPLIANCE_SALT" "$ENV_FILE"
_upsert_env "OS_QUERY_MASTERKEY"  "$SQL_MASTERKEY"  "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo "Compliance salt and SQL master key generated and written to the access-controlled local environment file."

# --- Secure file permissions -------------------------------------------------------
# Config files and private keys must not be world-readable. The Security plugin will
# log permission warnings at startup if these are not set correctly.
find "$SCRIPT_DIR/assets/ssl" -type f -name "*.pem" ! -name "*-key.pem" -exec chmod 644 {} +
find "$SCRIPT_DIR/assets/ssl" -type f -name "*-key.pem" -exec chmod 640 {} +
find "$SCRIPT_DIR/assets/opensearch/config" -type d -exec chmod 755 {} +
find "$SCRIPT_DIR/assets/opensearch/config" -type f -exec chmod 644 {} +
find "$SCRIPT_DIR/assets/opensearch/performance-analyzer" -type f -exec chmod 644 {} 2>/dev/null || true
echo "Certificate and OpenSearch config permissions set; private keys are not world-readable."

bash "$SCRIPT_DIR/prepare_local_auth_config.sh"