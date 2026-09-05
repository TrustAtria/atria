#!/usr/bin/env bash
# Run the sandbox.md walkthrough without Docker: start a locally-built
# atria-proxy pointed at the real TA sandbox (https://sandbox.trustatria.com),
# run abc.sh, tear it down. Same as the image, a faster loop while working
# on the scripts or the proxy. Needs network to the sandbox.
#
#   ./run-local.sh            run a.sh b.sh c.sh, tear down, exit with the verdict
#   ./run-local.sh -i         pass through to abc.sh (interactive)
#   ./run-local.sh a b        a subset
#
# atria-proxy comes from $ATRIA_PROXY_BIN, else `atria-proxy` on PATH, else
# this repo's release build (rebuilt if stale unless ABC_SKIP_BUILD=1).
set -Eeuo pipefail
SELF="$(readlink -f "$0")"; cd "$(dirname "$SELF")"
REPO_ROOT=$(cd ../.. && pwd)

SANDBOX=${ABC_SANDBOX:-https://sandbox.trustatria.com}
REGISTER=${ABC_REGISTER:-https://register.trustatria.com/api}
PROXY_PORT=${ABC_PORT_PROXY:-18443}
ADMIN_PORT=${ABC_PORT_ADMIN:-18081}

PROXY_BIN=${ATRIA_PROXY_BIN:-}
if [ -z "$PROXY_BIN" ]; then
  PROXY_BIN=$(command -v atria-proxy || echo "$REPO_ROOT/target/release/atria-proxy")
  if [ "$PROXY_BIN" = "$REPO_ROOT/target/release/atria-proxy" ] && [ -z "${ABC_SKIP_BUILD:-}" ]; then
    before=$(sha256sum "$PROXY_BIN" 2>/dev/null | cut -c1-16 || echo none)
    ( cd "$REPO_ROOT" && cargo build --release -p atria-proxy --quiet )
    after=$(sha256sum "$PROXY_BIN" 2>/dev/null | cut -c1-16 || echo none)
    [ "$before" != "$after" ] && echo "==> rebuilt atria-proxy ($before -> $after)"
  fi
fi
[ -x "$PROXY_BIN" ] || { echo "no atria-proxy binary — build it (cargo build --release -p atria-proxy) or set ATRIA_PROXY_BIN" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/abc-local.XXXXXX")
mkdir -p "$WORK/state"
PIDS=(); rc=1
cleanup() {
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done
  wait 2>/dev/null || true
  if [ "$rc" = 0 ]; then rm -rf "$WORK"; else echo "logs kept in $WORK"; fi
}
trap cleanup EXIT

wait_for() { local i=0; while [ $i -lt 40 ]; do curl -fsS -o /dev/null "$1" 2>/dev/null && return 0; i=$((i+1)); sleep 0.25; done; echo "  $2 did not come up ($1)" >&2; exit 1; }

CA_PEM=${ABC_CA_PEM:-./atria-ca.pem}
PROXY_CERT=${ABC_PROXY_CERT:-./proxy-cert.pem}
PROXY_KEY=${ABC_PROXY_KEY:-./proxy-key.pem}
for p in "$CA_PEM" "$PROXY_CERT" "$PROXY_KEY"; do
  [ -s "$p" ] || { echo "missing $p — need atria-ca.pem + the proxy server cert/key (sandbox.md L14)" >&2; exit 1; }
done
cp "$CA_PEM" "$WORK/atria-ca.pem"; cp "$PROXY_CERT" "$WORK/proxy-cert.pem"; cp "$PROXY_KEY" "$WORK/proxy-key.pem"

echo "==> atria-proxy (mTLS + TA-Authorization proof) on :$PROXY_PORT -> $SANDBOX  ($PROXY_BIN)"
cp ./policies.yaml "$WORK/policies.yaml"      # b.sh edits this copy, not the tracked file
cp ./rates.yaml    "$WORK/rates.yaml"
env -i PATH="$PATH" HOME="$HOME" \
  ATRIA_AUTH_MODE=mtls \
  ATRIA_LISTEN_ADDR="127.0.0.1:$PROXY_PORT" \
  ATRIA_PUBLIC_URL="https://127.0.0.1:$PROXY_PORT" \
  ATRIA_TLS_CERT="$WORK/proxy-cert.pem" \
  ATRIA_TLS_KEY="$WORK/proxy-key.pem" \
  ATRIA_UPSTREAM_URL="$SANDBOX" \
  ATRIA_CA_CERT="$WORK/atria-ca.pem" \
  ATRIA_DEPLOYMENT=sandbox \
  ATRIA_POLICY_FILE="$WORK/policies.yaml" \
  ATRIA_RATES_FILE="$WORK/rates.yaml" \
  ATRIA_CRL_URL="$REGISTER/internal/crl" \
  CRL_PULL_INTERVAL=5s \
  ATRIA_REPORT_URL="$REGISTER/internal/report" \
  ATRIA_AUDIT_LOG="$WORK/audit.log" \
  ATRIA_ADMIN_ADDR="127.0.0.1:$ADMIN_PORT" \
  RUST_LOG=warn \
  "$PROXY_BIN" >"$WORK/proxy.log" 2>&1 & PIDS+=($!)
wait_for "http://127.0.0.1:$ADMIN_PORT/admin/version" "proxy"

echo "==> running the walkthrough"
echo
set +e
ABC_STATE="$WORK/state" \
ABC_POLICY_FILE="$WORK/policies.yaml" \
ABC_SANDBOX="$SANDBOX" \
ABC_REGISTER="$REGISTER" \
ABC_CA_PEM="$WORK/atria-ca.pem" \
ABC_PROXY="https://127.0.0.1:$PROXY_PORT" \
ABC_ADMIN="http://127.0.0.1:$ADMIN_PORT" \
ABC_PUBLIC_URL="https://127.0.0.1:$PROXY_PORT" \
ABC_BRIEF=1 ./abc.sh "$@"
rc=$?
set -e

echo
[ $rc -ne 0 ] && { echo "--- proxy.log tail ---"; tail -n 25 "$WORK/proxy.log"; }
exit $rc
