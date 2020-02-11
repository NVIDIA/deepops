# https://ngc.nvidia.com/catalog/containers/nvidia:pytorch
FROM nvcr.io/nvidia/pytorch:20.01-py3

# Install some extra packages to ease development
RUN apt-get update && \
    apt-get install -y screen unzip git vim htop font-manager && \
    rm -rf /var/lib/apt/*

# Install nodejs, it is a dependency for Jupyter labextensions
RUN conda install nodejs

# Install the NVIDIA Jupyter Dashboard
RUN pip install jupyterlab-nvdashboard && \
    jupyter labextension install jupyterlab-nvdashboard

# Install ipyvolume for clean HTML5 visualizations
RUN pip install ipyvolume && \
    jupyter labextension install ipyvolume

# Install graphviz for clean graph/node/edge rendering
RUN apt-get update && \
    apt-get install -y graphviz && \
    pip install graphviz && \
    rm -rf /var/lib/apt/*

# Expose Jupyter & Tensorboard
EXPOSE 8888
EXPOSE 6006

# /workspace contains NVIDIA tutorials and example code
WORKDIR /workspace

# Start Jupyter up by default rather than a shell
ENTRYPOINT ["/bin/sh"]
CMD ["-c", "jupyter lab  --notebook-dir=/workspace --ip=0.0.0.0 --no-browser --allow-root --port=8888 --NotebookApp.token='' --NotebookApp.password='' --NotebookApp.allow_origin='*' --NotebookApp.base_url=${NB_PREFIX}"]
