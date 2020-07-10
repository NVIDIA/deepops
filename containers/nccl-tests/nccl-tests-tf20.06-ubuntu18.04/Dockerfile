FROM nvcr.io/nvidia/tensorflow:20.06-tf2-py3 as nccl_tests
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        wget \
    && rm -rf /var/lib/apt/lists/*
ENV NCCL_TESTS_COMMITISH=bd0755c95c
WORKDIR /root/nccl_tests
RUN wget -q -O - https://github.com/NVIDIA/nccl-tests/archive/${NCCL_TESTS_COMMITISH}.tar.gz | tar --strip-components=1 -xzf - \
    && make MPI=1 MPI_HOME=/usr/local/mpi

FROM nvcr.io/nvidia/tensorflow:20.06-tf2-py3
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*
COPY --from=nccl_tests /root/nccl_tests/build/* /usr/local/bin/
RUN ldconfig

