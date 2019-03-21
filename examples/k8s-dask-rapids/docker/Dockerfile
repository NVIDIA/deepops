# Base our new image on the CUDA 9.2 RAPIDS image from upstream
FROM nvcr.io/nvidia/rapidsai/rapidsai:cuda9.2-runtime-ubuntu16.04

# Fix font-manager package
RUN apt-get update && \
    apt-get install -y --fix-missing font-manager && \
    rm -rf /var/lib/apt/lists/*

# The name of the Anaconda Python environment we'll use (from upstream)
ENV CONDA_ENV rapids

# Install additional Python packages into the environment
# (If you want to install more packages, add them here!)
RUN source activate $CONDA_ENV && \
    conda install -y unzip python-graphviz && \
    pip install ipyvolume dask-kubernetes matplotlib cupy-cuda92

# Copy the parallel sum notebook in
COPY ParallelSum.ipynb /rapids/notebooks/ParallelSum.ipynb

# Set up image to be run
COPY prepare.sh /usr/bin/prepare.sh
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--allow-root", "--no-browser", "--NotebookApp.token='dask'"]
ENTRYPOINT ["tini", "--", "/usr/bin/prepare.sh"]
