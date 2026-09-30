#!/usr/bin/env python3
"""Local web interface for NPSAT v2.

Edit a configuration, start npsat_v2 (and npsat_trace when a trace configuration is given),
read the models' own output, download the output files and view two basic plots: the solved head
at the cell centres and the traced particle paths. Python standard library only.

Settings (environment):
  NPSAT_CASES      directory of case directories (flow.ini, input/, optional trace.ini)
                   default: $NPSAT_EXAMPLES, else /opt/npsat/examples
  NPSAT_RUNS       directory that receives one run directory per run      default /runs
  NPSAT_NP         default MPI rank count offered by the page                default 4
  NPSAT_GUI_HOST   bind address                                              default 0.0.0.0
  NPSAT_GUI_PORT   bind port                                                 default 8765

The server has no authentication. Inside the container it binds 0.0.0.0 so that the published
port reaches it; container/run.sh publishes that port on 127.0.0.1 only.
"""
import glob
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

HERE = Path(__file__).resolve().parent
CASES = Path(os.environ.get("NPSAT_CASES") or os.environ.get("NPSAT_EXAMPLES") or "/opt/npsat/examples")
RUNS = Path(os.environ.get("NPSAT_RUNS", "/runs"))
DEFAULT_NP = int(os.environ.get("NPSAT_NP", "4"))
HOST = os.environ.get("NPSAT_GUI_HOST", "0.0.0.0")
PORT = int(os.environ.get("NPSAT_GUI_PORT", "8765"))

NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
STATE_FILE = ".gui-state.json"
MAX_BODY = 1 << 20
MAX_LOG = 400_000
MAX_PATHS = 2000

# End reasons written to the streamline files (npsat_trace/trace_structures.h, enum EndReason).
END_REASONS = {
    1: "reached end of time step", 2: "entered ghost cell", 3: "exited domain", 4: "stuck",
    5: "bad mapping", 6: "zero velocity", 7: "water table", 8: "maximum iterations",
    9: "maximum age", 10: "bottom", 11: "lateral boundary", 12: "well captured",
    13: "well mass balance", 14: "non-expanding", 15: "maximum processor exchanges",
}

lock = threading.Lock()
active = {"id": None}


# ---------------------------------------------------------------------------------------------
# Runs
# ---------------------------------------------------------------------------------------------

def list_cases():
    return sorted(p.name for p in CASES.iterdir() if (p / "flow.ini").is_file()) if CASES.is_dir() else []


def read_text(path):
    return path.read_text(errors="replace") if path.is_file() else ""


def write_state(run_dir, state):
    tmp = run_dir / (STATE_FILE + ".tmp")
    tmp.write_text(json.dumps(state))
    tmp.replace(run_dir / STATE_FILE)


def read_state(run_dir):
    try:
        return json.loads((run_dir / STATE_FILE).read_text())
    except (OSError, ValueError):
        return None


def start_run(case, flow_ini, trace_ini, np_):
    if not NAME.match(case) or not (CASES / case / "flow.ini").is_file():
        raise ValueError("unknown case: %s" % case)
    if not flow_ini.strip():
        raise ValueError("flow.ini is empty")
    if np_ < 1:
        raise ValueError("MPI rank count must be at least 1")
    with lock:
        if active["id"] is not None:
            raise RuntimeError("run %s is still active" % active["id"])
        run_id = time.strftime("gui-%Y%m%d-%H%M%S-") + case
        run_dir = RUNS / run_id
        run_dir.mkdir(parents=True)
        active["id"] = run_id
    try:
        shutil.copytree(CASES / case, run_dir, dirs_exist_ok=True, ignore=shutil.ignore_patterns("expected"))
        (run_dir / "out").mkdir(exist_ok=True)
        (run_dir / "trace").mkdir(exist_ok=True)
        (run_dir / "flow.ini").write_text(flow_ini)
        if trace_ini.strip():
            (run_dir / "trace.ini").write_text(trace_ini)
        elif (run_dir / "trace.ini").exists():
            (run_dir / "trace.ini").unlink()
        state = {"id": run_id, "case": case, "np": np_, "state": "running", "phase": "flow",
                 "message": "", "started": time.time(), "finished": None}
        write_state(run_dir, state)
    except Exception:
        with lock:
            active["id"] = None
        raise
    threading.Thread(target=execute, args=(run_dir, state), daemon=True).start()
    return run_id


def run_step(run_dir, state, phase, command, log_name):
    """Runs one model executable; returns an error message or None."""
    state["phase"] = phase
    write_state(run_dir, state)
    with open(run_dir / log_name, "wb") as log:
        try:
            rc = subprocess.run(command, cwd=run_dir, stdout=log, stderr=subprocess.STDOUT).returncode
        except OSError as exc:
            return "cannot start %s: %s" % (command[0], exc)
    if rc != 0:
        return "`%s` exited with status %d" % (" ".join(command), rc)
    return None


def execute(run_dir, state):
    np_ = str(state["np"])
    try:
        err = run_step(run_dir, state, "flow", ["mpirun", "-n", np_, "npsat_v2", "-c", "flow.ini"], "flow.log")
        # npsat_v2 returns 0 after printing a configuration error, so completion is read from its log.
        if err is None and "Simulation Finished" not in read_text(run_dir / "flow.log"):
            err = "npsat_v2 exited with status 0 without printing 'Simulation Finished'"
        if err is None and (run_dir / "trace.ini").is_file():
            err = run_step(run_dir, state, "trace", ["mpirun", "-n", np_, "npsat_trace", "-c", "trace.ini"], "trace.log")
            if err is None and not glob.glob(str(run_dir / "**" / "*_streamlines_ordered_rank_*"), recursive=True):
                err = "npsat_trace exited with status 0 and wrote no ordered streamline file"
        state["state"] = "failed" if err else "succeeded"
        state["message"] = err or ""
    except Exception as exc:  # the thread must always leave a final state
        state["state"] = "failed"
        state["message"] = "GUI error while running: %r" % exc
    state["phase"] = "done"
    state["finished"] = time.time()
    write_state(run_dir, state)
    with lock:
        active["id"] = None


def run_dir_of(run_id):
    if not NAME.match(run_id) or not (RUNS / run_id / STATE_FILE).is_file():
        raise KeyError(run_id)
    return RUNS / run_id


def tail(path):
    if not path.is_file():
        return ""
    size = path.stat().st_size
    with open(path, "rb") as fh:
        if size > MAX_LOG:
            fh.seek(size - MAX_LOG)
        text = fh.read().decode(errors="replace")
    return ("[earlier output omitted]\n" if size > MAX_LOG else "") + text


def run_info(run_id):
    run_dir = run_dir_of(run_id)
    state = read_state(run_dir)
    with lock:
        is_active = active["id"] == run_id
    if state["state"] == "running" and not is_active:
        state["state"] = "failed"
        state["message"] = "the GUI server stopped while the run was active"
    end = state["finished"] or time.time()
    files = []
    for p in sorted(run_dir.rglob("*")):
        if p.is_file() and p.name not in (STATE_FILE, STATE_FILE + ".tmp"):
            files.append({"path": str(p.relative_to(run_dir)), "size": p.stat().st_size})
    return {**state, "elapsed": end - state["started"],
            "logs": {"flow": tail(run_dir / "flow.log"), "trace": tail(run_dir / "trace.log")},
            "files": files}


def list_runs():
    out = []
    if RUNS.is_dir():
        for p in sorted(RUNS.glob("gui-*"), reverse=True):
            st = read_state(p)
            if st:
                out.append({"id": st["id"], "case": st["case"], "state": st["state"]})
    return out


# ---------------------------------------------------------------------------------------------
# Plots: legacy ASCII VTK cell-centre files and ordered streamline files, drawn as SVG
# ---------------------------------------------------------------------------------------------

def read_vtk_points(path):
    """Returns (points, {scalar name: values}) from a legacy ASCII POLYDATA file."""
    tok = path.read_text().split()
    i = tok.index("POINTS")
    n = int(tok[i + 1])
    pts = [(float(tok[i + 3 + 3 * k]), float(tok[i + 4 + 3 * k]), float(tok[i + 5 + 3 * k])) for k in range(n)]
    scalars = {}
    j = tok.index("POINT_DATA")
    while True:
        try:
            j = tok.index("SCALARS", j + 1)
        except ValueError:
            break
        name = tok[j + 1]
        k = tok.index("default", j) + 1
        scalars[name] = [float(v) for v in tok[k:k + n]]
    return pts, scalars


def head_points(run_dir):
    """Cell-centre points and heads of the last written step, merged over MPI ranks."""
    files = sorted(glob.glob(str(run_dir / "**" / "*_cellcenters_rank_*_step_*.vtk"), recursive=True))
    if not files:
        raise LookupError("no cell-centre VTK file in this run (Output.Print_cellcenters_vtk = 1 writes it)")
    step = max(re.search(r"_step_(\d+)\.vtk$", f).group(1) for f in files)
    pts, heads = [], []
    for f in files:
        if f.endswith("_step_%s.vtk" % step):
            p, s = read_vtk_points(Path(f))
            if "head" not in s:
                raise LookupError("%s has no 'head' scalar" % f)
            pts += p
            heads += s["head"]
    return pts, heads, int(step)


def colour(t):
    stops = [(68, 1, 84), (59, 82, 139), (33, 145, 140), (94, 201, 98), (253, 231, 37)]
    t = min(max(t, 0.0), 1.0) * (len(stops) - 1)
    k = min(int(t), len(stops) - 2)
    f = t - k
    return "#%02x%02x%02x" % tuple(round(a + (b - a) * f) for a, b in zip(stops[k], stops[k + 1]))


class Panel:
    """Maps data coordinates to a rectangle of the SVG."""

    def __init__(self, x0, y0, w, h, xr, yr):
        self.x0, self.y0, self.w, self.h, self.xr, self.yr = x0, y0, w, h, xr, yr

    def sx(self, x):
        span = (self.xr[1] - self.xr[0]) or 1.0
        return self.x0 + (x - self.xr[0]) / span * self.w

    def sy(self, y):
        span = (self.yr[1] - self.yr[0]) or 1.0
        return self.y0 + self.h - (y - self.yr[0]) / span * self.h

    def frame(self, title, xlabel, ylabel):
        out = ['<rect x="%g" y="%g" width="%g" height="%g" fill="none" stroke="#000"/>' % (self.x0, self.y0, self.w, self.h),
               '<text x="%g" y="%g" font-size="13" font-weight="bold">%s</text>' % (self.x0, self.y0 - 8, title),
               '<text x="%g" y="%g" font-size="11" text-anchor="middle">%s: %g to %g</text>'
               % (self.x0 + self.w / 2, self.y0 + self.h + 16, xlabel, self.xr[0], self.xr[1]),
               '<text font-size="11" text-anchor="middle" transform="translate(%g,%g) rotate(-90)">%s: %g to %g</text>'
               % (self.x0 - 10, self.y0 + self.h / 2, ylabel, self.yr[0], self.yr[1])]
        return out


def extent(values):
    lo, hi = min(values), max(values)
    if hi == lo:
        hi = lo + 1.0
    return lo, hi


def svg_wrap(w, h, body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" '
            'font-family="sans-serif">%s</svg>' % (w, h, w, h, "".join(body)))


def head_svg(run_dir):
    pts, heads, step = head_points(run_dir)
    xs, ys, zs = [p[0] for p in pts], [p[1] for p in pts], [p[2] for p in pts]
    xr, yr, zr = extent(xs), extent(ys), extent(zs)
    hlo, hhi = extent(heads)
    # Horizontal spacing from the number of distinct (x, y) columns; the axes extend beyond the
    # outermost cell centres so that the markers lie inside the frames.
    n_col = len({(round(x, 6), round(y, 6)) for x, y in zip(xs, ys)})
    spacing = math.sqrt((xr[1] - xr[0]) * (yr[1] - yr[0]) / n_col) if (yr[1] > yr[0] and xr[1] > xr[0]) else 1.0
    n_lay = len({round(z, 6) for z in zs})
    dz = (zr[1] - zr[0]) / (n_lay - 1) if n_lay > 1 else 1.0
    xr = (xr[0] - 0.6 * spacing, xr[1] + 0.6 * spacing)
    yr = (yr[0] - 0.6 * spacing, yr[1] + 0.6 * spacing)
    zr = (zr[0] - 0.6 * dz, zr[1] + 0.6 * dz)
    pw, ph = 400, 300
    plan = Panel(60, 40, pw, ph, xr, yr)
    sect = Panel(60 + pw + 70, 40, pw, ph, xr, zr)
    # Section: the cell centres whose y is closest to the middle of the domain.
    ymid = min(ys, key=lambda y: abs(y - (yr[0] + yr[1]) / 2))
    body = plan.frame("Plan view, all cell centres (top drawn last)", "x", "y")
    body += sect.frame("Section at y = %g" % ymid, "x", "z")
    r_xy = max(1.5, min(0.45 * spacing / (xr[1] - xr[0]) * pw, 0.45 * dz / (zr[1] - zr[0]) * ph))
    for k in sorted(range(len(pts)), key=lambda k: zs[k]):
        c = colour((heads[k] - hlo) / (hhi - hlo))
        body.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>' % (plan.sx(xs[k]), plan.sy(ys[k]), r_xy, c))
        if abs(ys[k] - ymid) < 1e-6 * max(1.0, abs(ymid)):
            body.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>' % (sect.sx(xs[k]), sect.sy(zs[k]), r_xy, c))
    bx, by = 60, 40 + ph + 50
    for i in range(100):
        body.append('<rect x="%g" y="%g" width="%g" height="12" fill="%s"/>' % (bx + i * 4, by, 4, colour(i / 99)))
    body.append('<text x="%g" y="%g" font-size="11">head %g</text>' % (bx, by + 28, hlo))
    body.append('<text x="%g" y="%g" font-size="11" text-anchor="end">%g</text>' % (bx + 400, by + 28, hhi))
    body.append('<text x="%g" y="%g" font-size="11">Head at %d cell centres, output step %d. Length units are those of the input data.</text>'
                % (bx, by + 46, len(pts), step))
    return svg_wrap(2 * pw + 190, ph + 140, body)


def read_paths(run_dir):
    """Returns {(Eid, Sid): [(x, y, z), ...]} and {(Eid, Sid): end_reason} from ordered streamline files."""
    files = sorted(glob.glob(str(run_dir / "**" / "*_streamlines_ordered_rank_*.dat"), recursive=True))
    if not files:
        raise LookupError("no ordered streamline file (*_streamlines_ordered_rank_*.dat) in this run")
    paths, reasons = {}, {}
    for f in files:
        with open(f) as fh:
            for line in fh:
                v = line.split()
                if len(v) != 7:
                    continue
                if v[0] == "-1":
                    reasons[(int(v[2]), int(v[3]))] = int(v[4])
                else:
                    paths.setdefault((int(v[1]), int(v[2])), []).append((float(v[3]), float(v[4]), float(v[5])))
    return paths, reasons


def paths_svg(run_dir):
    paths, reasons = read_paths(run_dir)
    keys = sorted(paths)[:MAX_PATHS]
    allp = [p for k in keys for p in paths[k]]
    try:
        pts, _, _ = head_points(run_dir)
        allp += pts
    except LookupError:
        pass
    xr, yr, zr = extent([p[0] for p in allp]), extent([p[1] for p in allp]), extent([p[2] for p in allp])
    pw, ph = 400, 300
    plan = Panel(60, 40, pw, ph, xr, yr)
    sect = Panel(60 + pw + 70, 40, pw, ph, xr, zr)
    body = plan.frame("Plan view", "x", "y") + sect.frame("Side view (projection on x-z)", "x", "z")
    palette = ["#1f77b4", "#d62728", "#2ca02c", "#9467bd", "#ff7f0e", "#8c564b", "#17becf", "#7f7f7f"]
    for n, k in enumerate(keys):
        c = palette[n % len(palette)]
        for panel, ax in ((plan, 1), (sect, 2)):
            poly = " ".join("%.1f,%.1f" % (panel.sx(p[0]), panel.sy(p[ax])) for p in paths[k])
            body.append('<polyline points="%s" fill="none" stroke="%s" stroke-width="1.2"/>' % (poly, c))
            body.append('<circle cx="%.1f" cy="%.1f" r="2.5" fill="%s"/>' % (panel.sx(paths[k][0][0]), panel.sy(paths[k][0][ax]), c))
    by = 40 + ph + 50
    body.append('<text x="60" y="%g" font-size="11">%d particle paths%s. Dot: start point. Line: path, ordered by point index.</text>'
                % (by, len(paths), " (first %d drawn)" % MAX_PATHS if len(paths) > MAX_PATHS else ""))
    counts = {}
    for k in paths:
        r = reasons.get(k)
        counts[r] = counts.get(r, 0) + 1
    text = "; ".join("%s: %d" % (END_REASONS.get(r, "no termination record" if r is None else "code %d" % r), n)
                     for r, n in sorted(counts.items(), key=lambda kv: (kv[0] is None, kv[0])))
    body.append('<text x="60" y="%g" font-size="11">Particles by end reason - %s</text>' % (by + 18, text))
    return svg_wrap(2 * pw + 190, ph + 110, body)


# ---------------------------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    server_version = "npsat-gui"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def reply(self, code, body, ctype, extra=None):
        data = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def json(self, obj, code=200):
        self.reply(code, json.dumps(obj), "application/json")

    def error(self, code, message):
        self.json({"error": message}, code)

    def host_ok(self):
        # Refuses requests whose Host header is not a loopback name (DNS rebinding).
        host = (self.headers.get("Host") or "").rsplit(":", 1)[0].strip("[]")
        return host in ("127.0.0.1", "localhost", "::1")

    def do_GET(self):
        if not self.host_ok():
            return self.error(403, "host not allowed")
        parts = [unquote(p) for p in urlparse(self.path).path.strip("/").split("/") if p]
        try:
            if not parts:
                return self.reply(200, (HERE / "index.html").read_bytes(), "text/html; charset=utf-8")
            if parts == ["api", "config"]:
                return self.json({"cases": list_cases(), "np": DEFAULT_NP, "runs": list_runs()})
            if len(parts) == 3 and parts[:2] == ["api", "cases"]:
                case = parts[2]
                if not NAME.match(case) or not (CASES / case / "flow.ini").is_file():
                    return self.error(404, "unknown case")
                return self.json({"flow_ini": read_text(CASES / case / "flow.ini"),
                                  "trace_ini": read_text(CASES / case / "trace.ini")})
            if len(parts) == 3 and parts[:2] == ["api", "runs"]:
                return self.json(run_info(parts[2]))
            if len(parts) == 5 and parts[:2] == ["api", "runs"] and parts[3] == "plot":
                run_dir = run_dir_of(parts[2])
                fn = {"head.svg": head_svg, "paths.svg": paths_svg}.get(parts[4])
                if fn is None:
                    return self.error(404, "unknown plot")
                try:
                    return self.reply(200, fn(run_dir), "image/svg+xml")
                except LookupError as exc:
                    return self.error(404, str(exc))
                except (ValueError, IndexError) as exc:
                    return self.error(500, "cannot read the output file: %s" % exc)
            if len(parts) >= 3 and parts[0] == "files":
                run_dir = run_dir_of(parts[1])
                target = (run_dir / Path(*parts[2:])).resolve()
                if run_dir.resolve() not in target.parents or not target.is_file() or target.name.startswith(".gui-state"):
                    return self.error(404, "no such file")
                text = target.suffix in (".ini", ".log", ".csv", ".dat", ".txt", ".vtk", ".master", ".values", ".info")
                return self.reply(200, target.read_bytes(),
                                  "text/plain; charset=utf-8" if text else "application/octet-stream")
        except KeyError:
            return self.error(404, "unknown run")
        return self.error(404, "not found")

    def do_POST(self):
        if not self.host_ok():
            return self.error(403, "host not allowed")
        if urlparse(self.path).path != "/api/runs":
            return self.error(404, "not found")
        if self.headers.get("Content-Type", "").split(";")[0].strip() != "application/json":
            return self.error(415, "Content-Type must be application/json")
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY:
            return self.error(413, "request too large")
        try:
            req = json.loads(self.rfile.read(length))
            run_id = start_run(str(req["case"]), str(req["flow_ini"]), str(req.get("trace_ini", "")),
                               int(req.get("np", DEFAULT_NP)))
        except RuntimeError as exc:
            return self.error(409, str(exc))
        except (ValueError, KeyError, TypeError) as exc:
            return self.error(400, str(exc))
        return self.json({"id": run_id})


def main():
    RUNS.mkdir(parents=True, exist_ok=True)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    print("NPSAT GUI on http://%s:%d/  cases: %s  runs: %s" % (HOST, PORT, CASES, RUNS), flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
