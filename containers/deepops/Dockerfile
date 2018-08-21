RUN pip install --upgrade pip

RUN apt update && apt install -y --no-install-recommends git curl tar vim-tiny make sudo openssh-client sshpass lolcat && \
    rm -rf /var/cache/apt/*

ENV DOCKER_CHANNEL stable
ENV DOCKER_VERSION 17.12.0-ce
RUN if ! curl -fL -o docker.tgz "https://download.docker.com/linux/static/${DOCKER_CHANNEL}/x86_64/docker-${DOCKER_VERSION}.tgz"; then \
        echo >&2 "error: failed to download 'docker-${DOCKER_VERSION}' from '${DOCKER_CHANNEL}'"; \
        exit 1; \
    fi; \
    \
    tar --extract \
        --file docker.tgz \
        --strip-components 1 \
        --directory /usr/local/bin/ \
    ; \
    rm docker.tgz

COPY ./requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt && rm /tmp/requirements.txt

WORKDIR /source
RUN git clone --recursive https://github.com/NVIDIA/deepops.git && \
    cd deepops && \
    git checkout ${DEEPOPS_VERSION} && \
    ansible-galaxy install -r requirements.yml

ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

WORKDIR /source/nvidia_deepops
COPY python .
RUN python setup.py install && \
	mkdir -p /data

RUN mkdir -p /inventory
WORKDIR /scripts
COPY docker .

ENV DEEPOPS_SOURCE_ANSIBLE=/source/deepops/ansible

WORKDIR /source/deepops

ENV PATH=/scripts/bin:/usr/games:$PATH
ENTRYPOINT ["/scripts/entrypoint.sh"]
