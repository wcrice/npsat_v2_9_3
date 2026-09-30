#!/usr/bin/env bash
# Verifies a box_confined run against its analytic solution. Run inside the run directory.
# Exits non-zero on any failure.
#   head:          h(x) = 80 - 0.02 x        (Kxy = 1 m/d, heads 80 m at x = 0 and 60 m at x = 1000 m)
#   Dirichlet flow: K * i * A = 1 * 0.02 * (1000 m * 100 m) = 2000 m3/d
#   pore velocity:  K * i / n = 0.02 / 0.3 = 0.0666667 m/d
set -euo pipefail
run=.
fail=0
ok()  { printf 'PASS  %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fail=1; }

grep -q '^Simulation Finished' "$run/flow.log" && ok "flow.log: Simulation Finished" || bad "flow.log: no 'Simulation Finished'"
grep -q 'Schur system (Lambda) converged' "$run/flow.log" && ok "flow.log: $(grep -m1 'Schur system (Lambda) converged' "$run/flow.log" | sed 's/^ *//')" || bad "flow.log: no Schur convergence line"

# Cell rows carry 25 fields against a 26-name header, so the head is addressed
# from the row end: the last six fields are lambda0..5 and the head precedes them.
awk -F, '$1 ~ /^[0-9]+_[0-9]+:$/ { e = $(NF-6) - (80 - 0.02 * $2); if (e < 0) e = -e
           if (e > m) m = e; n++ }
         END { printf "%d %.3e\n", n, m }' "$run"/out/box_cell_budget_rank_*_step_000.csv > "$run/head_check.txt"
read -r ncell herr < "$run/head_check.txt"
[ "$ncell" -eq 500 ] && ok "cell_budget: $ncell cells" || bad "cell_budget: $ncell cells, expected 500"
awk -v e="$herr" 'BEGIN { exit !(e + 0 < 1e-6) }' && ok "max |head - analytic| = $herr m" || bad "max |head - analytic| = $herr m (limit 1e-6)"

awk -F, 'NR == 2 { printf "%.6e %.3e\n", $13, $19 }' "$run/out/box_time_step_budget_history.csv" > "$run/budget_check.txt"
read -r qin pdisc < "$run/budget_check.txt"
awk -v q="$qin" 'BEGIN { d = q - 2000; if (d < 0) d = -d; exit !(d < 1e-6 * 2000) }' && ok "Dirichlet inflow $qin m3/d (analytic 2000)" || bad "Dirichlet inflow $qin m3/d (analytic 2000)"
awk -v p="$pdisc" 'BEGIN { if (p < 0) p = -p; exit !(p < 1e-6) }' && ok "budget discrepancy $pdisc %" || bad "budget discrepancy $pdisc % (limit 1e-6)"

cat "$run"/trace/box_streamlines_ordered_rank_*_iter_0000.dat | awk -f summarize_streamlines.awk | sort > "$run/streamlines_summary.txt"
np=$(wc -l < "$run/streamlines_summary.txt")
[ "$np" -eq 5 ] && ok "streamlines: $np particles traced" || bad "streamlines: $np particles, expected 5"
while read -r line; do
  awk -v l="$line" 'BEGIN {
      match(l, /max_x=[0-9.e+-]+/);  x = substr(l, RSTART + 6, RLENGTH - 6)
      match(l, /max_dy=[0-9.e+-]+/); dy = substr(l, RSTART + 7, RLENGTH - 7)
      match(l, /max_dz=[0-9.e+-]+/); dz = substr(l, RSTART + 7, RLENGTH - 7)
      match(l, /max_vmag=[0-9.e+-]+/); v = substr(l, RSTART + 9, RLENGTH - 9)
      match(l, /end_reason=[0-9]+/); r = substr(l, RSTART + 11, RLENGTH - 11)
      dv = v - 0.0666667; if (dv < 0) dv = -dv
      exit !(dy + 0 < 1e-6 && dz + 0 < 1e-6 && dv < 1e-6 && x + 0 > 990 && r == 11) }' \
    && ok "particle ${line%% start*}: straight +x path to the east boundary at 0.0666667 m/d" \
    || bad "particle: $line"
done < "$run/streamlines_summary.txt"

[ "$fail" -eq 0 ] && echo "ALL CHECKS PASSED" || { echo "CHECKS FAILED"; exit 1; }
