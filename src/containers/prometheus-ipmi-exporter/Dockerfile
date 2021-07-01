FROM golang:latest AS builder
WORKDIR /go
RUN go get github.com/soundcloud/ipmi_exporter 

FROM ubuntu:20.04
RUN apt-get update \
    && apt-get install freeipmi-tools -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /go/bin/ipmi_exporter /bin/ipmi_exporter
COPY ./config.yml /config.yml

EXPOSE 9290

ENTRYPOINT ["/bin/ipmi_exporter","--config.file=/config.yml"]
