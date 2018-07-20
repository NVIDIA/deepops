FROM ubuntu:16.04

MAINTAINER Douglas Holt <dholt@nvidia.com>

RUN apt-get update && \
    apt-get -y install apt-transport-https curl && \
    curl -L https://packagecloud.io/danderson/pixiecore/gpgkey | apt-key add - && \
    echo "deb https://packagecloud.io/danderson/pixiecore/debian stretch main" >/etc/apt/sources.list.d/pixiecore.list && \
    apt-get update && \
    apt-get -y install pixiecore nginx vsftpd iptables dnsmasq python-flask

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
