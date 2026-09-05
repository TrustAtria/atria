#!/usr/bin/env bash
# The sandbox.md walkthrough end to end: part A (get an identity), part B
# (business calls through the proxy, policy edits), part C (revoke, watch
# the boundary react).
#
#   ./abc.sh          run all three back to back, stop on the first failure
#   ./abc.sh -i       pause between every call so you can read what happened
#   ./abc.sh a        run just one part (a, b or c); state carries between runs
#   ./abc.sh -i b c   -i plus a subset
#
# Part B is five steps, each its own script (b1.sh … b5.sh) so you can
# repeat one by hand; ./b.sh runs them in order.
#
# ABC_STATE (default a temp dir) is where the certificate and tokens are
# kept between parts.
cd "$(dirname "$(readlink -f "$0")")"
set -Eeuo pipefail

PARTS=()
for arg in "$@"; do
  case "$arg" in
    -i|--interactive) export ABC_INTERACTIVE=1 ;;
    a|b|c)            PARTS+=("$arg") ;;
    -h|--help)        sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)               echo "unknown argument: $arg (want -i, or a/b/c)" >&2; exit 2 ;;
  esac
done
[ "${#PARTS[@]}" -eq 0 ] && PARTS=(a b c)

b=$(printf '\033[1m'); o=$(printf '\033[0m'); [ -t 1 ] || { b=; o=; }
[ -n "${ABC_INTERACTIVE:-}" ] \
  && echo "${b}interactive — a run pauses before each call; press enter to advance.${o}" \
  || echo "${b}batch — the whole walkthrough runs to the end (or the first failure).${o}"

rc=0
for p in "${PARTS[@]}"; do
  echo
  echo "${b}==================  PART ${p^^}  ==================${o}"
  ./"$p.sh" || { rc=$?; echo "part $p exited $rc — stopping." ; break; }
done

echo
[ "$rc" -eq 0 ] \
  && echo "${b}Walkthrough complete.${o} Edit policies.yaml and re-run ./b.sh (or a single ./bN.sh), or read a.sh / b1.sh..b5.sh / c.sh — every call is one you can paste." \
  || echo "${b}Walkthrough stopped with errors.${o}"
exit "$rc"
