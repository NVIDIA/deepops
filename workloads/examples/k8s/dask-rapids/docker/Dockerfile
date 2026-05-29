# Base the example on the current RAPIDS notebooks image from NGC.
FROM nvcr.io/nvidia/rapidsai/notebooks:26.04-cuda12-py3.13

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends font-manager && \
    mkdir -p /opt/rapids/notebooks && \
    chown -R rapids:conda /opt/rapids && \
    rm -rf /var/lib/apt/lists/*

USER rapids
WORKDIR /opt/rapids/notebooks

# Copy the parallel sum notebook in
COPY --chown=rapids:conda ParallelSum.ipynb ./ParallelSum.ipynb
