# NPSAT v2 on deal.II 9.3.2 and Boost 1.74.0: build and run environment.
#
#   docker build -t npsat .        (or: podman build -t npsat .)
#
# Plain Dockerfile syntax only, no BuildKit features; builds with Docker and Podman unchanged.
# The build context is the repository root (see .dockerignore).
#
# No official dealii/dealii image carries 9.3.2, so deal.II is built from the release tarball.
# The base is Ubuntu 22.04 because its Boost is 1.74.0.
#
# Pinned inputs:
#   base image       Ubuntu 22.04 by digest
#   apt packages     the snapshot.ubuntu.com archive state named by APT_SNAPSHOT, and every
#                    directly installed package by version
#   deal.II          9.3.2 release tarball by SHA-256
#
# Stages, so that a source change rebuilds only the last one:
#   toolchain   apt toolchain, MPI, p4est, Trilinos, Boost, Python 3
#   dealii      deal.II 9.3.2 compiled against it
#   npsat       the NPSAT sources compiled against deal.II, then the GUI and the examples

# ubuntu:22.04 as of 2026-09-30. The tag moves, the digest does not.
FROM docker.io/library/ubuntu:22.04@sha256:b8b6ee6aa931ecd9d0d952abc34dc0e5f7c6a30c6bb71b079fe399fde0329c02 AS toolchain

ARG APT_SNAPSHOT=20260930T000000Z
ENV DEBIAN_FRONTEND=noninteractive

# ca-certificates is installed from the stock mirrors only to verify the https snapshot archive;
# the pinned version below replaces it.
#
#   Boost 1.74      program_options and geometry (NPSAT); serialization, iostreams, system,
#                   thread, random and filesystem (deal.II)
#   OpenMPI 4.1.2   deal.II MPI, mpirun
#   p4est, libsc    parallel::distributed::Triangulation
#   Trilinos 13.2   Epetra, AztecOO, Amesos, Ifpack, ML and Teuchos for deal.II's Trilinos
#                   interface. The whole trilinos-all-dev set is installed: deal.II 9.3.2 rejects
#                   Debian's TrilinosConfig.cmake if any library it names is missing.
#   libscotch-dev, libptscotch-dev
#                   TrilinosConfig links the libptscotch.so symlink that only -dev ships.
#   Python 3        interpreter for the GUI (gui/server.py); standard library only.
#   TBB is left out: deal.II 9.3 supports the classic TBB API only and jammy ships oneTBB.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && printf 'deb https://snapshot.ubuntu.com/ubuntu/%s/ %s main restricted universe multiverse\n' \
      "${APT_SNAPSHOT}" jammy "${APT_SNAPSHOT}" jammy-updates "${APT_SNAPSHOT}" jammy-security \
      > /etc/apt/sources.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates=20260601~22.04.1 \
      curl=7.81.0-1ubuntu1.29 \
      g++=4:11.2.0-1ubuntu1 \
      gfortran=4:11.2.0-1ubuntu1 \
      make=4.3-4.1build1 \
      cmake=3.22.1-1ubuntu1.22.04.2 \
      pkg-config=0.29.2-1ubuntu3 \
      openmpi-bin=4.1.2-2ubuntu1 \
      libopenmpi-dev=4.1.2-2ubuntu1 \
      libp4est-dev=2.2-3 \
      libsc-dev=2.3.1-21 \
      trilinos-all-dev=13.2.0-1ubuntu1 \
      libscotch-dev=6.1.3-1 \
      libptscotch-dev=6.1.3-1 \
      libboost1.74-dev=1.74.0-14ubuntu3 \
      libboost-program-options1.74-dev=1.74.0-14ubuntu3 \
      libboost-serialization1.74-dev=1.74.0-14ubuntu3 \
      libboost-iostreams1.74-dev=1.74.0-14ubuntu3 \
      libboost-system1.74-dev=1.74.0-14ubuntu3 \
      libboost-thread1.74-dev=1.74.0-14ubuntu3 \
      libboost-random1.74-dev=1.74.0-14ubuntu3 \
      libboost-filesystem1.74-dev=1.74.0-14ubuntu3 \
      liblapack-dev=3.10.0-2ubuntu1 \
      libblas-dev=3.10.0-2ubuntu1 \
      zlib1g-dev=1:1.2.11.dfsg-2ubuntu9.2 \
      python3=3.10.6-1~22.04.1 \
 && rm -rf /var/lib/apt/lists/*

FROM toolchain AS dealii

# Release only, portable code generation:
#   DEAL_II_ALLOW_PLATFORM_INTROSPECTION=OFF   no -march=native, the image runs on any x86-64 host
#   DEAL_II_ALLOW_AUTODETECTION=OFF            only the features named here are enabled
#   DEAL_II_FORCE_BUNDLED_BOOST=OFF            the system Boost 1.74.0 is the only Boost
# JOBS is the compile parallelism; empty means all available cores. Each deal.II compile job
# needs about 1.5 GB of memory.
ARG JOBS=
RUN curl -fsSL -o /tmp/dealii-9.3.2.tar.gz \
      https://github.com/dealii/dealii/releases/download/v9.3.2/dealii-9.3.2.tar.gz \
 && echo "5341d76bfd75d3402fc6907a875513efb5fe8a8b99af688d94443c492d5713e8  /tmp/dealii-9.3.2.tar.gz" | sha256sum -c - \
 && mkdir /tmp/dealii-src \
 && tar -xzf /tmp/dealii-9.3.2.tar.gz -C /tmp/dealii-src --strip-components=1 \
 && cmake -S /tmp/dealii-src -B /tmp/dealii-build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/opt/dealii \
      -DDEAL_II_ALLOW_AUTODETECTION=OFF \
      -DDEAL_II_ALLOW_PLATFORM_INTROSPECTION=OFF \
      -DDEAL_II_COMPONENT_EXAMPLES=OFF \
      -DDEAL_II_COMPONENT_DOCUMENTATION=OFF \
      -DDEAL_II_WITH_MPI=ON \
      -DDEAL_II_WITH_P4EST=ON -DP4EST_DIR=/usr -DSC_DIR=/usr \
      -DDEAL_II_WITH_TRILINOS=ON -DTRILINOS_DIR=/usr \
      -DDEAL_II_FORCE_BUNDLED_BOOST=OFF -DBOOST_DIR=/usr \
      -DDEAL_II_WITH_LAPACK=ON \
      -DDEAL_II_WITH_ZLIB=ON \
 && cmake --build /tmp/dealii-build -j "${JOBS:-$(nproc)}" \
 && cmake --install /tmp/dealii-build \
 && rm -rf /tmp/dealii-src /tmp/dealii-build /tmp/dealii-9.3.2.tar.gz

ENV DEAL_II_DIR=/opt/dealii

FROM dealii AS npsat

ARG JOBS=

COPY CMakeLists.txt npsat_v2.cpp npsat_trace.cpp /opt/npsat/src/
COPY npsat_flow /opt/npsat/src/npsat_flow
COPY npsat_trace /opt/npsat/src/npsat_trace
RUN cmake -S /opt/npsat/src -B /opt/npsat/build -DDEAL_II_DIR=/opt/dealii -DCMAKE_BUILD_TYPE=Release \
 && cmake --build /opt/npsat/build -j "${JOBS:-$(nproc)}" \
 && mkdir -p /opt/npsat/bin \
 && cp /opt/npsat/build/npsat_v2 /opt/npsat/build/npsat_trace /opt/npsat/bin/ \
 && dpkg-query -W -f='${Package}=${Version}\n' | sort > /opt/npsat/dpkg-manifest.txt \
 && { cmake --version | head -1; g++ --version | head -1; mpirun --version | head -1; \
      grep -m1 '#define DEAL_II_PACKAGE_VERSION' /opt/dealii/include/deal.II/base/config.h; \
      grep -m1 '#define BOOST_LIB_VERSION' /usr/include/boost/version.hpp; \
      python3 --version; } > /opt/npsat/versions.txt

COPY gui /opt/npsat/gui
COPY examples /opt/npsat/examples
RUN ln -s /opt/npsat/gui/server.py /opt/npsat/bin/npsat-gui \
 && ln -s /opt/npsat/examples/run.sh /opt/npsat/bin/npsat-examples \
 && mkdir -m 1777 /runs \
 && groupadd --gid 1000 npsat \
 && useradd --uid 1000 --gid 1000 --create-home --home-dir /home/npsat --shell /bin/bash npsat

# HOME is /tmp so that any numeric uid given with --user has a writable home.
# OMPI_MCA_rmaps_base_oversubscribe lets mpirun start more ranks than the host has cores.
# OMPI_ALLOW_RUN_AS_ROOT* lets mpirun start when the container user is root, which is the mapping
# of the invoking user under rootless Docker and Podman without --userns=keep-id.
# OMPI_MCA_btl_vader_single_copy_mechanism=none avoids the cross-memory-attach warning that
# OpenMPI prints when a container denies ptrace.
ENV PATH=/opt/npsat/bin:${PATH} \
    HOME=/tmp \
    NPSAT_EXAMPLES=/opt/npsat/examples \
    NPSAT_RUNS=/runs \
    OMPI_MCA_rmaps_base_oversubscribe=1 \
    OMPI_ALLOW_RUN_AS_ROOT=1 \
    OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
    OMPI_MCA_btl_vader_single_copy_mechanism=none

LABEL org.opencontainers.image.title="npsat" \
      org.opencontainers.image.description="NPSAT v2 on deal.II 9.3.2, Boost 1.74.0 and Ubuntu 22.04" \
      org.opencontainers.image.source="https://github.com/giorgk/npsat_v2_9_3"

USER 1000:1000
WORKDIR /runs
CMD ["npsat_v2", "--help"]
