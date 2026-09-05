#!/bin/sh
# Starts the one service in this image — the real atria-proxy debian
# package — pointed at the TA sandbox (https://sandbox.trustatria.com),
# then hands you a shell with the a/b/c scripts, or runs them once.
#
#   docker run -it  <image>          shell; run ./abc.sh or ./abc.sh -i
#   docker run --rm <image> batch    run abc.sh end to end, exit with its status
#   docker run --rm <image> abc.sh -i   any abc.sh argument works here too
#
# Everything else the walkthrough touches — register, session, the CA, the
# CRL, revoke, and the mock business-logic endpoints (/mock-*) — is the
# real sandbox, reached over the network. Nothing else runs in here.
set -eu

KIT=/opt/abc
SANDBOX=${ABC_SANDBOX_URL:-https://sandbox.trustatria.com}
mode=${1:-shell}

mkdir -p /etc/atria /var/log/atria
cp "$KIT/policies.yaml" /etc/atria/policies.yaml
cp "$KIT/rates.yaml"    /etc/atria/rates.yaml

# Baked at build time (publish.sh), all required for mTLS + proof:
#   atria-ca.pem   — the TA CA public cert (validates client certs; public)
#   proxy-cert.pem — this proxy's server cert, Atria-CA-issued, SAN covers
#                    127.0.0.1 / localhost (sandbox.md L14)
#   proxy-key.pem  — its key
for f in atria-ca.pem proxy-cert.pem proxy-key.pem; do
  [ -s "$KIT/$f" ] || { echo "entrypoint  no $KIT/$f in the image — the build must bake it (publish.sh)" >&2; exit 1; }
  cp "$KIT/$f" "/etc/atria/$f"
done
chmod 0640 /etc/atria/proxy-key.pem

set -a
. "$KIT/env"
set +a

/usr/bin/atria-proxy >/var/log/atria/proxy.log 2>&1 &
PROXY_PID=$!
trap 'kill "$PROXY_PID" 2>/dev/null || true' EXIT

i=0
while [ "$i" -lt 30 ]; do
  curl -fsS -o /dev/null http://127.0.0.1:8081/admin/version 2>/dev/null && break
  i=$((i + 1)); sleep 1
done
[ "$i" -lt 30 ] || { echo "entrypoint  atria-proxy did not come up in 30s" >&2; cat /var/log/atria/proxy.log >&2; exit 1; }
echo "entrypoint  atria-proxy $(curl -fsS http://127.0.0.1:8081/admin/version | sed 's/[{}\"]//g') -> $SANDBOX"
echo

cd "$KIT"
[ $# -gt 0 ] && shift || true
case "$mode" in
  shell)
    cat <<BANNER

  ───────────────────────────────────────────────────────────────────────
  The Atria proxy is up in this container, pointed at
  $SANDBOX. register / session / CA / CRL / revoke and
  the mock business logic (/mock-*) are all that sandbox, over the network.

    ./abc.sh          the sandbox.md walkthrough, A then B then C
    ./abc.sh -i       the same, pausing before each call so you can read it
    ./a.sh  ./b.sh  ./c.sh    one part at a time
    ./b1.sh .. ./b5.sh        one B step at a time — repeat any of them

  Every call is plain curl against the real proxy or the real sandbox —
  copy any line and change it.
  ───────────────────────────────────────────────────────────────────────

BANNER
    exec "${SHELL:-/bin/bash}"
    ;;
  batch)
    exec ./abc.sh "$@"
    ;;
  a.sh|b.sh|b[1-5].sh|c.sh|abc.sh)
    exec ./"$mode" "$@"
    ;;
  *)
    exec ./abc.sh "$mode" "$@"
    ;;
esac
