#!/usr/bin/env bash
# Compares a run with the reference output stored in <case>/expected.
#
#   compare.sh <case> [run-directory]      default run directory: $NPSAT_RUNS/<case>, ./runs/<case>
#
# The reference output was produced on 4 MPI ranks; compare only runs made with NPSAT_NP=4.
# Every CSV, VTK and streamline file in expected/ is compared field by field with the file of the
# same name in the run directory. Numeric fields must agree within 1e-6 absolute plus 1e-6
# relative; other fields must be equal. The wall-time columns of the time step budget history are
# skipped. Log files and VTU/PVTU files are compared by presence only, since they carry times and
# compressed binary data. Exit status is non-zero when a file is missing or differs.
set -uo pipefail

here=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
case=${1:?usage: compare.sh <case> [run-directory]}
run=${2:-${NPSAT_RUNS:-./runs}/$case}
exp=$here/$case/expected
[ -d "$exp" ] || { echo "no $exp" >&2; exit 2; }
[ -d "$run" ] || { echo "no run directory $run" >&2; exit 2; }

status=0
while IFS= read -r f; do
  rel=${f#"$exp"/}
  if [ ! -f "$run/$rel" ]; then echo "MISSING  $rel"; status=1; continue; fi
  case "$rel" in
    *.log|*.vtu|*.pvtu) echo "present  $rel"; continue ;;
  esac
  skip=""
  case "$rel" in *_time_step_budget_history.csv) skip="4,5,6" ;; esac
  diff=$(paste -d'\n' "$f" "$run/$rel" | awk -v skip="$skip" '
    function isnum(v) { return v ~ /^[-+]?([0-9]+[.]?[0-9]*|[.][0-9]+)([eE][-+]?[0-9]+)?$/ }
    BEGIN { n = split(skip, s, ","); for (i = 1; i <= n; i++) sk[s[i]] = 1 }
    NR % 2 == 1 { a = $0; next }
    { b = $0; gsub(/[, ]+/, " ", a); gsub(/[, ]+/, " ", b)
      na = split(a, x, " "); nb = split(b, y, " ")
      if (na != nb) { print "  line " NR / 2 ": " na " fields against " nb; next }
      for (i = 1; i <= na; i++) {
        if (i in sk || x[i] == y[i]) continue
        if (isnum(x[i]) && isnum(y[i])) {
          u = x[i] + 0; w = y[i] + 0
          d = u - w; if (d < 0) d = -d
          m = (u < 0 ? -u : u); t = (w < 0 ? -w : w); if (t > m) m = t
          if (d <= 1e-6 + 1e-6 * m) continue
        }
        print "  line " NR / 2 ", field " i ": " x[i] " against " y[i]; break
      } }')
  if [ -n "$diff" ]; then
    echo "DIFFERS  $rel"; echo "$diff" | head -5; status=1
  else
    echo "same     $rel"
  fi
done < <(find "$exp" -type f | sort)
exit "$status"
