FROM golang:1.10.2

ENV COMMIT_HASH 03425a0d6ae36852d5ea7b446571bbcd3829d717
ENV CUSTOM_FORK_AUTHOR deepops
RUN apt-get update
RUN apt-get install -qy --no-install-recommends wget git
RUN [ -d ${GOPATH}/bin ] || mkdir ${GOPATH}/bin
RUN go get -u github.com/golang/dep/cmd/dep
RUN mkdir -p ${GOPATH}/src/go.universe.tf
WORKDIR /go/src/go.universe.tf
RUN git clone https://github.com/google/netboot.git
WORKDIR /go/src/go.universe.tf/netboot
RUN git remote add ${CUSTOM_FORK_AUTHOR} https://github.com/${CUSTOM_FORK_AUTHOR}/netboot.git && git fetch ${CUSTOM_FORK_AUTHOR} && git checkout ${COMMIT_HASH}
RUN dep ensure
RUN ls -al ./vendor
WORKDIR /go/src
RUN CGO_ENABLED=0 GOOS=linux go build -o /bin/pixiecore -ldflags "-w -s -v -extldflags -static" go.universe.tf/netboot/cmd/pixiecore

FROM alpine:3.6
MAINTAINER Douglas Holt <dholt@nvidia.com>

RUN apk add --no-cache ca-certificates
COPY --from=0 /bin/pixiecore /usr/bin/pixiecore
RUN chmod +x /usr/bin/pixiecore

ENTRYPOINT ["/usr/bin/pixiecore"]
