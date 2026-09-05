#!/usr/bin/env bash
# Mint the sandbox API key the image ships (sandbox.md §2). It is a
# sandbox-scoped key on register.trustatria.com, and register-bo's
# POST /register is gated on a signed-in operator (CurrentUser) — this is a
# human/operator action, run once, not something the container does.
#
#   OPERATOR_COOKIE='sid=...' ./register-key.sh          # with an operator session
#   ./register-key.sh --check                            # just validate ./api-key against /session
#
# The result is written to ./api-key (plaintext, shown once by /register)
# and baked into the image. Sandbox-scoped: it can only mint sandbox certs.
set -Eeuo pipefail
cd "$(dirname "$(readlink -f "$0")")"

REGISTER=${ABC_REGISTER:-https://register.trustatria.com/api}
AGENT_ID=${ABC_AGENT_ID:-abc-agent}
SCOPE=${ABC_SCOPE:-sandbox}
OUT=api-key

if [ "${1:-}" = --check ]; then
  [ -s "$OUT" ] || { echo "no $OUT" >&2; exit 1; }
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$REGISTER/session" \
    -H "authorization: Bearer $(cat "$OUT")" -H 'content-type: application/json' -d '{}')
  echo "POST $REGISTER/session -> $code"
  [ "$code" = 200 ] || [ "$code" = 201 ]
  exit $?
fi

if [ -s "$OUT" ] && [ "${1:-}" != --force ]; then
  echo "$OUT already present — --force to replace, --check to test it"
  exit 0
fi

[ -n "${OPERATOR_COOKIE:-}" ] || {
  cat >&2 <<'EOF'
register-bo POST /register needs a signed-in operator. Either:
  - sign in on register.trustatria.com, copy the session cookie, and
    re-run:  OPERATOR_COOKIE='<cookie>' ./register-key.sh
  - or, on the deployment box, INSERT the key into the registerta DB with a
    real accounts.user_id and secret_hash = sha256hex(secret) for a
    plaintext of the form  atria_<id>_<secret>  (see
    trust-atria-srv/crates/atria-ca/src/apikey.rs).
Then place the plaintext in ./api-key.
EOF
  exit 1
}

echo "minting a '$SCOPE'-scoped key for '$AGENT_ID' at $REGISTER/register"
body=$(curl -fsS -X POST "$REGISTER/register" \
  -H "cookie: $OPERATOR_COOKIE" -H 'content-type: application/json' \
  --data "{\"agent_id\":\"$AGENT_ID\",\"scope\":\"$SCOPE\",\"label\":\"docker sandbox image\"}")

key=$(printf '%s' "$body" | jq -r '.api_key // empty')
[ -n "$key" ] || { echo "no api_key in the response: $body" >&2; exit 1; }

printf '%s' "$key" >"$OUT"
chmod 0644 "$OUT"
echo "wrote $OUT  (key_id $(printf '%s' "$body" | jq -r '.key_id'), expires in $(printf '%s' "$body" | jq -r '.expires_in_days // "?"') days)"
echo "NOTE: this key has a TTL — re-mint and re-publish before it lapses (trust-atria-srv#20)"
