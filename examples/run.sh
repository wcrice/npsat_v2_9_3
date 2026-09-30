#!/usr/bin/env bash
# Runs the example cases: npsat_v2 (flow), npsat_trace (particle tracing, for cases that have a
# trace.ini), the case's check.sh and, on 4 ranks, compare.sh against the stored reference output.
#
#   run.sh [case ...]      default: every case directory next to this script
#
# Settings (environment):
#   NPSAT_RUNS   directory that receives one run directory per case   default ./runs
#   NPSAT_NP     MPI ranks for npsat_v2 and npsat_trace               default 4
#
# npsat_v2, npsat_trace and mpirun must be in PATH. A case directory is copied to
# $NPSAT_RUNS/<case> and every command runs there, so the case directory is never written to.
# npsat_trace must use the rank count of the flow run: it reloads the distributed triangulation
# that npsat_v2 saved, and p4est aborts on a different count.
# Exit status is non-zero when any case fails a step, a check or the comparison with expected/.
set -uo pipefail

here=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
runs=${NPSAT_RUNS:-./runs}
np=${NPSAT_NP:-4}

if [ "$#" -gt 0 ]; then
  cases=("$@")
else
  cases=()
  for d in "$here"/*/; do [ -f "$d/flow.ini" ] && cases+=("$(basename "$d")"); done
fi
if [ "${#cases[@]}" -eq 0 ]; then
  echo "no case directory with a flow.ini in $here" >&2
  exit 1
fi

status=0
for c in "${cases[@]}"; do
  src=$here/$c
  if [ ! -f "$src/flow.ini" ]; then
    echo "$c: no $src/flow.ini" >&2
    status=1
    continue
  fi
  run=$runs/$c
  rm -rf "$run"
  mkdir -p "$run"
  ( cd "$src" && tar --exclude=./expected -cf - . ) | tar -xf - -C "$run"
  mkdir -p "$run/out" "$run/trace"
  cd "$run" || exit 1

  echo "== $c: npsat_v2, $np MPI ranks"
  mpirun -n "$np" npsat_v2 -c flow.ini 2>&1 | tee flow.log
  rc=${PIPESTATUS[0]}
  if [ "$rc" -ne 0 ]; then echo "$c: npsat_v2 exited with status $rc" >&2; status=1; cd - >/dev/null; continue; fi

  if [ -f trace.ini ]; then
    echo "== $c: npsat_trace, $np MPI ranks"
    mpirun -n "$np" npsat_trace -c trace.ini 2>&1 | tee trace.log
    rc=${PIPESTATUS[0]}
    if [ "$rc" -ne 0 ]; then echo "$c: npsat_trace exited with status $rc" >&2; status=1; cd - >/dev/null; continue; fi
  fi

  echo "== $c: check"
  bash check.sh 2>&1 | tee check.log
  [ "${PIPESTATUS[0]}" -eq 0 ] || status=1

  if [ "$np" -eq 4 ]; then
    echo "== $c: comparison with expected/"
    "$here/compare.sh" "$c" "$PWD" > compare.log 2>&1
    rc=$?
    grep -v '^present' compare.log
    [ "$rc" -eq 0 ] || status=1
  else
    echo "== $c: comparison with expected/ skipped (the reference output is for 4 ranks)"
  fi
  cd - >/dev/null
done
exit "$status"
