#!/usr/bin/env bash
# sandbox.md — The Execution workflow, part C: revoke the certificate and
# see which side of the boundary reacts. Needs what a.sh and b.sh left in
# $ABC_STATE.
cd "$(dirname "$(readlink -f "$0")")"
. ./lib.sh
: "${ABC_FAILED:=0}"
require agent-cert.pem agent-key.pem mock-jwt agent-id
JWT=$(cat "$ABC_STATE/mock-jwt")
AGENT_ID=$(cat "$ABC_STATE/agent-id")

step "C1  the backend, reached directly, on its own token"
say "Straight to the backend, no proxy in the path, carrying only the mock"
say "session token from part A/B. It works — the backend enforces its own"
say "session and nothing else. Hold this result: it is the control for"
say "everything below."
ta_call POST "$ABC_BACKEND/mock-bl" '{"note":"direct, control"}' -H "authorization: Bearer $JWT"
[ "$ABC_STATUS" = 200 ] && ok "direct POST /mock-bl -> 200" || bad "direct POST /mock-bl -> $ABC_STATUS ${ABC_ERROR}"
beat
pause

step "C2  revoke the certificate — self-revoke at register.trustatria.com"
say "Revoking is done where issuance is. No API key, no operator session:"
say "the call carries a TA-Authorization proof signed by the certificate's"
say "own key — the same header the proxy checks — and register-bo verifies"
say "it against the TA CA public key with no secret. Only this one"
say "certificate goes on the CRL; the shipped API key and the agent stay"
say "live. Accepted only for a sandbox-scoped cert. The proxy does not know"
say "yet."
REV_URL="$ABC_CLOUD/session/revoke"
REV_BODY='{"reason":"superseded"}'
ta_call POST "$REV_URL" "$REV_BODY" -H "TA-Authorization: $(ta_sign POST "$REV_URL" "$REV_BODY")"
if [ "$ABC_STATUS" = 200 ]; then
  ok "revoked $AGENT_ID's certificate — serial $(jget "$ABC_STATE/body" .serial), $(jget "$ABC_STATE/body" .certificates_revoked) certificate(s); API key still live"
else
  bad "POST /session/revoke -> $ABC_STATUS ${ABC_ERROR}"; exit 1
fi
beat
pause

step "C3  the proxy still lets it through — it is serving a stale list"
say "The proxy verifies offline against a cached revocation list and only"
say "refreshes on an interval. Until it does, the revoked certificate keeps"
say "working. That window is the cost of not calling home per request, and"
say "it is bounded, not open-ended."
ta_bl POST '{"note":"after revoke, before pull"}'
[ "$ABC_STATUS" = 200 ] \
  && note "POST /mock-bl through the proxy: still 200 — the new list has not been pulled" \
  || note "POST /mock-bl through the proxy: $ABC_STATUS ${ABC_ERROR} (the interval pull may have already run)"
beat
pause

step "C4  tell the proxy to pull the new list"
say "In a real deployment this happens on a timer. Here we force it so the"
say "walkthrough does not wait."
ta_call POST "$ABC_ADMIN/admin/crl/pull"
note "pull -> $ABC_STATUS  (revoked serials now on the proxy's list: $(jget "$ABC_STATE/body" '.revoked // "?"'))"
beat
pause

step "C5  now the boundary reacts — and only the boundary"
say "Same signed call through the proxy: refused. The certificate is still"
say "cryptographically valid; the list is what stops it."
ta_bl POST '{"note":"after the pull"}'
[ "$ABC_STATUS" = 403 ] && [ "$ABC_ERROR" = CERTIFICATE_REVOKED ] \
  && ok  "through the proxy -> 403 CERTIFICATE_REVOKED" \
  || bad "through the proxy -> $ABC_STATUS ${ABC_ERROR}  (expected 403 CERTIFICATE_REVOKED)"

say ""
say "The same direct call, unchanged: still 200. The backend was never told"
say "about the revocation — the proxy is the thing that enforces it."
ta_call POST "$ABC_BACKEND/mock-bl" '{"note":"direct, after revoke+pull"}' -H "authorization: Bearer $JWT"
[ "$ABC_STATUS" = 200 ] && ok "direct POST /mock-bl -> 200 (unchanged)" || bad "direct POST /mock-bl -> $ABC_STATUS ${ABC_ERROR}"
beat
pause

step "C6  log out"
say "The backend keeps no server-side session — the token is entirely in"
say "the caller's hand — so logout has nothing to end and answers 200. It"
say "still requires the token (you have to be logged in to log out)."
ta_call POST "$ABC_BACKEND/mock-logout" '' -H "authorization: Bearer $JWT"
[ "$ABC_STATUS" = 200 ] && ok "POST /mock-logout -> 200" || bad "POST /mock-logout -> $ABC_STATUS ${ABC_ERROR}"
note "sandbox.md expects logout to also end the direct session; the mock"
note "backend (matching crates/mock-target A-52) does not invalidate the"
note "token — a known gap between sandbox.md and what mock-target ships."

step "C done — the whole point in one line"
say "Revocation reached the proxy and stopped the call there; the backend,"
say "which only ever checked its own token, kept answering. Enforcement is"
say "the proxy's job, and it stayed the proxy's job."
exit "${ABC_FAILED:-0}"
