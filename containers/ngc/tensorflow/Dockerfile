# https://ngc.nvidia.com/catalog/containers/nvidia:tensorflow
FROM nvcr.io/nvidia/tensorflow:20.01-tf1-py3

# Install some extra packages to ease development
RUN apt-get update && \
    apt-get install -y screen unzip git vim htop font-manager && \
    rm -rf /var/lib/apt/*

# Install nodejs and npm, which are dependencies for labextensions
RUN apt-get update && \
    apt-get install -y nodejs=8.10.0~dfsg-2ubuntu0.4 \
                       npm=3.5.2-0ubuntu4 && \
    rm -rf /var/lib/apt/*

# Cleanup old python2 install that interferes with pip
RUN rm /usr/bin/python && \
    ln -s $(which python3) /usr/bin/python

# Install the NVIDIA Jupyter Dashboard
RUN  pip install jupyterlab-nvdashboard==0.2.0 && \
     jupyter labextension install jupyterlab-nvdashboard

# Install ipyvolume for clean HTML5 visualizations
RUN pip install ipyvolume==0.5.2 && \
    jupyter labextension install ipyvolume

# Install toc to build table of ontents in Jupyter, not available through Conda
RUN jupyter labextension install @jupyterlab/toc

# Install graphviz for clean graph/node/edge rendering
RUN apt-get update && \
    apt-get install -s graphviz=2.40.1-2 && \
    pip install graphviz==0.13.2 && \
    rm -rf /var/lib/apt/*

# Expose Jupyter & Tensorboard
EXPOSE 8888
EXPOSE 6006

# /workspace contains NVIDIA tutorials and example code
WORKDIR /workspace

# Start Jupyter up by default rather than a shell
ENTRYPOINT ["/bin/sh"]
CMD ["-c", "jupyter lab  --notebook-dir=/workspace --ip=0.0.0.0 --no-browser --allow-root --port=8888 --NotebookApp.token='' --NotebookApp.password='' --NotebookApp.allow_origin='*' --NotebookApp.base_url=${NB_PREFIX}"]
