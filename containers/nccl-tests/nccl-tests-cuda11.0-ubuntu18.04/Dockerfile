FROM ubuntu:18.04 as openmpi
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        file \
        libpmi0-dev \
        libpmi2-0-dev \
        wget \
    && rm -rf /var/lib/apt/lists/*
RUN ln -s /usr/include/slurm-wlm /usr/include/slurm
ENV OPENMPI_VERSION=4.0.3
WORKDIR /root/openmpi
RUN wget -q -O - https://www.open-mpi.org/software/ompi/v$(echo "${OPENMPI_VERSION}" | cut -d . -f 1-2)/downloads/openmpi-${OPENMPI_VERSION}.tar.gz | tar --strip-components=1 -xzf - \
    && ./configure --prefix=/usr/local --disable-getpwuid --with-pmi --with-pmix=internal \
    && make -j"$(nproc)" install >/dev/null

FROM nvidia/cuda:11.0-devel-ubuntu18.04-rc as nccl_tests
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        wget \
    && rm -rf /var/lib/apt/lists/*
COPY --from=openmpi /usr/local /usr/local
#ENV NCCL_TESTS_COMMITISH=cbe7f65400
ENV NCCL_TESTS_COMMITISH=bd0755c95c
WORKDIR /root/nccl_tests
RUN wget -q -O - https://github.com/NVIDIA/nccl-tests/archive/${NCCL_TESTS_COMMITISH}.tar.gz | tar --strip-components=1 -xzf - \
    && make MPI=1

FROM nvidia/cuda:11.0-base-ubuntu18.04-rc
RUN apt-get update && apt-get install -y software-properties-common
RUN add-apt-repository 'deb https://developer.download.nvidia.com/compute/machine-learning/repos/ubuntu1804/x86_64/ /'
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libnccl2 \
        libnccl-dev \
        libnuma1 \
        libpmi0 \
        libpmi2-0 \
        rdma-core \
        librdmacm1 \
        ibverbs-utils \
        libibverbs1 \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*
COPY --from=openmpi /usr/local /usr/local
COPY --from=nccl_tests /root/nccl_tests/build/* /usr/local/bin/
RUN ldconfig

