#!/usr/bin/env bash
# tests/test_dockerfile_perl_deps_static.sh
#
# Static checks that critical Perl runtime deps stay present in Dockerfile-Alpine.

set -euo pipefail

DOCKERFILE="$(cd "$(dirname "$0")/.." && pwd)/Dockerfile-Alpine"
CPAN_INSTALLER="$(cd "$(dirname "$0")/.." && pwd)/scripts/install-koha-perl-dependencies.sh"

PASS=0; FAIL=0; _N=0
ok() {
    _N=$(( _N + 1 ))
    echo "ok ${_N} - $1"
    PASS=$(( PASS + 1 ))
}
not_ok() {
    _N=$(( _N + 1 ))
    echo "not ok ${_N} - $1"
    FAIL=$(( FAIL + 1 ))
}
assert_contains() {
    local desc="$1"; local pattern="$2"; local file="${3:-${DOCKERFILE}}"
    if grep -qF -- "${pattern}" "${file}"; then
        ok "${desc}"
    else
        not_ok "${desc} (pattern not found in ${file}: ${pattern})"
    fi
}

echo "TAP version 14"
echo "# Static checks on Dockerfile-Alpine Perl dependencies"
echo ""

assert_contains "Dockerfile installs CGI::Session package" "perl-cgi-session"
assert_contains "Dockerfile installs Crypt::SysRandom into the runtime Perl library" "cpanm --notest --local-lib=/opt/koha-perl Crypt::SysRandom"
assert_contains "Dockerfile supplies the native fribidi headers needed by Text::Bidi" "fribidi-dev"
assert_contains "Dockerfile uses the shared Koha CPAN dependency installer" "install-koha-perl-dependencies.sh" "${DOCKERFILE}"
assert_contains "Koha CPAN dependencies are installed from the source directory" "cpanm --notest --local-lib=/opt/koha-perl --installdeps ." "${CPAN_INSTALLER}"
BASE_STAGE="$(awk '/^FROM docker.io\/library\/alpine:.* AS base$/ { in_base=1 } /^FROM base AS builder$/ { in_base=0 } in_base { print }' "${DOCKERFILE}")"
if grep -Eq '(^|[[:space:]])(nodejs|npm|yarn|mariadb-dev|perl-app-cpanminus|perl-local-lib)([[:space:]]|$)' <<<"${BASE_STAGE}"; then
    not_ok "runtime base excludes development and Perl build packages"
else
    ok "runtime base excludes development and Perl build packages"
fi
assert_contains "development runtime installs Node, Yarn, and Git separately" "apk add --no-cache nodejs npm yarn git"
assert_contains "Perl dependency builder installs CPAN build utilities separately" "apk add --no-cache perl-app-cpanminus perl-local-lib mariadb-dev git"
if grep -qF -- "--installdeps . || true" "${DOCKERFILE}"; then
    not_ok "Koha CPAN dependency failures are not suppressed"
else
    ok "Koha CPAN dependency failures are not suppressed"
fi
if grep -qF -- "|| true" "${CPAN_INSTALLER}"; then
    not_ok "Koha CPAN installer does not suppress dependency failures"
else
    ok "Koha CPAN installer does not suppress dependency failures"
fi

echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}"
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
