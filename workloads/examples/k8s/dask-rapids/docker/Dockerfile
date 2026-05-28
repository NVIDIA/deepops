# Base the example on the current RAPIDS notebooks image from NGC.
FROM nvcr.io/nvidia/rapidsai/notebooks:26.04-cuda12-py3.13

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends font-manager && \
    rm -rf /var/lib/apt/lists/*

USER rapids

# Copy the parallel sum notebook in
COPY --chown=rapids:conda ParallelSum.ipynb /home/rapids/notebooks/ParallelSum.ipynb
