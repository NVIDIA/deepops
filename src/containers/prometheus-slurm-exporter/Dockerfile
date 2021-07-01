FROM golang:latest AS builder
WORKDIR /go
RUN go get github.com/vpenso/prometheus-slurm-exporter 

FROM ubuntu:20.04
RUN apt-get update \
    && apt-get install munge -y --no-install-recommends \
    && useradd -M slurm \
    && echo /usr/lib/slurm >> /etc/ld.so.conf \
    && ldconfig \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /go/bin/prometheus-slurm-exporter /bin/prometheus-slurm-exporter

ENV LD_LIBRARY_PATH /usr/lib/slurm

EXPOSE 8080

ENTRYPOINT ["/bin/prometheus-slurm-exporter"]
