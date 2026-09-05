#!/usr/bin/env bash
# Shared plumbing for a.sh / b.sh / c.sh — the three parts of the sandbox
# walkthrough in trust-atria-project/sandbox.md. Source it, do not run it.
set -Eeuo pipefail

# The only service in the container is the proxy, on loopback. The two real
# sandbox services it talks to, per sandbox.md:
#   register.trustatria.com  — register / session / revoke / CRL (register-bo,
#                              the real atria-ca, Postgres-backed)
#   sandbox.trustatria.com   — the mock business logic (/mock-login, /mock-bl,
#                              /mock-logout), what the proxy forwards to
ABC_REGISTER=${ABC_REGISTER:-https://register.trustatria.com/api}
ABC_SANDBOX=${ABC_SANDBOX:-https://sandbox.trustatria.com}
ABC_CLOUD=${ABC_CLOUD:-$ABC_REGISTER}             # register / session / session/revoke
ABC_BACKEND=${ABC_BACKEND:-$ABC_SANDBOX}          # the mock business logic, reached directly (not through the proxy)
ABC_PROXY=${ABC_PROXY:-https://127.0.0.1:8443}    # the atria-proxy in this container — mTLS (HTTPS + client cert)
ABC_ADMIN=${ABC_ADMIN:-http://127.0.0.1:8081}     # that proxy's own admin port
ABC_PUBLIC_URL=${ABC_PUBLIC_URL:-$ABC_PROXY}      # the origin a proof is bound to; must match the proxy's ATRIA_PUBLIC_URL

# The shipped sandbox API key (sandbox.md §2, "sandbox ship with API key").
# A sandbox-scoped key minted once on register.trustatria.com and baked into
# the image; A2 uses it instead of registering per run.
ABC_API_KEY_FILE=${ABC_API_KEY_FILE:-$(dirname "${BASH_SOURCE[0]}")/api-key}

# State carried between the three scripts (the certificate from A is what B
# and C sign with). Each script can also run on its own — it re-reads what
# an earlier one left here.
ABC_STATE=${ABC_STATE:-${TMPDIR:-/tmp}/atria-abc}
mkdir -p "$ABC_STATE"

# -i on the wrapper sets this; a bare a/b/c run leaves it empty and never
# blocks.
ABC_INTERACTIVE=${ABC_INTERACTIVE:-}

# ABC_BRIEF=1 drops the narration (say/note) and keeps only step headers and
# the ok/BAD result of every call — a ~1/5 transcript for a recording or a
# quick review. The calls made and the assertions are identical.
ABC_BRIEF=${ABC_BRIEF:-}

_b=$(printf '\033[1m'); _d=$(printf '\033[2m'); _g=$(printf '\033[32m'); _r=$(printf '\033[31m'); _o=$(printf '\033[0m')
[ -t 1 ] || { _b=; _d=; _g=; _r=; _o=; }

# briefpause — under ABC_BRIEF, a beat after every line that still prints
# (step/ok/bad/wire — say/note are dropped entirely, see below). BRIEF
# narration is gone, so a recording has nothing else giving a reader time
# to read a result before the next one appears.
briefpause() { [ -n "${ABC_BRIEF:-}" ] && sleep 0.5; return 0; }

# say — a line of explanation for the person watching. This is where the
# walkthrough is narrated; the code stays terse on purpose so the two do
# not drift.
say()  { [ -n "$ABC_BRIEF" ] || printf '%s\n' "$*"; }
step() { printf '\n%s— %s —%s\n' "$_b" "$*" "$_o"; briefpause; }
note() { [ -n "$ABC_BRIEF" ] || printf '   %s%s%s\n' "$_d" "$*" "$_o"; }
ok()   { printf '   %sok%s  %s\n'  "$_g" "$_o" "$*"; briefpause; }
bad()  { printf '   %sBAD%s %s\n'  "$_r" "$_o" "$*"; ABC_FAILED=1; briefpause; }

# wire — the full URL of the call about to be made, printed on every call
# (BRIEF too), so the transcript names the exact host each request went to.
# ta_through_proxy sets ABC_FWD first; the line then shows both hops:
#   · POST https://127.0.0.1:8443/mock-bl  ->  https://sandbox.trustatria.com/mock-bl
wire() {
  local l="$1 $2"
  [ -n "${ABC_FWD:-}" ] && l="$l  ->  $ABC_FWD"
  printf '   %s· %s%s\n' "$_d" "$l" "$_o"
  briefpause
}

# Interactive pause. Batch runs skip it; -i stops so the reader can look at
# what just happened before the next call is made.
pause() {
  [ -n "$ABC_INTERACTIVE" ] || return 0
  printf '%s   [enter] to continue%s ' "$_d" "$_o"
  read -r _ || true
}

# beat — a short wait between steps so a non-interactive run (a recording)
# does not blur one into the next. Interactive runs pause on a keypress
# instead, so it does nothing there. ABC_BEAT overrides the 1.5s default.
beat() { [ -n "$ABC_INTERACTIVE" ] || sleep "${ABC_BEAT:-1.5}"; }

# ta_call METHOD URL [json-body] [curl-args...]
# Makes the call, leaves the body in $ABC_STATE/body and the HTTP status in
# $ABC_STATUS, the parsed `error` field (if any) in $ABC_ERROR.
ta_call() {
  local method=$1 url=$2 body=${3:-}
  shift; shift; [ $# -gt 0 ] && shift || true
  wire "$method" "$url"
  local args=(-sS -o "$ABC_STATE/body" -w '%{http_code}' -X "$method" --path-as-is)
  [ -n "$body" ] && args+=(-H 'content-type: application/json' --data "$body")
  ABC_STATUS=$(curl "${args[@]}" "$@" "$url" 2>"$ABC_STATE/curl.err") || ABC_STATUS=000
  ABC_ERROR=$(jq -r '.error // empty' <"$ABC_STATE/body" 2>/dev/null || true)
  ABC_FWD=
}

# jget FILE FILTER — read one value out of a saved JSON response.
jget() { jq -r "$2" <"$1"; }

# ta_sign METHOD FULL-URL [BODY]
# Prints the compact ES256 JWS that goes in the TA-Authorization header:
# the certificate from A travels inside it (x5c), and the claims bind this
# exact method, URL and body so a copied header is useless on anything
# else. One proof is one request — call this again for the next.
ta_sign() {
  python3 "$(dirname "${BASH_SOURCE[0]}")/jws-es256.py" \
    --cert "$ABC_STATE/agent-cert.pem" --key "$ABC_STATE/agent-key.pem" \
    --method "$1" --url "$2" --body "${3:-}"
}

# ta_through_proxy METHOD PATH [BODY] [extra curl args...]
# curl args for the mTLS connection to the proxy: pin its CA, and present
# the agent certificate once a.sh has one. PROXY_TLS is a global array the
# proxy-facing helpers splice in.
proxy_tls() {
  PROXY_TLS=(--cacert "$ABC_STATE/atria-ca.pem")
  [ -s "$ABC_STATE/agent-cert.pem" ] && PROXY_TLS+=(--cert "$ABC_STATE/agent-cert.pem" --key "$ABC_STATE/agent-key.pem")
}

# One call at the boundary: mTLS with the agent cert, plus a fresh
# TA-Authorization proof (what a TLS-terminated deployment would check).
# Records the outcome like ta_call. The proof binds the URL without its
# query string (agent.md: `htu` has no query).
ta_through_proxy() {
  local method=$1 path=$2 body=${3:-}; shift; shift; [ $# -gt 0 ] && shift || true
  local proof; proof=$(ta_sign "$method" "$ABC_PUBLIC_URL${path%%\?*}" "$body")
  proxy_tls
  # local hop is $ABC_PROXY$path; the proxy forwards path-for-path to its
  # upstream ($ABC_SANDBOX, = ATRIA_UPSTREAM_URL) — wire shows both.
  ABC_FWD="${ABC_SANDBOX}${path}"
  ta_call "$method" "$ABC_PROXY$path" "$body" "${PROXY_TLS[@]}" -H "TA-Authorization: $proof" "$@"
}

# ta_bl METHOD [BODY] — /mock-bl through the proxy, carrying both credentials
# it needs: the TA-Authorization proof for the proxy, and the mock session
# token (from $ABC_STATE/mock-jwt) as the bearer the backend checks.
ta_bl() {
  ta_through_proxy "$1" /mock-bl "${2:-}" -H "authorization: Bearer $(cat "$ABC_STATE/mock-jwt")"
}

require() {
  for f in "$@"; do
    [ -s "$ABC_STATE/$f" ] && continue
    case "$f" in
      mock-jwt) say "missing $ABC_STATE/$f — run ./b1.sh first (it gets the mock session token)" ;;
      *)        say "missing $ABC_STATE/$f — run ./a.sh first (it enrols and leaves the certificate here)" ;;
    esac
    exit 1
  done
}

# --- part B helpers ---------------------------------------------------
# A payment-shaped body. `transaction_value` is the number the proxy weighs;
# `currency` and `memo` ride along untouched — it bounds one numeric field
# wherever it appears and does not read the currency. `nested` hides the same
# field a level down.
pay()    { printf '{"memo":"part B","currency":"usd","transaction_value":%s}' "$1"; }
nested() { printf '{"order":{"currency":"usd","transaction_value":%s}}' "$1"; }

# expect METHOD BODY  WANT_STATUS  WANT_ERROR  EXPLANATION
# One /mock-bl call through the proxy, asserted. WANT_ERROR "" means "do not
# check the error field". Records a pass/fail into ABC_FAILED like bad().
expect() {
  ta_bl "$1" "$2"
  if [ "$ABC_STATUS" = "$3" ] && { [ -z "$4" ] || [ "$ABC_ERROR" = "$4" ]; }; then
    ok "$1 /mock-bl -> $ABC_STATUS ${ABC_ERROR:+$ABC_ERROR }  $5"
  else
    bad "$1 /mock-bl -> $ABC_STATUS ${ABC_ERROR}  (wanted $3 $4)"
  fi
}
