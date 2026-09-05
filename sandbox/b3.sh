#!/usr/bin/env bash
# sandbox.md — Execution workflow B3: the policy decides by what is in the
# payload (max_transaction_value, at any depth). Needs the certificate
# (a.sh) and the mock token (b1.sh). Assumes the shipped ceiling of 1000 —
# run before b4, which raises it.
cd "$(dirname "$(readlink -f "$0")")"
. ./lib.sh
: "${ABC_FAILED:=0}"
require agent-cert.pem agent-key.pem mock-jwt

step "B3  and by what is in the payload"
say "PUT and POST are granted, and they carry a payment. The policy also"
say "sets a ceiling — max_transaction_value — and the proxy refuses any"
say "transaction_value over it, wherever in the body it sits and whatever"
say "shape it is hidden in. Same route, same method, decided on the amount."
expect POST "$(pay 250)"     200 ""                              "250 usd — under the 1000 ceiling"
expect PUT  "$(pay 999.99)"  200 ""                              "999.99 — still under"
expect POST "$(pay 5000)"    403 TRANSACTION_VALUE_EXCEEDS_LIMIT "5000 — over the ceiling"
expect POST '{"transaction_value":"5000"}' 403 TRANSACTION_VALUE_NOT_NUMERIC "a string the proxy cannot compare is one it cannot bound"
expect POST "$(nested 5000)" 403 TRANSACTION_VALUE_EXCEEDS_LIMIT "nested one level deep — checked at any depth"
beat
pause
exit "${ABC_FAILED:-0}"
