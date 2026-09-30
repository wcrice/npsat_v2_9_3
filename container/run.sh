#!/usr/bin/env bash
# Builds the NPSAT image and runs it with Docker or Podman.
#
#   container/run.sh [test|build|gui|serve|stop|shell]      default: test
#
#   test    build the image if it is absent, run the example cases and their checks
#   build   build the image (rebuilds only the stages whose inputs changed)
#   gui     build the image if it is absent, serve the GUI in the foreground on
#           http://$NPSAT_GUI_BIND:$NPSAT_GUI_PORT/ until interrupted
#   serve   as gui, but detached: the container is named $NPSAT_CONTAINER_NAME and restarts with
#           the container runtime unless it was stopped
#   stop    remove the container started by serve
#   shell   build the image if it is absent, open a shell in it
#
# Settings (environment):
#   NPSAT_RUNTIME   docker or podman   default: docker if installed, otherwise podman
#   NPSAT_IMAGE     image name         default npsat:local
#   NPSAT_RUNS      host directory that receives run output, mounted at /runs
#                                      default <repository>/runs
#   NPSAT_NP        MPI ranks          default 4
#   NPSAT_GUI_PORT  host port of the GUI                                  default 8765
#   NPSAT_GUI_BIND  host address the GUI port is published on             default 127.0.0.1
#   NPSAT_GUI_HOSTS comma-separated host names, besides localhost, that the GUI accepts in the
#                   Host header; set it to the name used in the URL when NPSAT_GUI_BIND is not
#                   a loopback address                                     default none
#   NPSAT_CONTAINER_NAME  name of the container started by serve         default npsat-gui
#   NPSAT_CASES     host directory of extra cases listed by the GUI (same layout as examples/),
#                   mounted read-only at /cases                      default unset
#   NPSAT_JOBS      compile parallelism of the image build; empty means all cores   default empty
#   NPSAT_NO_CACHE  any non-empty value builds without the layer cache              default unset
#
# The container runs as the invoking user, so files in NPSAT_RUNS belong to that user. No
# compose file, no rootful daemon and no network access is required beyond the image build.
#
# The GUI has no authentication. Publishing it on an address other than 127.0.0.1 lets every
# host that can reach that address start runs as the invoking user.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
mode=${1:-test}
case "$mode" in test|build|gui|serve|stop|shell) ;; *) echo "usage: $0 [test|build|gui|serve|stop|shell]" >&2; exit 2 ;; esac

rt=${NPSAT_RUNTIME:-}
if [ -z "$rt" ]; then
  if command -v docker >/dev/null 2>&1; then rt=docker
  elif command -v podman >/dev/null 2>&1; then rt=podman
  else echo "neither docker nor podman is installed; set NPSAT_RUNTIME" >&2; exit 1; fi
fi
command -v "$rt" >/dev/null 2>&1 || { echo "$rt is not installed" >&2; exit 1; }

image=${NPSAT_IMAGE:-npsat:local}
runs=${NPSAT_RUNS:-$repo/runs}
np=${NPSAT_NP:-4}
port=${NPSAT_GUI_PORT:-8765}
bind=${NPSAT_GUI_BIND:-127.0.0.1}
name=${NPSAT_CONTAINER_NAME:-npsat-gui}
if [ "$mode" != build ] && [ "$mode" != stop ]; then
  mkdir -p "$runs"
  runs=$(cd "$runs" && pwd -P)
fi

# Rootless Podman maps the invoking user to container root unless --userns=keep-id keeps the
# numeric uid, which the bind mount needs in order to be writable.
userflags=(--user "$(id -u):$(id -g)")
[ "$rt" = podman ] && userflags+=(--userns=keep-id)

build() {
  local args=(build -t "$image")
  [ -n "${NPSAT_JOBS:-}" ] && args+=(--build-arg "JOBS=$NPSAT_JOBS")
  [ -n "${NPSAT_NO_CACHE:-}" ] && args+=(--no-cache)
  "$rt" "${args[@]}" "$repo"
}

ensure_image() {
  "$rt" image inspect "$image" >/dev/null 2>&1 || build
}

case "$mode" in
  build)
    build
    ;;
  test)
    ensure_image
    "$rt" run --rm "${userflags[@]}" -v "$runs:/runs:z" "$image" cat /opt/npsat/versions.txt
    "$rt" run --rm "${userflags[@]}" -v "$runs:/runs:z" -e NPSAT_NP="$np" "$image" npsat-examples
    echo "run output: $runs"
    ;;
  gui|serve)
    ensure_image
    extra=()
    [ -n "${NPSAT_CASES:-}" ] && extra+=(-v "$(cd "$NPSAT_CASES" && pwd -P):/cases:ro,z" -e NPSAT_CASES=/cases)
    [ -n "${NPSAT_GUI_HOSTS:-}" ] && extra+=(-e "NPSAT_GUI_HOSTS=$NPSAT_GUI_HOSTS")
    common=("${userflags[@]}" -p "$bind:$port:8765" -v "$runs:/runs:z" -e NPSAT_NP="$np"
            ${extra[@]+"${extra[@]}"} "$image" npsat-gui)
    if [ "$mode" = serve ]; then
      "$rt" run -d --name "$name" --restart unless-stopped "${common[@]}"
      echo "GUI: http://$bind:$port/   (container $name; stop with: container/run.sh stop; run output: $runs)"
    else
      echo "GUI: http://$bind:$port/   (Ctrl-C stops it; run output: $runs)"
      "$rt" run --rm "${common[@]}"
    fi
    ;;
  stop)
    "$rt" rm -f "$name"
    ;;
  shell)
    ensure_image
    "$rt" run --rm -it "${userflags[@]}" -v "$runs:/runs:z" -e NPSAT_NP="$np" "$image" bash
    ;;
esac
