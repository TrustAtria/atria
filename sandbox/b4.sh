#!/usr/bin/env bash
# sandbox.md — Execution workflow B4: raise max_transaction_value with a
# live reload, no restart. Edits $ABC_POLICY_FILE (default
# /etc/atria/policies.yaml). Needs the certificate (a.sh) and the mock
# token (b1.sh). Re-runnable — it sets the ceiling to 10000 whatever it was.
cd "$(dirname "$(readlink -f "$0")")"
. ./lib.sh
: "${ABC_FAILED:=0}"
require agent-cert.pem agent-key.pem mock-jwt

POLICY=${ABC_POLICY_FILE:-/etc/atria/policies.yaml}

step "B4  the ceiling is yours to move"
say "max_transaction_value in policies.yaml is the filter the client owns."
say "Raise it, apply the edit with no restart, and the call that was"
say "refused on its amount goes through — while DELETE, never granted,"
say "stays refused."
if [ ! -w "$POLICY" ]; then
  note "policy file $POLICY is not writable from here."
  note "raise max_transaction_value in it, then reload:  curl -sS -X POST $ABC_ADMIN/admin/policy/reload"
  note "and re-run this script to watch the 5000 call flip to 200."
  exit "${ABC_FAILED:-0}"
fi

before=$(grep -oE 'max_transaction_value:[[:space:]]*[0-9.]+' "$POLICY" | grep -oE '[0-9.]+$')
note "max_transaction_value is $before — raising it to 10000.0"
sed -i -E 's/(max_transaction_value:[[:space:]]*)[0-9.]+/\110000.0/' "$POLICY"
ta_call POST "$ABC_ADMIN/admin/policy/reload"
note "reload -> $ABC_STATUS  (a document that fails to parse is refused and the old policy stays in force)"

expect POST "$(pay 5000)" 200 ""                    "5000 usd — now under the new ceiling"
expect DELETE ''          403 ENDPOINT_NOT_ALLOWED  "still not a granted method — the amount was never the only gate"
beat
pause
exit "${ABC_FAILED:-0}"
