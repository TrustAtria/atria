#!/usr/bin/env bash
# sandbox.md — Execution workflow B5: add the heuristic value_guard filter
# (fuzzy money-ish field names, numeric-string coercion, currency read from
# the body and converted via ATRIA_RATES_FILE) with a live reload. Edits
# $ABC_POLICY_FILE. Needs the certificate (a.sh) and the mock token (b1.sh).
cd "$(dirname "$(readlink -f "$0")")"
. ./lib.sh
: "${ABC_FAILED:=0}"
require agent-cert.pem agent-key.pem mock-jwt

POLICY=${ABC_POLICY_FILE:-/etc/atria/policies.yaml}

step "B5  the heuristic filter — any money-ish field, any currency"
say "max_transaction_value matches one exact field name and refuses"
say "anything it cannot read. value_guard is the looser version: any field"
say "whose name contains value/amount/sum/total, numeric strings coerced,"
say "the currency read from the body and converted (ATRIA_RATES_FILE), and"
say "a matched field it cannot parse skipped — not a 4xx. Add it and reload."

if grep -q '# VALUE_GUARD_HERE' "$POLICY"; then
  sed -i 's|.*# VALUE_GUARD_HERE.*|    value_guard:\n      max: 1000.0\n      currency: USD|' "$POLICY"
  ta_call POST "$ABC_ADMIN/admin/policy/reload"
  note "value_guard added (max 1000 USD), reload -> $ABC_STATUS"
elif grep -q 'value_guard:' "$POLICY"; then
  note "value_guard is already in $POLICY — testing against it as it stands"
else
  note "no '# VALUE_GUARD_HERE' marker and no value_guard block in $POLICY —"
  note "add one by hand to try this step; the other steps are unaffected"
  beat; pause; exit "${ABC_FAILED:-0}"
fi

expect POST '{"sum":900,"currency":"eur"}'  200 ""                   "900 EUR ~= 981 USD — under"
expect POST '{"sum":950,"currency":"eur"}'  403 VALUE_LIMIT_EXCEEDED "950 EUR ~= 1035 USD — over, after conversion"
expect POST '{"gross_amount":"1,500.00"}'   403 VALUE_LIMIT_EXCEEDED "a numeric string is coerced and bounded"
expect POST '{"customer_reference_value":"acme-42"}' 200 ""          "name matches but the value will not convert — skipped, not refused"
beat
pause
exit "${ABC_FAILED:-0}"
