#!/usr/bin/env bash
# tests/test_dockerfile_perl_deps_static.sh
#
# Static checks that critical Perl runtime deps stay present in Dockerfile-Alpine.

set -euo pipefail

DOCKERFILE="$(cd "$(dirname "$0")/.." && pwd)/Dockerfile-Alpine"

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
    local desc="$1"; local pattern="$2"
    if grep -qF -- "${pattern}" "${DOCKERFILE}"; then
        ok "${desc}"
    else
        not_ok "${desc} (pattern not found: ${pattern})"
    fi
}

echo "TAP version 14"
echo "# Static checks on Dockerfile-Alpine Perl dependencies"
echo ""

assert_contains "Dockerfile installs CGI::Session package" "perl-cgi-session"
assert_contains "Dockerfile installs Crypt::SysRandom into the runtime Perl library" "cpanm --notest --local-lib=/opt/koha-perl Crypt::SysRandom"
assert_contains "Dockerfile supplies the native fribidi headers needed by Text::Bidi" "fribidi-dev"
assert_contains "Dockerfile does not hide Koha CPAN dependency installation failures" "cpanm --notest --local-lib=/opt/koha-perl --installdeps .;"
if grep -qF -- "--installdeps . || true" "${DOCKERFILE}"; then
    not_ok "Koha CPAN dependency failures are not suppressed"
else
    ok "Koha CPAN dependency failures are not suppressed"
fi

echo ""
echo "1..${_N}"
echo "# Passed: ${PASS}  Failed: ${FAIL}"
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
