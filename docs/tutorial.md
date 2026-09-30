# Tutorial: a confined box, from input to result

This tutorial runs `examples/box_confined` by hand: it reads the configuration, runs the flow
model, runs the particle tracer, and compares the result with the analytic solution. The case
was constructed from the source for this repository. It is not a benchmark supplied by the
upstream author. Option names and file formats are listed in `reference.md`.

## The problem

A box of 1000 x 1000 x 100 m is held at a head of 80 m on the west face (x = 0) and 60 m on the
east face (x = 1000 m). The north, south, top and bottom faces are closed. Conductivity is
1 m/d in every direction and porosity is 0.3. The aquifer is confined and the solution is
steady. The analytic solution follows:

| Quantity | Value |
|---|---|
| Head | `h(x) = 80 - 0.02 x` m |
| Darcy flux | 1 m/d x 0.02 = 0.02 m/d in +x |
| Flow through the box | 0.02 m/d x (1000 m x 100 m) = 2000 m3/d |
| Pore velocity | 0.02 / 0.3 = 0.0667 m/d |

The mesh is 10 x 10 x 5 cells of 100 x 100 x 20 m, 500 cells in all. The run uses 4 MPI ranks.

## Setting up

With the container, from the repository root:

```bash
container/run.sh shell
```

The shell starts in `/runs`, which is the `runs/` directory of the repository on the host. The
executables `npsat_v2` and `npsat_trace` are in `PATH`. Without the container, `npsat_v2`,
`npsat_trace` and `mpirun` must be in `PATH` (see the README for the build).

Copy the case to a working directory. Inside the container the examples are in
`/opt/npsat/examples`; natively they are in `examples/` of the repository.

```bash
mkdir -p tutorial/out tutorial/trace
cp -r /opt/npsat/examples/box_confined/. tutorial/
cd tutorial
ls
```

The directory holds `flow.ini` (flow configuration), `trace.ini` (tracer configuration),
`input/` (data files), `check.sh` with `summarize_streamlines.awk` (the checks), `expected/` (the
reference output) and the two empty directories `out/` and `trace/`. Both programs require their output directories to exist.

## The flow configuration

`flow.ini` has one section per topic. The lines that matter here:

```ini
[Paths]
Main = .
Input = input
Output = out/
```

`Main` is the base directory. Input files are read from `./input`. Output files go to `./out/`.
The trailing slash on `Output` matters when more than one rank writes VTU output.

```ini
[Geometry]
Type = BOX
BoxDims = 1000,1000,100
BoxLLP = 0,0,0
Top = 100
Bottom = 0

[Discretization]
Nxyz = 10,10,5
Vertical = 0,0.2,0.4,0.6,0.8,1
```

A box with its lower-left corner at the origin, divided into 10 x 10 x 5 cells. `Top` and
`Bottom` are the elevations the box is fitted to. `Vertical` places the six layer interfaces at
equal fractions of the thickness.

```ini
[Refinement]
Initial = 0
Wells = 0
...
```

Refinement options default to 1 when they are omitted, so the file sets all of them to 0 to keep
the 500-cell mesh.

```ini
[BC]
Dirichlet = dirichlet.dat
Neumann =
GHB =
HalfWidth = 10
MinOverlap = 50
```

One file of Dirichlet boundaries. The Neumann and general-head files are empty. The two numbers
only matter for lateral-polyline regions, but they have no default and must be present.

```ini
[Properties]
Kxy = kxy.master
Kz = kz.master
Sy = sy.master
Ss = ss.master

[IC]
Head = ic.master
```

Properties and the initial head are interpolation master files. A plain number is not accepted.

```ini
[Simulation]
Nsteps = 1
Start_step = 0
Delta_time_file = dt.dat
Confined = 1
Steady_state = 1
```

A confined, steady run that solves input time step 0.

```ini
[Output]
Prefix = box
Save_trace_data = 1
Save_fine_velocities = 1
Print_solution_cell_vtu = 1
Print_cell_budget_csv = 1
Print_cellcenters_vtk = 1
```

`Save_trace_data` writes what `npsat_trace` reads. The three `Print_` options write the
VTU files, the cell budget CSV and the cell-centre VTK that are inspected below.

## The input files

`input/dirichlet.dat` defines the two fixed-head faces:

```
2
EDGE 2 head_west.master
-5 50
5 950
EDGE 2 head_east.master
995 50
1005 950
```

Two entries. `EDGE` selects vertical boundary faces. With two vertices the region is the
rectangle between the two corners. The first rectangle spans x from -5 to 5 and y from 50 to 950,
so it selects the west faces of the cells at x = 0 whose corners lie inside it. The master
files give the head.

`input/head_west.master` and its values file `head_west.values`:

```
1

2 CONST none head_west.values
-10 -10
1010 1010
```

```
80.0
```

One region, a rectangle from (-10, -10) to (1010, 1010), with a constant value taken from
`head_west.values`. The second word `none` is the spatial file, which a `CONST` region does not
read. The values file is a matrix with one row and one column: one value for one input time step.
`kxy.master`, `kz.master`, `sy.master`, `ss.master` and `ic.master` have the same shape
(1.0, 1.0, 0.2, 1.0e-5, and an initial head of 70).

`input/dt.dat` holds one line, `1.0`, the duration of the single input time step. A steady run
does not use it.

## Running the flow model

```bash
mpirun -n 4 npsat_v2 -c flow.ini 2>&1 | tee flow.log
```

The log reads the input, builds the mesh, solves and writes the output. The lines to look for:

```
Initial triangulation cells: 500
Number of flux DoFs: 1700
Number of head DoFs: 500
Number of trace DoFs: 1700
Steady-state mode: solving input stress scenario 0 from IC.Head; transient spin-up is not used.
   Schur system (Lambda) converged in 1 iterations.
  Head range: [61, 79] m, Mean: 70 m
  Dirichlet inflow              : 2.00e+03 volume/time
  Dirichlet outflow             : 2.00e+03 volume/time
  Percent discrepancy           : -1.22e-10 %
Simulation Finished
```

The head range is 61 to 79 m because the heads are cell values at the cell centres, 50 m from the
faces that are held at 80 and 60 m. The inflow through the Dirichlet faces is 2000 volume/time,
equal to the analytic 2000 m3/d, and the budget closes to 1e-10 percent.

Both programs exit with status 0 after some configuration errors. `Simulation Finished` is the
line that shows the run completed.

The program ends with `Total executable wall time`. The triangulation is written with MPI-IO;
on an NFS file system that step alone took 30 s in this case, against 0.3 s for the whole run on
a local disk.

## Flow output

```bash
ls out
```

The files follow the `Output.Prefix`, `box`. The ones used in this tutorial:

| File | Content |
|---|---|
| `box_time_step_budget_history.csv` | Water budget of the step |
| `box_cell_budget_rank_NNNN_step_000.csv` | Per-cell face flows and heads, one file per rank |
| `box_cellcenters_rank_NNNN_step_000.vtk` | Cell centres with head, `dS` and `Qw` |
| `box_solution_cell_step_000_0000.pvtu` and `.N.vtu` | Head on the mesh |
| `box_dist_tria`, `box_velmap_*`, `box_Vface_rt0_vals_*` | Mesh and velocity field for `npsat_trace` |

The remaining files are listed in `reference.md`. To compare the head with the analytic solution,
read it from the end of each row of the cell budget CSV (the header has one column more than the
rows, see `reference.md`):

```bash
awk -F, 'BEGIN { m = 0 } $1 ~ /^[0-9]+_[0-9]+:$/ { h = $(NF-6); e = h - (80 - 0.02 * $2); if (e < 0) e = -e; if (e > m) m = e }
         END { print "largest head deviation:", m, "m" }' out/box_cell_budget_rank_*_step_000.csv
```

The printed deviation is 0: the model head equals the analytic head at every cell centre to the
precision of the output.

To view the head, open `out/box_solution_cell_step_000_0000.pvtu` in ParaView, or plot the
`head` point data of the `.vtk` files.

## Particle tracing

`trace.ini`:

```ini
[Data]
Prefix = out/box
Particle_file = input/particles.dat

[Simulation]
Delta_time_file = input/trace_dt.dat
Porosity = 0.3

[Output]
Prefix = trace/box

[Misc]
Dbg_prefix = trace/dbg
```

`Data.Prefix` is the flow prefix including its directory. `Delta_time_file` has one line,
`20000`: the tracer runs one time step of 20000 days on the flow field of step 0. `Porosity`
converts Darcy flux to pore velocity. `Misc.Dbg_prefix` must be present although no debug output
is requested.

`input/particles.dat` holds five seeds, `Eid Sid x y z rt rf`:

```
# Eid Sid x y z rt rf
1 1 130 250 10 0 0
1 2 130 550 30 0 0
1 3 130 730 50 0 0
1 4 330 450 30 0 0
1 5 530 150 50 0 0
```

`Eid` and `Sid` label each particle in the output. `rt` and `rf` are read and not used. The
seeds lie inside cells. A seed exactly on a cell face is inserted once for each cell that
contains it.

```bash
mpirun -n 4 npsat_trace -c trace.ini 2>&1 | tee trace.log
```

The tracer must run on the same number of ranks as the flow run. The log ends with
`COMPLETED PARTICLE CHUNK ITERATION 0` and `Particles processed: 5`.

## Particle output

```bash
ls trace
head -3 trace/box_streamlines_ordered_rank_0000_iter_0000.dat
```

Each line of a `box_streamlines_ordered_rank_NNNN_iter_0000.dat` file is a point,
`pid Eid Sid x y z vmag`, or a termination record `-1 pid Eid Sid end_reason 0 0`. A particle is
stored completely in one rank's file. For the particle seeded at (330, 450, 30):

```
0 1 4 330 450 30 0.0666667
1 1 4 336.667 450 30 0.0666667
2 1 4 343.333 450 30 0.0666667
```

It moves 6.667 m per point in +x at constant y and z, at 0.0666667 m/d. `summarize_streamlines.awk`
condenses the files to one line per particle:

```bash
cat trace/box_streamlines_ordered_rank_*_iter_0000.dat | awk -f summarize_streamlines.awk | sort
```

Every particle keeps its y and z, has a maximum velocity of 0.0666667 m/d, and ends with reason
11 (lateral boundary) at x between 993 and 996 m, within one point spacing of the east face.

## Automated check

```bash
bash check.sh
```

The script checks the log, the head against the analytic solution (limit 1e-6 m), the Dirichlet
flow against 2000 m3/d, the budget discrepancy, and, for each particle, a straight path along +x
at 0.0666667 m/d ending at the lateral boundary. It exits non-zero on any failure.
`container/run.sh` runs the same script for both examples.

The same run, with the expected result, is stored in `examples/box_confined/expected/`.

## The GUI

`container/run.sh gui` serves the same case at `http://127.0.0.1:8765/`. Choose `box_confined`,
keep the configuration text, and start the run. The page shows the status, the output of
`npsat_v2` and `npsat_trace` as the programs print it, the output file list, and two plots: the
head at the cell centres (plan view and a section) and the particle paths. To see a failure,
delete the line `Head = ic.master` from the flow configuration and start the run: the model
prints `boost::bad_any_cast: failed conversion using boost::any_cast` and exits with status 0,
and the page reports the run as failed because `Simulation Finished` is missing.

## Variations

- `examples/box_unconfined` differs in `Confined = 0`, in `Rch_Data = rch.master` (recharge
  0.0005 m/d) and in having no tracer step. Its log shows the nonlinear iteration
  (`NL 4 | dH_inf 5.181e-03 | tol 1.793e-02 | CONVERGED`) and the net Dirichlet outflow of
  500 m3/d that equals the recharge.
- Setting `1.0` to `2.0` in `input/kxy.values` doubles the Dirichlet inflow to 4000 m3/d and
  leaves the head range at 61 to 79 m. The inflow line of `check.sh` then fails, because the
  script assumes K = 1.
- Setting `Refinement.Initial = 1` splits each cell into 8 cells: the log reports 4000 global
  active cells, 1000 on each rank.
- Running `npsat_v2` and `npsat_trace` on one rank (`mpirun -n 1`) writes a single `.vtu` file in
  place of the `.pvtu` set.

## Not covered

The case has no wells, streams, general-head or Neumann boundaries, no transient forcing, no
refinement, and no checkpoint restart. Those options exist in the source and are listed in
`reference.md`, but no case in this repository runs them. The unconfined tracer behaviour at the
water table was not investigated.
