#!/usr/bin/env bash
# sandbox.md — The Execution workflow, part A: get an identity and learn to
# present it. Leaves the certificate in $ABC_STATE for b.sh and c.sh.
cd "$(dirname "$(readlink -f "$0")")"
. ./lib.sh
: "${ABC_FAILED:=0}"

AGENT_ID=${ABC_AGENT_ID:-abc-agent}

step "A1  pin the CA the proxy trusts"
say "Everything Atria signs chains to one certificate. It ships in the"
say "image (the proxy pins the same file), so verifying any certificate it"
say "issues needs no call to the cloud on the hot path."
CA_PEM=${ABC_CA_PEM:-$(dirname "$(readlink -f "$0")")/atria-ca.pem}
if [ -s "$CA_PEM" ]; then
  cp "$CA_PEM" "$ABC_STATE/atria-ca.pem"
  ok "CA pinned from $CA_PEM"
else
  bad "no CA cert at $CA_PEM — publish.sh fetches it, or set ABC_CA_PEM"; exit 1
fi
beat
pause

step "A2  the API key — it ships with this image"
say "sandbox.md: 'sandbox ship with API key'. It was registered once against"
say "$ABC_CLOUD/register and baked in; it is valid only for this sandbox and"
say "only to mint a short-lived certificate. A real agent would call"
say "register.trustatria.com itself, on the user's behalf."
if [ -s "$ABC_API_KEY_FILE" ]; then
  cp "$ABC_API_KEY_FILE" "$ABC_STATE/api-key"
  ok "using the shipped key ($ABC_API_KEY_FILE)"
else
  say "no shipped key — registering one now (run ./register-key.sh to bake it in)"
  ta_call POST "$ABC_CLOUD/register" "{\"agent_id\":\"$AGENT_ID\"}"
  if [ "$ABC_STATUS" = 201 ] || [ "$ABC_STATUS" = 200 ]; then
    jget "$ABC_STATE/body" .api_key >"$ABC_STATE/api-key"
    ok "api_key issued for $AGENT_ID"
  else
    bad "POST /register returned $ABC_STATUS ${ABC_ERROR}"; exit 1
  fi
fi
beat
pause

step "A3  spend the key on a short-lived certificate"
say "Bearer the api_key. Back comes an X.509 certificate and its private"
say "key — minutes to hours, not years. The short life is the blast-radius"
say "limiter: a stolen certificate stops working on its own."
ta_call POST "$ABC_CLOUD/session" '{}' -H "authorization: Bearer $(cat "$ABC_STATE/api-key")"
if [ "$ABC_STATUS" = 201 ] || [ "$ABC_STATUS" = 200 ]; then
  jget "$ABC_STATE/body" .certificate_pem >"$ABC_STATE/agent-cert.pem"
  jget "$ABC_STATE/body" .private_key_pem >"$ABC_STATE/agent-key.pem"
  printf '%s' "$AGENT_ID" >"$ABC_STATE/agent-id"
  ok "certificate for $AGENT_ID — serial $(jget "$ABC_STATE/body" .serial), expires $(jget "$ABC_STATE/body" .not_after)"
else
  bad "POST /session returned $ABC_STATUS ${ABC_ERROR}"
  [ "$ABC_STATUS" = 401 ] && say "   the shipped key may have lapsed (90-day TTL) or be missing — re-mint with ./register-key-db.sh (or ./register-key.sh --force). Part C is cert-only self-revoke now; it does not touch the key."
  exit 1
fi
beat
pause

step "A4  the proxy requires the certificate AND a signed proof; the BL does neither"
say "Identity is the Atria certificate, presented two ways at once: at the"
say "TLS handshake (mTLS) and inside a signed TA-Authorization header on"
say "every request. The proxy requires both, validates the header's"
say "signature against the pinned CA public key with no secret, checks the"
say "two name the same certificate, and re-checks the CRL per request. The"
say "BL checks only its own session token."
say ""
say "First without the certificate: the handshake itself is refused."
ta_call POST "$ABC_PROXY/mock-login" '{"login":"abc-demo","password":"abc-demo-pw"}' --cacert "$ABC_STATE/atria-ca.pem"
if [ "$ABC_STATUS" = 000 ]; then
  ok "refused at the TLS handshake — no client certificate ($(tr -d '\n' <"$ABC_STATE/curl.err" | tail -c 90))"
else
  bad "expected the handshake to fail without a client cert, got $ABC_STATUS"
fi
beat
pause

say "Now with the certificate but no TA-Authorization header: past the"
say "handshake, refused by the proxy. The certificate alone is not enough."
proxy_tls
ta_call POST "$ABC_PROXY/mock-login" '{"login":"abc-demo","password":"abc-demo-pw"}' "${PROXY_TLS[@]}"
if [ "$ABC_STATUS" = 401 ] && [ "$ABC_ERROR" = INVALID_PROOF ]; then
  ok "through the handshake, then refused — 401 INVALID_PROOF, no proof header"
else
  bad "expected 401 INVALID_PROOF with a cert but no proof, got $ABC_STATUS ${ABC_ERROR}"
fi
beat
pause

say "Now both — the certificate and a fresh proof. mock-login asks for no"
say "Atria credential — a real customer login never does — so a 200 is the"
say "proxy letting it through on the cert and the proof, not the BL checking"
say "anything."
ta_through_proxy POST /mock-login '{"login":"abc-demo","password":"abc-demo-pw"}'
if [ "$ABC_STATUS" = 200 ]; then
  jget "$ABC_STATE/body" .token >"$ABC_STATE/mock-jwt"
  ok "through the proxy, then through the backend — mock session token saved for part B"
else
  bad "expected 200 with cert + proof, got $ABC_STATUS ${ABC_ERROR}"
fi

step "A done"
say "You hold: an Atria certificate ($ABC_STATE/agent-cert.pem) and the mock"
say "backend's own session token ($ABC_STATE/mock-jwt). Part B uses both."
exit "${ABC_FAILED:-0}"
