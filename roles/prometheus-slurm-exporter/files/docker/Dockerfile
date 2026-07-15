# DeepOps-owned Slurm exporter image, built locally by the
# prometheus-slurm-exporter role (no registry pull, no external source).
#
# The exporter source lives in this build context (see ../exporter). The
# container bind-mounts the host's Slurm client binaries and libraries, so
# the runtime stage provides a current glibc plus the system libraries those
# binaries link that are not part of the Slurm install prefix.
ARG SLURM_EXPORTER_BASE_IMAGE=ubuntu:24.04

FROM golang:1.24 AS build
COPY exporter/ /src/
RUN cd /src && CGO_ENABLED=0 go build -buildvcs=false -o /deepops-slurm-exporter .

FROM ${SLURM_EXPORTER_BASE_IMAGE}
# The slurm system user must resolve inside the container or the mounted
# Slurm client tools refuse to parse slurm.conf (SlurmUser lookup).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libmunge2 \
        libjson-c5 \
        libyaml-0-2 \
        liblz4-1 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --no-create-home --shell /usr/sbin/nologin slurm
COPY --from=build /deepops-slurm-exporter /usr/local/bin/deepops-slurm-exporter
ENTRYPOINT ["/usr/local/bin/deepops-slurm-exporter"]
