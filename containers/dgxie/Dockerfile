FROM golang:1.10.2

ENV COMMIT_HASH 27896bc470a2044c714101b2a321d6d900ccecbe
ENV CUSTOM_FORK_AUTHOR hightoxicity
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

FROM ubuntu:16.04
MAINTAINER Douglas Holt <dholt@nvidia.com>

RUN apt-get update && \
    apt-get -y install apt-transport-https curl && \
    apt-get -y install nginx vsftpd iptables dnsmasq python-flask
COPY --from=0 /bin/pixiecore /usr/bin/pixiecore
RUN chmod +x /usr/bin/pixiecore

RUN mkdir -p /www /var/run/vsftpd/empty
    # && \
    #echo "local_enable=YES" >> /etc/vsftpd.conf && \
    #echo "passwd_chroot_enable=yes" >> /etc/vsftpd.conf && \
    #echo 'seccomp_sandbox=NO' >> /etc/vsftpd.conf && \
    #echo 'pasv_enable=Yes' >> /etc/vsftpd.conf && \
    #echo 'pasv_max_port=10100' >> /etc/vsftpd.conf && \
    #echo 'pasv_min_port=10090' >> /etc/vsftpd.conf

COPY get_hosts.py /usr/local/bin
COPY rest_api.py /usr/local/bin
COPY api.py /api.py
COPY nginx.conf /etc/nginx/nginx.conf
COPY start /usr/sbin/start
COPY dnsmasq.conf /etc/dnsmasq.conf
COPY vsftpd.conf /etc/vsftpd.conf

VOLUME /etc/dnsmasq.d

ENTRYPOINT ["/bin/bash"]
CMD ["/usr/sbin/start"]
