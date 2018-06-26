RUN apt update && \
     apt install -y --no-install-recommends openssh-client sshpass && \
     rm -rf /var/lib/apt/lists/*

RUN mkdir -p /inventory
COPY ansible.docker.cfg /etc/ansible/ansible.cfg

WORKDIR /ansible
COPY . .

ENV PATH=/ansible/docker/bin:$PATH
ENTRYPOINT ["/ansible/docker/entrypoint.sh"]
