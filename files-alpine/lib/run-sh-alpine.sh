#!/bin/sh
# run-sh-alpine.sh - Alpine shims + helpers - FINAL v10
# Includes stub for setup_git_workflow when skipped

setup_git_workflow(){
  if [ "${KOHA_ALPINE_SKIP_GIT_SETUP:-no}" = "yes" ]; then
    echo "[git] setup_git_workflow skipped (prod)"
    return 0
  fi
  if ! command -v git >/dev/null 2>&1; then
    echo "[git] git not found, skipping workflow setup"
    return 0
  fi
  # original dev logic here (if any) - keep no-op for prod
  echo "[git] Ensuring git workflow"
  return 0
}

# other helpers if needed - keep existing ones
ensure_koha_paths(){
  mkdir -p /etc/koha/sites /var/lib/koha /var/log/koha /var/run/koha /var/cache/koha
  chown -R kohadev:kohadev /var/lib/koha /var/log/koha /var/run/koha /var/cache/koha 2>/dev/null || true
}

# Export
export -f setup_git_workflow 2>/dev/null || true
