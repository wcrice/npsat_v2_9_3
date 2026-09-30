# NPSAT v2

NPSAT v2 is an MPI-parallel groundwater flow model and particle tracer built on deal.II 9.3.
It consists of two executables:

| Executable | Source | Purpose |
|---|---|---|
| `npsat_v2` | `npsat_v2.cpp`, `npsat_flow/` | Solves steady or transient saturated flow on a three-dimensional hexahedral mesh and writes heads, cell budgets and the face velocity field |
| `npsat_trace` | `npsat_trace.cpp`, `npsat_trace/` | Reads the mesh and velocity field written by `npsat_v2` and follows particles through it, forward or backward |

Both programs take one configuration file (`-c file`) and run under `mpirun`. `npsat_trace` must
use the rank count of the `npsat_v2` run it reads.

Flow is solved with a hybridized mixed finite element method: a Raviart-Thomas flux, a
cell-wise constant head and a head trace on the cell faces (`FE_RaviartThomas`, `FE_DGQ`,
`FE_FaceQ` in `npsat_v2.cpp`), with Trilinos linear solvers. Unconfined aquifers are solved with
Picard iteration and optional Anderson acceleration. The model accepts areal recharge, stream
and multi-node well sources, Dirichlet and general-head boundaries, and time-varying input.
Particle paths are integrated in the Raviart-Thomas velocity field, with porosity converting
Darcy flux to pore velocity.

The code fixes no unit system. Lengths, time, conductivity and storage must be consistent. The
example cases use metres and days.

## Contents of this branch

| Path | Content |
|---|---|
| `npsat_v2.cpp`, `npsat_trace.cpp`, `npsat_flow/`, `npsat_trace/` | Model sources |
| `Dockerfile`, `.dockerignore` | Image with deal.II 9.3.2, Boost 1.74.0, the two executables, the examples and the GUI |
| `container/run.sh` | Builds the image and runs the examples, the GUI or a shell with Docker or Podman |
| `examples/` | Two constructed reference cases with inputs, checks and expected output |
| `gui/` | Local web interface |
| `docs/reference.md` | Configuration options, input file formats, output files |
| `docs/tutorial.md` | Walkthrough of one case from input to result |

The sources are those of upstream branch `trace_dbg` at commit `7f67337`. The default branch
`main` holds only a scaffold that prints the MPI rank. Two build fixes are applied to that
commit: `npsat_flow/helper_func.h` includes `<sys/stat.h>` (`stat()` and `S_ISDIR` are used
without it), and `CMakeLists.txt` links Boost.Program_options, which `flow_input.h` and
`trace_input.h` use. No numerical code is changed.

## Running in a container

```bash
container/run.sh
```

The command builds the image (about 10 to 12 minutes cold with 24 compile jobs, mostly the
deal.II compile; the image is 1.4 to 1.5 GB), then runs both example cases on 4 MPI ranks,
checks the results against analytic values and compares them with the stored reference output.
The exit status is non-zero when a step, a check or a comparison fails. Output is written to
`runs/` in the repository.

| Command | Action |
|---|---|
| `container/run.sh test` | Build if needed, run the examples and their checks (default) |
| `container/run.sh build` | Build the image |
| `container/run.sh gui` | Serve the GUI on `http://127.0.0.1:8765/` until interrupted |
| `container/run.sh serve` | As `gui`, detached and restarted by the container runtime; `container/run.sh stop` removes it |
| `container/run.sh shell` | Shell in the image, with the executables in `PATH` |

Settings are environment variables (`NPSAT_RUNTIME`, `NPSAT_IMAGE`, `NPSAT_RUNS`, `NPSAT_NP`,
`NPSAT_GUI_PORT`, `NPSAT_GUI_BIND`, `NPSAT_GUI_HOSTS`, `NPSAT_CONTAINER_NAME`, `NPSAT_CASES`,
`NPSAT_JOBS`, `NPSAT_NO_CACHE`), documented at the top of `container/run.sh`.

The Dockerfile uses no BuildKit-specific syntax and the launcher needs no compose file. The
container runs as the invoking user, and the GUI port is published on `127.0.0.1` unless
`NPSAT_GUI_BIND` names another address (see "Serving the GUI on a network address").

Tested runtimes (Ubuntu 24.04 hosts, x86-64):

| Runtime | Mode | Result |
|---|---|---|
| Docker 29.1.3 | rootful daemon, classic builder (no buildx) | image built; both examples passed their checks and matched `expected/`; GUI ran and displayed a run and a failed run |
| Podman 4.9.3 | rootless, `--userns=keep-id`, image storage on a local disk | same |

The two images built independently from the same commit list the same 400 packages at the same
versions. Rootless Docker, SELinux-enforcing hosts and macOS or Windows container hosts were not
tested. Rootless Podman failed to build on image storage located on an NFS home directory
(`Value too large for defined data type` from `chmod` in the `openssh-client` post-installation
script during the apt install); the image storage must be on a local file system. The host
directory given by `NPSAT_RUNS` should also be local: `npsat_v2` saves its mesh with MPI-IO, and
that step took 30 s per run on NFS against 0.3 s on a local disk.

The image pins the Ubuntu 22.04 base image by digest, the apt archive by snapshot date
(`APT_SNAPSHOT` in the `Dockerfile`), every directly installed package by version, and the
deal.II 9.3.2 tarball by SHA-256. The build needs network access to Docker Hub,
`snapshot.ubuntu.com` and `github.com`; running needs none. The image contains the compiler
toolchain. After editing the sources, `container/run.sh build` recompiles only the NPSAT stage.

## Building without a container

Requirements: deal.II 9.3.x configured with MPI, p4est and Trilinos, Boost with
`program_options` (1.74.0 was used), CMake (3.22.1 was used) and a C++ compiler accepted by
deal.II 9.3 (GCC 11.4.0 was used).

```bash
cmake -S . -B build -DDEAL_II_DIR=/path/to/dealii -DCMAKE_BUILD_TYPE=Release
cmake --build build -j 8
```

`CMAKE_BUILD_TYPE` must match a deal.II library that is installed (Release only in the image).
The build produces `build/npsat_v2` and `build/npsat_trace`. The upstream build environment is
not documented; only the container toolchain above was tested.

## Running the model

```bash
mkdir -p run/out run/trace && cp -r examples/box_confined/. run/ && cd run
mpirun -n 4 npsat_v2    -c flow.ini      # heads, budgets, velocity field
mpirun -n 4 npsat_trace -c trace.ini     # particle paths
```

`npsat_v2 -h` and `npsat_trace -h` print every configuration option with its default.
`npsat_v2 -v` and `npsat_trace -v` print the program version (0.0.05 and 0.0.02).

An unknown or missing option, or an unreadable configuration file, does not produce a non-zero
exit status: both programs print the message and exit 0. A run has completed only when `npsat_v2` has printed `Simulation Finished` and
`npsat_trace` has printed `COMPLETED PARTICLE CHUNK ITERATION`. The examples' `check.sh` and the
GUI test for these lines.

## GUI

`container/run.sh gui` serves a local page at `http://127.0.0.1:8765/`. It edits the
configuration of a case, starts `npsat_v2` and, when a trace configuration is present,
`npsat_trace`, shows the models' own output unchanged, marks the run as failed when a program
exits non-zero or does not print its completion line, lists the output files for download, and
draws two static plots: head at the cell centres (plan view and a section, from the cell-centre
VTK files) and the traced particle paths (from the ordered streamline files). Output is written to
`runs/gui-<time>-<case>/`. The page opens on the most recent run of the output directory, and a
run can be selected from the list. Extra cases are listed from the directory given in
`NPSAT_CASES` (same layout as `examples/`). The server has no authentication.

### Serving the GUI on a network address

`container/run.sh serve` starts the GUI detached, as a container named `$NPSAT_CONTAINER_NAME`
with the restart policy `unless-stopped`, publishing the GUI port on `$NPSAT_GUI_BIND`. The GUI
refuses a request whose `Host` header names a host that is not in `NPSAT_GUI_HOSTS` (besides
`localhost`, `127.0.0.1` and `::1`), so the name used in the URL must be listed.

```bash
NPSAT_GUI_BIND=192.0.2.10 NPSAT_GUI_PORT=8120 NPSAT_GUI_HOSTS=npsat.example.net,192.0.2.10 \
NPSAT_RUNS=/var/tmp/npsat-runs container/run.sh serve
# http://npsat.example.net:8120/
container/run.sh stop
```

`NPSAT_GUI_BIND` is the address of a host interface and `NPSAT_RUNS` should be on a local disk.
Anything that can reach that address can start runs as the invoking user, edit the configuration
text that those runs use, and read the run output. Serve only on a network whose hosts are all
trusted. To show a finished run on arrival, start the two examples once through the page or with

```bash
curl -s -X POST -H 'Content-Type: application/json' http://npsat.example.net:8120/api/runs \
  -d "$(python3 -c 'import json,sys; print(json.dumps({"case": "box_confined", "flow_ini": open("examples/box_confined/flow.ini").read(), "trace_ini": open("examples/box_confined/trace.ini").read(), "np": 4}))')"
```

A second request is refused with status 409 while a run is active.

## Examples

`examples/box_confined` and `examples/box_unconfined` were constructed from reading the source.
The upstream author did not supply them, and they are not validated benchmarks. Each is a
1000 x 1000 x 100 m box of 10 x 10 x 5 cells with Kxy = Kz = 1 m/d, head 80 m on the west face and
60 m on the east face. They check the solver against analytic or conservation results
(`check.sh`), not against any published NPSAT result. `examples/<case>/expected/` holds the output
of a reference run on 4 ranks. `docs/tutorial.md` walks through the confined case.

## Not established

The following are not determined by the source or were not exercised:

- Agreement with any published NPSAT v2 result. None is available.
- Wells, streams, general-head and Neumann boundaries, transient runs, mesh refinement,
  checkpoint restart, `trajectory_atlas` tracing, the `idw`, `cell_idw` and `coarse_rt` velocity
  schemes, `FILE` geometry, and gridded, scattered and lateral-polyline input were not run.
- `BC.Neumann`, `Sources.Well_factor` and `Output.Print_vtk` are read from the configuration
  and not referenced elsewhere in the source. The Neumann file is never opened.
- The meaning of the `rt` and `rf` columns of the particle file: they are read and not used.
- The rule that ends a particle at the water table (end reason 7) was not investigated.
- Performance and scaling: the examples have 500 cells.
- Whether the `sys/stat.h` include and the Boost link are needed with the upstream author's
  toolchain.
- Whether the upstream author builds against deal.II 9.3.0 or 9.3.2: `CMakeLists.txt` requires
  9.3.0 or later and the repository description names 9.3.2.

Behaviour observed in the source that a user will meet is listed in `docs/reference.md`.
