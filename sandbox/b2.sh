#!/usr/bin/env bash
# sandbox.md — Execution workflow B2: the policy decides by HTTP method.
# Needs the certificate (a.sh) and the mock token (b1.sh). Runnable on its
# own; re-runnable.
cd "$(dirname "$(readlink -f "$0")")"
. ./lib.sh
: "${ABC_FAILED:=0}"
require agent-cert.pem agent-key.pem mock-jwt

step "B2  the policy decides by method"
say "Every verb hits the same handler, and the policy names each one it"
say "allows on its own line. GET is granted and DELETE is not; a granted"
say "call reaches the backend, a withheld one stops at the proxy and the"
say "backend never hears it."
expect GET    ''  200 ""                    "a read — nothing to weigh"
expect DELETE ''  403 ENDPOINT_NOT_ALLOWED  "this verb is not granted"
beat
pause
exit "${ABC_FAILED:-0}"
