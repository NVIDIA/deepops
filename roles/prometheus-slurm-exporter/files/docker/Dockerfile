# Prometheus Slurm exporter image, built locally by the
# prometheus-slurm-exporter role (no registry pull required).
#
# The container bind-mounts the host's Slurm client binaries and libraries,
# so the runtime stage provides a current glibc plus the system libraries
# those binaries link that are not part of the Slurm install prefix.
ARG SLURM_EXPORTER_BASE_IMAGE=ubuntu:24.04

FROM golang:1.24 AS build
ARG SLURM_EXPORTER_VERSION=0.20
# The sed below fixes an upstream parsing bug present through vpenso master:
# the node collector calls sinfo -O without field widths, so node names of
# 20+ characters truncate into the next column and the exporter panics with
# "index out of range". The ": " width suffix disables truncation.
RUN git clone --depth 1 --branch ${SLURM_EXPORTER_VERSION} \
        https://github.com/vpenso/prometheus-slurm-exporter /src \
    && cd /src \
    && sed -i 's/NodeList,AllocMem,Memory,CPUsState,StateLong/NodeList: ,AllocMem: ,Memory: ,CPUsState: ,StateLong: /' node.go \
    && grep -q 'NodeList: ' node.go \
    && CGO_ENABLED=0 go build -o /prometheus-slurm-exporter

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
COPY --from=build /prometheus-slurm-exporter /usr/local/bin/prometheus-slurm-exporter
ENTRYPOINT ["/usr/local/bin/prometheus-slurm-exporter"]
