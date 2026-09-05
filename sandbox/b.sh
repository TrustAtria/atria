#!/usr/bin/env bash
# sandbox.md — The Execution workflow, part B: business calls through the
# proxy, decided by HTTP method and by payload, with two live policy edits.
#
# Five steps, each its own script so you can repeat one by hand:
#   b1.sh  a mock session token through the proxy
#   b2.sh  decided by method              (GET ok, DELETE blocked)
#   b3.sh  decided by payload             (max_transaction_value, any depth)
#   b4.sh  raise the ceiling, live reload
#   b5.sh  add the heuristic value_guard, live reload
#
# b4 and b5 edit /etc/atria/policies.yaml and the steps are ordered — to
# redo one from a clean policy, restart the container (or restore the file).
# This runs them in order and stops at the first failure.
cd "$(dirname "$(readlink -f "$0")")"
set -Eeuo pipefail

rc=0
for n in 1 2 3 4 5; do
  ./"b$n.sh" || { rc=$?; echo "B$n exited $rc — stopping." >&2; break; }
  # BRIEF drops the narration between steps, so a recording gets an explicit
  # beat here instead — longer than briefpause's per-line 0.5s, this is
  # between whole steps.
  [ -n "${ABC_BRIEF:-}" ] && sleep 2
done
exit "$rc"
