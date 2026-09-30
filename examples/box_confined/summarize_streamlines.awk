# Per-particle summary of npsat_trace ordered streamline files.
# Point rows:       pid Eid Sid x y z vmag
# Termination rows: -1 pid Eid Sid end_reason 0 0
$1 != -1 {
  k = $2 " " $3
  if (!((k, $1) in seen)) { seen[k, $1] = 1; n[k]++ }
  if (!(k in x0)) { x0[k] = $4; y0[k] = $5; z0[k] = $6 }
  if ($4 > xmax[k]) xmax[k] = $4
  dy = $5 - y0[k]; dz = $6 - z0[k]
  if (dy < 0) dy = -dy
  if (dz < 0) dz = -dz
  if (dy > mdy[k]) mdy[k] = dy
  if (dz > mdz[k]) mdz[k] = dz
  if ($7 > vmax[k]) vmax[k] = $7
}
$1 == -1 { r[$3 " " $4] = $5 }
END {
  for (k in n)
    printf "Eid,Sid=%s start=(%g,%g,%g) points=%d max_x=%g max_dy=%g max_dz=%g max_vmag=%g end_reason=%s\n",
           k, x0[k], y0[k], z0[k], n[k], xmax[k], mdy[k], mdz[k], vmax[k], r[k]
}
