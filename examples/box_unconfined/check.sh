#!/usr/bin/env bash
# Verifies a box_unconfined run. Run inside the run directory. Exits non-zero on any failure.
#   Recharge:       5e-4 m/d * (1000 m * 1000 m) = 500 m3/d, leaving through the Dirichlet faces
#   Dupuit, 1-D:    inflow at x = 0    K(h0^2 - h1^2)/(2L) - wL/2 = 1.15 m2/d -> 1150 m3/d
#                   outflow at x = L   K(h0^2 - h1^2)/(2L) + wL/2 = 1.65 m2/d -> 1650 m3/d
#   The 3-D model carries a saturated thickness and vertical flow the Dupuit estimate omits,
#   so those two fluxes are compared at 5 %.
set -euo pipefail
run=.
fail=0
ok()  { printf 'PASS  %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fail=1; }

grep -q '^Simulation Finished' "$run/flow.log" && ok "flow.log: Simulation Finished" || bad "flow.log: no 'Simulation Finished'"
grep -q '| CONVERGED' "$run/flow.log" && ok "flow.log: $(grep -m1 '| CONVERGED' "$run/flow.log")" || bad "flow.log: nonlinear loop did not report CONVERGED"

awk -F, 'NR == 2 { printf "%.6e %.6e %.6e %.6e %.3e\n", $7, $13, $14, $15, $19 }' "$run/out/box_time_step_budget_history.csv" > "$run/budget_check.txt"
read -r rch qin qout qnet pdisc < "$run/budget_check.txt"
near() { awk -v a="$1" -v b="$2" -v t="$3" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(d <= t * b) }'; }
near "$rch" 500 1e-6 && ok "recharge $rch m3/d (5e-4 m/d * 1e6 m2 = 500)" || bad "recharge $rch m3/d (expected 500)"
near "$qnet" 500 1e-6 && ok "net Dirichlet outflow $qnet m3/d equals recharge" || bad "net Dirichlet outflow $qnet m3/d (expected 500)"
near "$qin" 1150 0.05 && ok "west inflow $qin m3/d (Dupuit 1150, within 5 %)" || bad "west inflow $qin m3/d (Dupuit 1150)"
awk -v q="$qout" 'BEGIN { d = q - 1650; if (d < 0) d = -d; exit !(d <= 0.05 * 1650) }' && ok "east outflow $qout m3/d (Dupuit 1650, within 5 %)" || bad "east outflow $qout m3/d (Dupuit 1650)"
awk -v p="$pdisc" 'BEGIN { if (p < 0) p = -p; exit !(p < 1e-6) }' && ok "budget discrepancy $pdisc %" || bad "budget discrepancy $pdisc % (limit 1e-6)"

[ "$fail" -eq 0 ] && echo "ALL CHECKS PASSED" || { echo "CHECKS FAILED"; exit 1; }
