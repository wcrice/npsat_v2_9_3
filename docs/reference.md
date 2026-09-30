# Reference

This reference is written from the sources at commit `7f67337` of upstream branch `trace_dbg`
(`npsat_flow/flow_input.h`, `npsat_trace/trace_input.h` and the readers and writers they drive).
Descriptions are the help strings of the source where these are accurate and are replaced by
what the code does where they are not. Where the code does not determine a fact, the text says
so. Behaviour marked "observed" was seen in a run of the container image.

## Invocation

```
mpirun -n N npsat_v2    -c flow.ini
mpirun -n N npsat_trace -c trace.ini
```

| Argument | Action |
|---|---|
| `-c file`, `--config file` | Configuration file |
| `-h`, `--help` | Prints every configuration option with its default, then exits |
| `-v`, `--version` | Prints the program version (`npsat_v2` 0.0.05, `npsat_trace` 0.0.02), then exits |
| none | Prints usage, then exits |

`npsat_v2` runs on any number of MPI ranks. `npsat_trace` must run on the same number of ranks:
it reloads the distributed triangulation that `npsat_v2` saved, and p4est aborts otherwise
(observed: `Abort: num procs mismatch`, exit status 134). `npsat_trace` reads the output of an
`npsat_v2` run made with `Output.Save_trace_data = 1`.

Relative paths resolve as follows. The configuration file and every path in `npsat_trace`'s
configuration resolve against the working directory. In `npsat_v2`, `Paths.Input` and
`Paths.Output` resolve against `Paths.Main`, and every other file name resolves against
`Paths.Input` (output file names against `Paths.Output`). Absolute paths are used as given.

## Configuration file

A configuration file is an INI file read by Boost.Program_options.

```ini
# comment
[Paths]
Main = .
Input = input
```

- The option name is `Section.Key`; names are case sensitive.
- `#` starts a comment, also after a value.
- An empty value (`Key =`) is an empty string.
- Lists are comma separated (`BoxDims = 1000,1000,100`).
- Flags take 0 or 1.
- Unknown options are errors (`unrecognised option 'Simulation.Foo'`).
- An option without a default that is missing from the file is an error whose message does not
  name the option (`boost::bad_any_cast: failed conversion using boost::any_cast`).

In the tables, "required" marks an option without a default. The type column gives the type the
reader converts to; `npsat_v2 -h` and `npsat_trace -h` print the same names and defaults.

## npsat_v2 options

Each section of the file contains the options of that name. The descriptions use "master file"
for an interpolation master file, described under "Input files".

### [Paths]

| Option | Type | Default | Description |
|---|---|---|---|
| `Paths.Main` | string | required | Base directory. Paths.Input and Paths.Output are joined to it unless absolute. |
| `Paths.Input` | string | required | Directory of the input files, joined to Paths.Main unless absolute. Every file name elsewhere in the configuration is resolved against it unless absolute. |
| `Paths.Output` | string | required | Output directory, joined to Paths.Main unless absolute. Must exist before the run. A trailing slash is required when more than one MPI rank writes VTU output. |
| `Paths.CheckPointsFolder` | string | empty | Checkpoint directory, joined to Paths.Main unless absolute; empty uses Paths.Output. Must exist. |

### [Geometry]

| Option | Type | Default | Description |
|---|---|---|---|
| `Geometry.Type` | string | required | BOX or FILE. Any other value is treated as FILE. |
| `Geometry.BoxDims` | string | required if BOX | Box extent as X,Y,Z. |
| `Geometry.BoxLLP` | string | required if BOX | Minimum corner of the box as X,Y,Z. |
| `Geometry.MeshFileName` | string | required if FILE | Two-dimensional quadrilateral mesh file, extruded vertically (see "Mesh file"). |
| `Geometry.Top` | string | required | Top elevation: a number, or the name of an interpolation master file evaluated in x and y at time index 0. |
| `Geometry.Bottom` | string | required | Bottom elevation: a number, or the name of an interpolation master file evaluated in x and y at time index 0. |

### [Discretization]

| Option | Type | Default | Description |
|---|---|---|---|
| `Discretization.Nxyz` | string | required if BOX | Number of cells in x, y and z as nx,ny,nz. |
| `Discretization.Vertical` | string | required | Relative position of each cell layer interface from 0 (bottom) to 1 (top), as a comma-separated list, or the name of an interpolation master file. A list of Nz + 1 values is expected with a box. |

### [Refinement]

| Option | Type | Default | Description |
|---|---|---|---|
| `Refinement.Initial` | int | 1 | Number of uniform refinements of the whole mesh; each one splits every cell into 8. |
| `Refinement.Wells` | int | 1 | Number of refinement passes applied to cells that contain a well screen. |
| `Refinement.Streams` | int | 1 | Number of refinement passes applied to top cells that intersect a stream. |
| `Refinement.Top` | int | 1 | Number of refinement passes applied to cells with a face on the top boundary. |
| `Refinement.TopDepth` | int | 1 | Number of layers of face neighbours, counted outward from each top cell flagged by Refinement.Top, that are flagged with it. |
| `Refinement.Dirichlet` | int | 1 | Number of refinement passes applied to cells with a face on a Dirichlet boundary entry. |
| `Refinement.GHB` | int | 1 | Number of refinement passes applied to cells with a face on a general-head boundary entry. |
| `Refinement.Neumann` | int | 1 | Counts toward the number of refinement passes. The code that flags Neumann cells is commented out. |
| `Refinement.WellMinScreenLength` | number | 0.5 | Maximum minimum well-screen overlap length used for a cell-well link |
| `Refinement.WellMinScreenCellFraction` | number | 0.1 | Minimum well-screen overlap as a fraction of local cell height |

### [BC]

| Option | Type | Default | Description |
|---|---|---|---|
| `BC.Dirichlet` | string | required | Dirichlet boundary file (see "Dirichlet and general-head boundary files"). Empty disables Dirichlet boundaries. |
| `BC.Neumann` | string | required | Read and never opened. |
| `BC.GHB` | string | required | General-head boundary file. Empty disables general-head boundaries. |
| `BC.HalfWidth` | number | required | Half-width of the buffer around a lateral polyline, in the horizontal length unit. Used by LATERAL and LATERAL_POLYLINE interpolation regions. |
| `BC.MinOverlap` | number | required | Minimum length of the overlap between a lateral face edge and the buffered polyline for the face to match. Used by LATERAL and LATERAL_POLYLINE interpolation regions. |

### [Properties]

| Option | Type | Default | Description |
|---|---|---|---|
| `Properties.Kxy` | string | required | Horizontal hydraulic conductivity (Kxx = Kyy): name of an interpolation master file. A number is not accepted. |
| `Properties.Kz` | string | required | Vertical hydraulic conductivity: name of an interpolation master file. A number is not accepted. |
| `Properties.Sy` | string | required | Specific yield: name of an interpolation master file. A number is not accepted. |
| `Properties.Ss` | string | required | Specific storage: name of an interpolation master file. A number is not accepted. |

### [Sources]

| Option | Type | Default | Description |
|---|---|---|---|
| `Sources.Rch_Data` | string | empty | Areal recharge rate (length per time): name of an interpolation master file. Empty disables recharge. |
| `Sources.Rch_factor` | number | 1 | Multiplier applied to the recharge values. |
| `Sources.Well_Data` | string | empty | Well file (see "Well file"). Empty disables wells. |
| `Sources.Well_Rates` | string | empty | Pumping rate table: one row per well (row q_row of the well file), one column per input time step. Empty gives zero rates. |
| `Sources.Well_factor` | number | 1 | Read and not applied. |
| `Sources.Stream_Data` | string | empty | Stream geometry file (see "Stream file"). Stream input is used only when this and Sources.Stream_Rates are both set. |
| `Sources.Stream_Rates` | string | empty | Stream rate table: one row per row_id of the stream file, one column per input time step; the rate is multiplied by the intersected area. |
| `Sources.Stream_factor` | number | 1 | Multiplier applied to the stream rates. |

### [IC]

| Option | Type | Default | Description |
|---|---|---|---|
| `IC.Head` | string | required | Initial head: name of an interpolation master file, evaluated at time index 0. |

### [Simulation]

| Option | Type | Default | Description |
|---|---|---|---|
| `Simulation.Nsteps` | int | 24 | Number of model time steps. A steady-state run solves one step regardless. |
| `Simulation.Start_step` | int | 0 | Index of the first input time step, counted from 0 in Simulation.Delta_time_file. In a steady-state run it selects the one input scenario that is solved. |
| `Simulation.Delta_time_file` | string | required | File with one time step duration per row (see "Time step file"). The number of rows is the number of input time steps; time-dependent input files carry one column per row. |
| `Simulation.Confined` | int | 0 | 1 treats the aquifer as confined and disables the nonlinear unconfined conductivity and yield behaviour. Any other value is unconfined. |
| `Simulation.Steady_state` | int | 0 | 1 solves one steady scenario, the input time step Simulation.Start_step, from IC.Head. Any other value is transient. |
| `Simulation.Restart_from_checkpoint` | int | 0 | 1 restarts from the last committed checkpoint. Any other value starts from IC.Head. |
| `Simulation.Checkpoint_file` | string | npsat_flow.chk | Destination checkpoint basename; relative paths use Paths.CheckPointsFolder |
| `Simulation.Restart_checkpoint_file` | string | empty | Optional checkpoint basename to load; empty loads Simulation.Checkpoint_file |

### [Spinup]

| Option | Type | Default | Description |
|---|---|---|---|
| `Spinup.Iterations` | unsigned int | 30 | Maximum number of accepted spin-up solves of the first step of a transient run; 0 disables spin-up. Not used in a steady-state run. |
| `Spinup.Tolerance` | number | 1.0 | Upper bound on the maximum absolute head change for spin-up to converge. |
| `Spinup.MinimumSolves` | unsigned int | 5 | Minimum number of spin-up solves before convergence is allowed |
| `Spinup.FluxRelativeL2Tolerance` | number | 1.0e-2 | Maximum relative L2 change between consecutive recovered spin-up flux fields |
| `Spinup.RMSHeadTolerance` | number | 1.0e-1 | Maximum RMS head change between consecutive spin-up solves |
| `Spinup.ConsecutivePasses` | unsigned int | 3 | Required consecutive solves satisfying all spin-up convergence metrics |
| `Spinup.PumpingLossFractionTolerance` | number | 5.0e-3 | Maximum pumping removed by dry wells as a fraction of total requested pumping |
| `Spinup.PumpingLossStabilityTolerance` | number | 1.0e-4 | Maximum solve-to-solve change in pumping-loss fraction |
| `Spinup.ExitAfterConvergence` | int | 0 | Exit after successful spin-up convergence and writing its outputs |
| `Spinup.StableDryWellSolves` | unsigned int | 3 | Deprecated; the dry-well count is diagnostic only. |

### [Solver]

| Option | Type | Default | Description |
|---|---|---|---|
| `Solver.System_iterations` | int | 15000 | Maximum iterations of the linear system solver. |
| `Solver.System_tol` | number | 1e-12 | Tolerance of the linear system solver. |

### [Nonlinear]

| Option | Type | Default | Description |
|---|---|---|---|
| `Nonlinear.Iterations` | unsigned int | 25 | Maximum Picard iterations per time step. |
| `Nonlinear.AbsTolUpdate` | number | 1e-2 | Absolute tolerance on the head update, in head units. |
| `Nonlinear.RelTolUpdate` | number | 1e-4 | Relative tolerance on the head update. |
| `Nonlinear.DampingOmega` | number | 0.7 | Picard damping factor |
| `Nonlinear.UseAnderson` | int | 1 | Enable Anderson acceleration |
| `Nonlinear.AndersonStart` | unsigned int | 2 | Picard iteration at which Anderson acceleration starts. |
| `Nonlinear.AndersonM` | unsigned int | 5 | Anderson acceleration memory depth |
| `Nonlinear.AndersonReg` | number | 1e-11 | Anderson least-squares regularization |
| `Nonlinear.AndersonBeta` | number | 0.7 | Damping factor applied to the Anderson correction, 0 < beta <= 1. |
| `Nonlinear.AndersonMaxAlpha` | number | 5.0 | Maximum allowed absolute Anderson coefficient before rejecting the accelerated step. |
| `Nonlinear.AndersonMaxStepFactor` | number | 2.0 | Reject Anderson step if its L2 norm exceeds this multiple of the damped Picard step. |
| `Nonlinear.CarryHistoryAcrossTimesteps` | int | 0 | Carry Anderson history across time steps |
| `Nonlinear.RechargeStabilizationMode` | string | effective_top | hysteresis_only or effective_top. Any other value is an error. |
| `Nonlinear.UseRechargeHysteresis` | int | 1 | Use hysteresis for recharge receiver wet/dry switching |
| `Nonlinear.RechargeDryingSaturatedFraction` | number | 5.0e-3 | Minimum saturated thickness fraction for a previous recharge receiver to remain active |
| `Nonlinear.RechargeWettingSaturatedFraction` | number | 5.0e-2 | Minimum saturated thickness fraction for a new recharge receiver to become active |
| `Nonlinear.RechargeMinRelativeK` | number | 1.0e-4 | Minimum relative conductivity for a cell to receive routed recharge |
| `Nonlinear.EffectiveTopMode` | string | recharge_receivers | off, recharge_receivers or all_water_table_cells. Any other value is an error. hysteresis_only in Nonlinear.RechargeStabilizationMode forces off. |

### [Output]

| Option | Type | Default | Description |
|---|---|---|---|
| `Output.Prefix` | string | required | Prefix of every output file name. Files are written as <Paths.Output>/<Prefix>_<suffix>. |
| `Output.Print_initial_mesh` | int | 0 | 1 writes <prefix>_initial_mesh.vtk (rank 0, before refinement). |
| `Output.Print_mesh_with_prop` | int | 0 | 1 writes the final mesh with nodal properties and boundary-condition data. |
| `Output.Print_mesh_exit` | int | 0 | 1 exits after the initial mesh output, before setup and solve. |
| `Output.Save_trace_data` | int | 0 | 1 writes the mesh and velocity data read by npsat_trace. Requires Output.Save_fine_velocities or Output.Save_coarse_velocities. |
| `Output.Save_fine_velocities` | int | 1 | 1 writes the fine-dominated RT0 face velocities (default scheme of npsat_trace). |
| `Output.Save_coarse_velocities` | int | 0 | 1 writes the coarse-dominated RT0 face velocities. |
| `Output.Print_vtk` | int | 0 | Read and not applied. |
| `Output.Print_water_table` | int | 0 | 1 writes <prefix>_water_table_rank_NNNN_step_SSS.dat. |
| `Output.Print_q_to_vtu` | int | 0 | 1 adds the face flux of each cell to the VTU and cell-centre VTK output. |
| `Output.Print_lambda_to_vtu` | int | 0 | 1 adds the face head trace of each cell to the VTU and cell-centre VTK output. |
| `Output.Print_area_to_vtu` | int | 0 | 1 adds the face area of each cell to the VTU and cell-centre VTK output. |
| `Output.Print_cell_budget_csv` | int | 0 | 1 writes <prefix>_cell_budget_rank_NNNN_step_SSS.csv. |
| `Output.Print_solution_cell_vtu` | int | 0 | 1 writes <prefix>_solution_cell_step_SSS_*.vtu (and .pvtu when more than one rank). |
| `Output.Print_cellcenters_vtk` | int | 0 | 1 writes <prefix>_cellcenters_rank_NNNN_step_SSS.vtk. |
| `Output.Print_cell_well_map_csv` | int | 0 | Write cell-well map CSV output |
| `Output.Print_trace_well_maps_csv` | int | 0 | Write trace-well coupling map CSV output |
| `Output.Print_wellbore_segments_csv` | int | 0 | Write wellbore segment CSV output |
| `Output.Print_wellbore_segments_vtu` | int | 0 | Write wellbore segment VTU output |
| `Output.Print_wellbore_segments_legacy_vtk` | int | 0 | Write wellbore segment legacy VTK output |
| `Output.Print_wellboreflow_csv` | int | 0 | Write wellbore flow CSV output |
| `Output.Print_well_resid_csv` | int | 0 | Write well residual CSV output |

### [Misc]

| Option | Type | Default | Description |
|---|---|---|---|
| `Misc.Print_matrices` | int | 1 | Prints element matrices; debugging. |
| `Misc.Verbose_level` | int | 0 | 0, 1 or 2; larger values print more diagnostics. |
| `Misc.Assembly_progress_frequency` | int | 10 | Assembly progress reporting interval in percent [0,100]; 0 disables reporting |
| `Misc.LogFile` | string | empty | Name of the detailed nonlinear log, relative to Paths.Output; empty disables it. |
| `Misc.Dry_wel_log` | int | 0 | Maintain per-rank dry-well snapshots and a rank-0 minimum-water-table summary when nonzero |

### Conventions

- The code fixes no units. The log labels the budget "volume/time". Head, elevations and
  coordinates share one length unit, conductivity is length per time, recharge is length per
  time, and time is the unit of the time step file. The examples use metres and days.
- `Simulation.Confined` and `Simulation.Steady_state` combine freely. The confined example
  needed one linear solve (`Schur system (Lambda) converged in 1 iterations`). The unconfined
  example iterated (`NL n | dH_inf ... | CONVERGED`) and wrote one `ITER` and one `ACCEPT` line
  per iteration to `Misc.LogFile`.
- A transient run repeats the first step as spin-up until the `Spinup.*` criteria pass or
  `Spinup.Iterations` solves are done, then advances through `Simulation.Nsteps` steps. The
  input time step of step `i` is `(Start_step + i) mod n`, `n` being the number of rows of the
  time step file, so output file names cycle when `Nsteps` exceeds `n`.
- The Refinement options default to 1 when omitted. The examples set all of them to 0.

## npsat_trace options

### [Data]

| Option | Type | Default | Description |
|---|---|---|---|
| `Data.Prefix` | string | required | Prefix of the npsat_v2 output files to read, including directory: <Paths.Output>/<Output.Prefix> of the flow run. |
| `Data.Particle_file` | string | required | Particle seed file (see "Particle file"). The path is used as given. |

### [Simulation]

| Option | Type | Default | Description |
|---|---|---|---|
| `Simulation.Delta_time_file` | string | required | File with one time step duration per row. Row k is traced through the flow output of step k. |
| `Simulation.Porosity` | number | 0.3 | Effective porosity; pore velocity is Darcy flux divided by it. |
| `Simulation.DtEps` | number | 0.01 | Remaining time at or below which a time step counts as complete. |
| `Simulation.Direction` | number | 1.0 | 0 or greater traces forward, less than 0 traces backward. |
| `Simulation.StagnantVelocityThreshold` | number | 1.0e-8 | Velocity magnitude below which a particle is stagnant for the current time step |
| `Simulation.WellCaptureDistance` | number | 10.0 | Near-well distance that always triggers a well-flow check |
| `Simulation.WellCaptureCellFraction` | number | 0.2 | Near-well check distance as a fraction of cell diameter |
| `Simulation.WellInfluenceQScale` | number | 1.0 | Well influence radius multiplier applied to sqrt(abs(Qe)) |
| `Simulation.WellInfluenceMaxCellFraction` | number | 0.45 | Maximum well influence radius as a fraction of cell diameter |
| `Simulation.MaxProcessorExchanges` | int | 100 | Maximum particle exchanges per time step |
| `Simulation.MaxStreamlineSteps` | int | 10000 | Maximum integration steps per particle streamline |
| `Simulation.MaxNonExpandingSteps` | int | 50 | Terminate particles after this many non-expanding trajectory steps |
| `Simulation.MaxAge` | int | 2147483647 | Maximum total particle travel time. |
| `Simulation.Max_particles_per_iter` | int | 20000 | Number of seeds read and traced per iteration (chunk). Seeds from a well row are not split across chunks. |
| `Simulation.TransportMethod` | string | point | Transport method: point or trajectory_atlas |
| `Simulation.VelocityInterpolation` | string | split_rt0 | Velocity interpolation scheme: split_rt0, coarse_rt, idw, or cell_idw |

### [IDW]

| Option | Type | Default | Description |
|---|---|---|---|
| `IDW.Power` | number | 2.0 | Inverse-distance weighting power |
| `IDW.ProximityTolerance` | number | 0.01 | Use a sample directly when the anisotropic distance is below this tolerance |
| `IDW.AnisotropyRatio` | number | 0.0 | Vertical distance multiplier; zero estimates it from cell geometry |

### [Point]

| Option | Type | Default | Description |
|---|---|---|---|
| `Point.MaxStep` | number | 100000.0 | Maximum point-tracing distance advanced in one substep |
| `Point.StepsPerCell` | unsigned int | 5 | Minimum number of point-tracing substeps across one directional cell width |
| `Point.MaxStepTime` | number | 100.0 | Maximum point-tracing time advanced in one substep |
| `Point.StepsPerTime` | unsigned int | 3 | Minimum number of point-tracing substeps per transient time step |

### [Atlas]

| Option | Type | Default | Description |
|---|---|---|---|
| `Atlas.QuadraturePointsPerDirection` | unsigned int | 2 | Tensor-product quadrature points per subface direction |
| `Atlas.StoredSamplesPerTrajectory` | unsigned int | 8 | Number of time-ordered samples retained on each local atlas trajectory |
| `Atlas.MaximumQuerySamples` | unsigned int | 32 | Maximum nearby cached samples used by an atlas query |
| `Atlas.MaximumLocalSteps` | unsigned int | 200 | Maximum integration steps while constructing one cell-local atlas trajectory |
| `Atlas.MaximumBranchesPerPacket` | unsigned int | 16 | Maximum branches retained after one atlas query |
| `Atlas.KernelPower` | number | 2.0 | Inverse-distance kernel power for interior atlas queries |
| `Atlas.KernelEpsilon` | number | 1.0e-6 | Dimensionless regularization for atlas distance weights |
| `Atlas.MinimumPacketWeight` | number | 0.01 | Stop propagating atlas packets below this flow amount |
| `Atlas.MinimumSplitWeight` | number | 0.01 | Approximate minimum packet flow amount needed per retained atlas split branch |
| `Atlas.FlowTolerance` | number | 1.0e-12 | Absolute flow tolerance used to classify atlas origins and terminals |
| `Atlas.BalanceRelativeTolerance` | number | 1.0e-5 | Relative cell/trajectory flow-balance diagnostic tolerance |

### [Output]

| Option | Type | Default | Description |
|---|---|---|---|
| `Output.Prefix` | string | required | Prefix of the streamline files, including directory. The directory must exist. |
| `Output.Print_loaded_tria` | int | 0 | 1 writes the reloaded triangulation as VTU with prefix <Output.Prefix>_dbg_reloaded. |
| `Output.Load_tria_exit` | int | 0 | 1 exits after loading the triangulation. |
| `Output.Write_bin` | int | 0 | 1 writes streamlines in binary format. |
| `Output.Write_ascii` | int | 1 | 1 writes streamlines in ASCII format. At least one of Write_bin and Write_ascii must be 1. |

### [Misc]

| Option | Type | Default | Description |
|---|---|---|---|
| `Misc.Dbg_prefix` | string | required | Prefix of debug files. Required although it is used only when a Misc debug option is 1. |
| `Misc.Init_cell_dbg` | int | 0 | Enable debug output for cell initialization |
| `Misc.Particle_traj_dbg` | int | 0 | Enable debug output for particle trajectories |
| `Misc.Cache_bilinear_coefficients` | int | 0 | Cache bilinear map coefficients in initialized cell velocity caches |

### Conventions

- `Simulation.TransportMethod = point` integrates each particle in the velocity field of the
  current flow step. `trajectory_atlas` builds cell-local trajectory atlases (`Atlas.*`); it was
  not run.
- `Simulation.VelocityInterpolation` selects how the face velocities are interpolated inside a
  cell: `split_rt0` (default) uses the fine-dominated data, `coarse_rt` the coarse-dominated
  data (requires `Output.Save_coarse_velocities = 1` in the flow run), `idw` and `cell_idw`
  inverse-distance weighting (`IDW.*`). Only `split_rt0` was run.
- Particle time is tracked in the unit of the time step file. A particle ends at the end of the
  last time step, at a boundary, at a well, or for one of the reasons listed under "Streamline
  files".

## Input files

All files are text. Fields are separated by white space; most readers also accept commas.
Lines whose first non-blank character is `#` and blank lines are skipped where a reader is
described as matrix-based.

### Time step file

One number per line (`#` comments allowed): the duration of input time step `k` on line `k`,
counted from 0. The number of lines is the number of input time steps. Every time-dependent input
(Dirichlet and general-head values, recharge, well rates, stream rates) has one column per line.
A steady-state run ignores the duration (`model_step_duration` is 0 in the budget history).

### Interpolation master file

Properties, recharge, initial head, boundary values, top and bottom elevations, and vertical
interface positions are given as functions of position by master files.

```
n_regions

n_vertices type spatial_file values_file
x0 y0
x1 y1
...
```

- Each region is a rectangle (`n_vertices = 2`, two opposite corners) or a polygon
  (`n_vertices > 2`) in the x-y plane. The region must have non-zero area.
- `type` is `CONST`, `SCATTER`, `GRIDDED`, `LATERAL_POLYLINE` or `LATERAL`.
- The regions are tested in file order and the first region that contains the point applies.
  A point outside every region has the value 0.
- `spatial_file` defines the spatial pattern. `CONST` does not read it; any word serves (the
  examples use `none`).
- `values_file` is a matrix of numbers: one row per spatial pattern identifier (one row for
  `CONST`) and one column per input time step. Separators are white space, commas, semicolons
  and tabs. All rows have the same number of columns. A column index beyond the last column
  uses the last column. A dimension line such as `1 1` is read as data, not as a header.
- Properties (`Properties.*`) always use column 0.

Example of a constant 1.0 over a 1020 x 1020 rectangle (`kxy.master` with `kxy.values`
holding `1.0`):

```
1

2 CONST none kxy.values
-10 -10
1010 1010
```

The spatial file formats below are stated from the comments of the readers and were not run.

- `GRIDDED`: lines `xorig ncol`, `yorig nrow`, `dx dy`, `nlay`, then for each layer an
  `nrow x ncol` block of integer identifiers, separated from the next layer by an
  `nrow x ncol` block of interface elevations. Identifiers select rows of the values file.
- `SCATTER`: line `n_points n_triangles`, line `mode_xy mode_z` (each `LINEAR` or `NEAREST`),
  `n_points` rows `x y ID1 [elev12 ID2 ...]`, then the triangle connectivity.
- `LATERAL_POLYLINE`: line `n_polyline_points nlay`, line `HOR_type VER_type` (`LINEAR` or
  `NEAREST`), the polyline points `x y`, then one row of identifiers per layer separated by
  rows of interface elevations. With `nlay = 0` the value is independent of z.

### Dirichlet and general-head files

```
N
TYPE nv master_file [conductance_master_file]
x1 y1
...
xnv ynv
```

`N` entries follow. Each has a `TYPE`, a vertex count, the master file of the boundary head, and,
in a general-head file only, the master file of the conductance. Vertices are x-y pairs.

| TYPE | Faces matched |
|---|---|
| `TOP` | top boundary faces whose plan-view footprint intersects the region |
| `BOT` | bottom boundary faces, same test |
| `EDGE` | vertical boundary faces with at least one vertex inside the region |
| `EDGETOP` | as `EDGE`, restricted to cells that also have a top boundary face |

- `nv = 2` builds a rectangle from two opposite corners, for every TYPE. A rectangle needs a
  non-zero extent in both x and y; a two-point line along an axis fails with
  `Rectangle boundary has zero area.` The example Dirichlet entries are 10-unit-wide rectangles
  centred on the faces x = 0 and x = 1000.
- `nv >= 3` builds a polygon.
- Entries are tested in file order; the first entry that matches a face applies.
- In a master file referenced from an `EDGE` entry, `LATERAL_POLYLINE` regions match faces
  within `BC.HalfWidth` of the polyline with at least `BC.MinOverlap` of overlap.

### Well file

Comma-separated, first line skipped as a header:

```
Eid,x,y,top,bottom,q_row,rw,Rskin,Kskin
```

| Column | Meaning |
|---|---|
| `Eid` | Integer well identifier, carried to the output |
| `x`, `y` | Well position |
| `top`, `bottom` | Elevations of the screened interval |
| `q_row` | Row of the `Sources.Well_Rates` matrix that gives the pumping rate |
| `rw` | Well radius |
| `Rskin` | Skin radius |
| `Kskin` | Skin hydraulic conductivity |

`rw`, `Rskin` and `Kskin` set the conductance between a well and the cells it intersects; the
rate is given by the rate table. The sign convention of the pumping rate is not stated in the
input readers. Wells were not run.

### Stream file

```
n_streams
npoints row_id [width]
x1 y1
x2 y2
...
```

`npoints = 2` gives a stream line with the half-width `width` (the field is present for two
points only); `npoints > 2` gives a polygon. `row_id` is the row of the `Sources.Stream_Rates`
matrix. The rate of a row is multiplied by the intersected area of each cell to give the
exchange volume rate. Streams were not run.

### Mesh file

For `Geometry.Type` other than `BOX`: the first line `n_vertices n_cells`, then `n_vertices`
lines `x y`, then `n_cells` lines of four vertex indices (counted from 0) in counter-clockwise order. The
two-dimensional mesh is extruded into as many layers as `Discretization.Vertical` defines and
conformed to `Geometry.Top` and `Geometry.Bottom`. Not run.

### Particle file

The format is chosen from the first data line: 7 columns give seeds, 10 columns give well rows.
Comments (`#`) and blank lines are skipped.

| Columns | Content |
|---|---|
| 7 | `Eid Sid x y z rt rf`: one particle at `(x, y, z)` |
| 10 | `Eid x y ztop zbot rt rf nlay n_per_layer radius`: `nlay * n_per_layer` particles on `nlay` circles of the given radius around `(x, y)`, at elevations evenly spaced from `zbot` to `ztop` |

`Eid` and `Sid` identify a particle in the output. For well rows `Sid = ilay * n_per_layer + j`.
A well row needs `nlay >= 2`, `n_per_layer >= 2` and `radius > 0`. `rt` and `rf` are read and
not used by any code found in the source.

## Output files

The prefix is `<Paths.Output>/<Output.Prefix>`. `NNNN` is the MPI rank with four digits and `SSS` the
input time step with three digits. Files marked "binary" are read by `npsat_trace` and their
layout is not documented here.

### npsat_v2

| File | Written when | Content |
|---|---|---|
| `<prefix>_time_step_budget_history.csv` | always, rank 0 | One row per model step; columns below |
| `<Misc.LogFile>` | `Misc.LogFile` set | Two header lines name the columns of the `ITER` and `ACCEPT` lines written per nonlinear iteration |
| `<prefix>_cell_budget_rank_NNNN_step_SSS.csv` | `Output.Print_cell_budget_csv = 1` | One row per cell; columns below |
| `<prefix>_cellcenters_rank_NNNN_step_SSS.vtk` | `Output.Print_cellcenters_vtk = 1` | Legacy ASCII VTK point cloud, one point per cell centre, point data `active_cell_index`, `head`, `dS`, `Qw` |
| `<prefix>_solution_cell_step_SSS_CCCC.N.vtu`, `.pvtu` | `Output.Print_solution_cell_vtu = 1` | Point data `head`, `Qw`, `dS` on the hexahedral mesh, constant within each cell; `CCCC` is the input time step with four digits; one `.vtu` per group of ranks and a `.pvtu` that joins them; a single `<prefix>_solution_cell_step_SSS.vtu` with one rank |
| `<prefix>_water_table_rank_NNNN_step_SSS.dat` | `Output.Print_water_table = 1` | `x y top_cell effective_top wt uses_effective_top` per water-table column |
| `<prefix>_coarse_tria_vertices.dat`, `_coarse_tria_cells.dat` | `Output.Save_trace_data = 1` | Coarse mesh read by `npsat_trace` |
| `<prefix>_dist_tria`, `_dist_tria.info` | `Output.Save_trace_data = 1` | Distributed triangulation, binary |
| `<prefix>_velmap_rank_NNNN.bin` | `Output.Save_trace_data = 1` | Mapping of velocity degrees of freedom, binary |
| `<prefix>_Vface_rt0_vals_rank_NNNN_step_SSS.bin` | `Output.Save_trace_data = 1` and `Save_fine_velocities = 1` | Face velocities, binary |
| `<prefix>_Vface_coarse_rt_vals_rank_NNNN_step_SSS.bin` | `Save_coarse_velocities = 1` | Coarse-dominated face velocities, binary |
| `<prefix>_water_table_rank_NNNN_step_SSS.bin` | `Output.Save_trace_data = 1` | Water table for tracing, binary (magic `WTABLEv2`) |
| `<prefix>_cellwell_map_rank_NNNN.bin`, `_particle_well_flows_rank_NNNN_step_SSS.bin` | `Output.Save_trace_data = 1` | Well coupling data, binary; 24 bytes in a run without wells |
| `npsat_flow.chk.meta`, `npsat_flow.chk.slotN.rankNNNNNN` | always | Checkpoint (`Simulation.Checkpoint_file`), two alternating slots |
| `<prefix>_initial_mesh.vtk`, `_mesh_properties*` | `Print_initial_mesh`, `Print_mesh_with_prop` | Mesh output |
| well CSV, VTU and VTK files | `Output.Print_*well*` | Wellbore and well-residual output; not run |

Time step budget history columns (`volume/time` unless stated):
`simulation_counter`, `input_data_time_step`, `model_step_duration`, `wall_seconds`,
`wall_minutes`, `wall_hours`, `recharge`, `streams`, `wells_applied`,
`storage_volume_change` (volume), `storage_rate`, `storage_rate_throughput_fraction`,
`dirichlet_inflow`, `dirichlet_outflow`, `dirichlet_net_outflow`, `complete_budget_inflow`,
`complete_budget_outflow`, `budget_residual`, `budget_percent_discrepancy` (percent),
`dry_wells`, `requested_pumping`, `pumping_loss`, `pumping_loss_fraction`.

Cell budget columns: the header names 26 fields, `cell_id`, `Xc`, `Yc`, `Zc`, `dof0` to `dof5`,
`Qface0` to `Qface5`, `Qw`, `Qwbf`, `dS_rate`, `head`, `lambda0` to `lambda5`. Each row holds 25
fields: the value of `Qwbf` is not written, so from `Qwbf` onward the header names are shifted
by one column against the values. Counted from the row end, the last six values are
`lambda0` to `lambda5` (head on the six faces) and the value before them is the cell head.
`Qface0` to `Qface5` are volumetric rates through the six faces in deal.II face order (0 and 1
are the low and high x faces); in the confined example face 0 carries -40 and face 1 +40 volume/time,
so flow out of the cell is positive. `cell_id` is the deal.II cell identifier (`<coarse>_<path>:`).

### npsat_trace

| File | Content |
|---|---|
| `<Output.Prefix>_streamlines_ordered_rank_NNNN_iter_IIII.dat` | Streamline points and termination records, sorted by `Eid`, `Sid`; iteration `IIII` counts particle chunks; with `Output.Write_bin = 1` a `.bin` file with the same records |
| `<Output.Prefix>_streamlines_tmp_rank_NNNN.dat` | Per-rank working file, overwritten in every iteration |

The ASCII file has seven columns per line. A point line is `pid Eid Sid x y z vmag`, where `pid`
counts the points of the particle from 0 and `vmag` is the pore velocity magnitude. A
termination line is `-1 pid Eid Sid end_reason 0 0`.

### Streamline files

| `end_reason` | Name in the source | Meaning |
|---|---|---|
| 1 | `er_reached_dt_end` | Reached the end of the time step on this rank; not a termination |
| 2 | `er_entered_ghost` | Entered a ghost cell |
| 3 | `er_exited_domain` | Left the domain |
| 4 | `er_stuck` | No progress |
| 5 | `er_bad_mapping` | Position could not be mapped in its cell |
| 6 | `er_zero_velocity` | Zero velocity |
| 7 | `er_water_table` | Reached the water table |
| 8 | `MAX_ITER` | Maximum number of integration steps |
| 9 | `MAX_AGE` | Maximum age |
| 10 | `er_bottom` | Reached the bottom boundary |
| 11 | `er_lateral` | Reached a lateral boundary |
| 12 | `er_well_captured` | Captured by a well |
| 13 | `er_well_mass_balance` | Well mass balance exhausted |
| 14 | `er_nonexpanding` | Non-expanding trajectory steps exceeded `Simulation.MaxNonExpandingSteps` |
| 15 | `er_max_proc_exchanges` | Exceeded `Simulation.MaxProcessorExchanges` |

The names are those of `enum EndReason` in `npsat_trace/trace_structures.h`; the meanings are
read from the names and the options that refer to them. Code 11 (lateral boundary) was
observed in the confined example; the other codes were not produced.

## Behaviour on errors

| Situation | Observed result |
|---|---|
| Configuration file missing, unknown option, required option missing | Message on the console, exit status 0 |
| Input file missing, output directory missing, exception during the run | `Exception on processing:` and the message, exit status 1 |
| `npsat_trace` rank count differs from the flow run | `Abort: num procs mismatch`, exit status 134 |
| `npsat_trace` output directory missing | `Could not open ASCII streamline output: <file>`, exit status 1 |

A zero exit status therefore does not establish success. `npsat_v2` prints `Simulation Finished`
and `npsat_trace` prints `COMPLETED PARTICLE CHUNK ITERATION` when they complete.

## Other behaviour observed in the source and in runs

- `Paths.Output` without a trailing slash puts the multi-rank VTU and PVTU files next to the
  output directory (`outbox_solution_cell_*` instead of `out/box_solution_cell_*`). Other
  output is unaffected.
- `npsat_v2` writes the distributed triangulation with MPI-IO. On an NFS mount the save took 30 s
  for the 500-cell examples; on a local ext4 file system the whole run took 0.3 s.
- `Properties.*` accept master files only. The help strings say "a number or the name of a 3D
  function". A number is taken as a file name (`Cannot open file: ./input/1.0`).
- A seed on a cell face is inserted once for each cell that contains it: three seeds on cell
  faces gave `Initial particles: 6`. Seeds inside cells give one particle each.
- With one MPI rank, `npsat_v2` writes `<prefix>_solution_cell_step_SSS.vtu` and no `.pvtu`.
- The `Geometry.Top` and `Geometry.Bottom` surfaces are evaluated at time index 0.
- Checkpoint restart, dry-well handling, `trajectory_atlas` and well tracing have options and
  output but no case here exercises them.
