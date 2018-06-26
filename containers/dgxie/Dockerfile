FROM alpine:latest

RUN apk add --no-cache --virtual sl_plus_deps syslinux && \
    cp -r /usr/share/syslinux /tftpboot && \
    find /tftpboot -type f -exec chmod 0444 {} + && \
    apk del sl_plus_deps

# Add safe defaults that can be overriden easily.
COPY pxelinux.cfg /tftpboot/pxelinux.cfg/

# Do not track further change to /tftpboot.
VOLUME /tftpboot

# http://forum.alpinelinux.org/apk/main/x86_64/tftp-hpa
RUN apk add --no-cache tftp-hpa

RUN apk add --no-cache nginx && \
    adduser -D -u 1000 -g 'www' www && \
    mkdir -p /www && \
    chown -R www:www /var/lib/nginx && \
    chown -R www:www /www && \
    mkdir -p /run/nginx

ADD nginx.conf /etc/nginx/nginx.conf

RUN apk add --no-cache vsftpd

RUN echo "local_enable=YES" >> /etc/vsftpd/vsftpd.conf \
#  && echo "chroot_local_user=YES" >> /etc/vsftpd/vsftpd.conf \
#  && echo "write_enable=YES" >> /etc/vsftpd/vsftpd.conf \
#  && echo "local_umask=022" >> /etc/vsftpd/vsftpd.conf \
  && echo "passwd_chroot_enable=yes" >> /etc/vsftpd/vsftpd.conf \
  && echo 'seccomp_sandbox=NO' >> /etc/vsftpd/vsftpd.conf \
  && echo 'pasv_enable=Yes' >> /etc/vsftpd/vsftpd.conf \
  && echo 'pasv_max_port=10100' >> /etc/vsftpd/vsftpd.conf \
  && echo 'pasv_min_port=10090' >> /etc/vsftpd/vsftpd.conf

RUN apk add --no-cache iptables

#RUN apk add --no-cache dhcp && touch /var/lib/dhcp/dhcpd.leases
#ADD dhcpd.conf /etc/dhcp/dhcpd.conf
#VOLUME /etc/dhcp

RUN apk add --no-cache dnsmasq
ADD dnsmasq.conf /etc/dnsmasq.conf
VOLUME /etc/dnsmasq.d

# Set up REST API for grabbing DHCP lease IPs
RUN apk add --no-cache python py-flask
ADD get_hosts.py /usr/local/bin
ADD rest_api.py /usr/local/bin

#EXPOSE 69/udp 80/tcp 20/tcp 21/tcp 10090-10100 67/udp 67/tcp
EXPOSE 69/udp 13370/tcp 20/tcp 21/tcp 10090-10100 67/udp 67/tcp

RUN adduser -D tftp

COPY start /usr/sbin/start
ENTRYPOINT ["/usr/sbin/start"]
#CMD ["-L", "--verbose", "-u", "tftp", "--secure", "/tftpboot"]
