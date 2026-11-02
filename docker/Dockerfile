# gufi-archive container image: GUFI plus the archive reporting scripts
#
# Build from the repository root so the checked-out reports/ are used:
#   docker build -f docker/Dockerfile -t gufi-archive .
#
# Apptainer / Singularity can run the resulting image without root:
#   apptainer pull gufi.sif docker://ghcr.io/umich-arc/gufi-archive:latest

# ----------------------------------------------------------------------
# Builder: compile GUFI at the pinned commit
# ----------------------------------------------------------------------
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# ubuntu 22.04's cmake 3.22 is old enough for the pinned GUFI tree; patch is
# used by GUFI's bundled SQLite build
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        cmake \
        git \
        wget \
        patch \
        gcc \
        g++ \
        make \
        pkg-config \
        autoconf \
        libpcre3-dev \
        libattr1-dev \
        attr \
        python3 && \
    rm -rf /var/lib/apt/lists/*

# The reports use this commit's older gufi_query / querydbs CLI options
ARG GUFI_COMMIT=226b604f4687ac055bde16f0d59742ad472fdb44

RUN git clone https://github.com/mar-file-system/GUFI.git /GUFI && \
    git -C /GUFI checkout --detach "${GUFI_COMMIT}"

WORKDIR /GUFI/build

# The bundled googletest tarball doesn't extract where the build expects
# (GUFI#90), so let it download googletest main instead; main no longer
# compiles GUFI's C++11 unit tests, which the reports don't need
RUN rm ../contrib/deps/googletest.tar.gz && \
    sed -i '/add_subdirectory(googletest)/d' ../test/unit/CMakeLists.txt && \
    cmake -DDEP_BUILD_THREADS="$(nproc)" .. && \
    make -j"$(nproc)" && \
    make install

# Same config edits as the retired singularity.def
RUN cp /etc/GUFI/config.example /etc/GUFI/config && \
    sed -i -e 's/IndexRoot/#IndexRoot/' -e 's/Threads/#Threads/' /etc/GUFI/config && \
    echo "IndexRoot=/tmp/GUFI" >> /etc/GUFI/config && \
    echo "Threads=12" >> /etc/GUFI/config

# ----------------------------------------------------------------------
# Runtime: GUFI's runtime libraries, its install and the reports
# ----------------------------------------------------------------------
FROM ubuntu:22.04

LABEL maintainer="brockp@umich.edu"
LABEL org.opencontainers.image.source="https://github.com/umich-arc/gufi-archive"
LABEL org.opencontainers.image.description="GUFI filesystem indexing and reports for archiving or purging data from primary storage"

ENV DEBIAN_FRONTEND=noninteractive

# python3 runs the gufi_ls / gufi_find wrappers, bsdextrautils provides the
# column command the reports format their output with
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libpcre3 \
        python3 \
        bsdextrautils \
        attr && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local /usr/local
COPY --from=builder /etc/GUFI /etc/GUFI
COPY reports /gufi-archive/reports

# Docker ENV is imported by Apptainer/Singularity, matching the old .sif %environment
ENV PATH="/gufi-archive/reports:${PATH}"

WORKDIR /data

CMD ["gufi_ls", "--help"]
