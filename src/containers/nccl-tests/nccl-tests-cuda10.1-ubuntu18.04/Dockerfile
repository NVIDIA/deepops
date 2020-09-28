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
ENV OPENMPI_VERSION=3.1.4
WORKDIR /root/openmpi
RUN wget -q -O - https://www.open-mpi.org/software/ompi/v$(echo "${OPENMPI_VERSION}" | cut -d . -f 1-2)/downloads/openmpi-${OPENMPI_VERSION}.tar.gz | tar --strip-components=1 -xzf - \
    && ./configure --prefix=/usr/local --disable-getpwuid --with-pmi --with-pmix=internal \
    && make -j"$(nproc)" install >/dev/null

FROM nvidia/cuda:10.1-devel-ubuntu18.04 as nccl_tests
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        wget \
    && rm -rf /var/lib/apt/lists/*
COPY --from=openmpi /usr/local /usr/local
ENV NCCL_TESTS_COMMITISH=cbe7f65400
WORKDIR /root/nccl_tests
RUN wget -q -O - https://github.com/NVIDIA/nccl-tests/archive/${NCCL_TESTS_COMMITISH}.tar.gz | tar --strip-components=1 -xzf - \
    && make MPI=1

FROM nvidia/cuda:10.1-base-ubuntu18.04
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libnccl2 \
        libnuma1 \
        libpmi0 \
        libpmi2-0 \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*
COPY --from=openmpi /usr/local /usr/local
COPY --from=nccl_tests /root/nccl_tests/build/* /usr/local/bin/
RUN ldconfig
