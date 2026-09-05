#!/usr/bin/env bash
# sandbox.md — Execution workflow B1: get a mock session token through the
# proxy. Leaves it in $ABC_STATE/mock-jwt for B2-B5. Needs the certificate
# a.sh enrolled. Runnable on its own.
cd "$(dirname "$(readlink -f "$0")")"
. ./lib.sh
: "${ABC_FAILED:=0}"
require agent-cert.pem agent-key.pem

step "B1  get a mock session token through the proxy"
say "POST /mock-login, proxied. Any login and password, each at least six"
say "characters; the login becomes the token's name. This token is the"
say "backend's own — Atria never issues or reads it."
ta_through_proxy POST /mock-login '{"login":"abc-demo","password":"abc-demo-pw"}'
if [ "$ABC_STATUS" = 200 ]; then
  jget "$ABC_STATE/body" .token >"$ABC_STATE/mock-jwt"
  ok "mock session token saved"
else
  bad "POST /mock-login through the proxy returned $ABC_STATUS ${ABC_ERROR}"
  [ "$ABC_STATUS" = 401 ] && say "   401 here means the proof did not verify — is ABC_PUBLIC_URL the same origin the proxy was told (ATRIA_PUBLIC_URL)?"
  exit 1
fi
beat
pause
exit "${ABC_FAILED:-0}"
