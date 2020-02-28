# https://ngc.nvidia.com/catalog/containers/nvidia:rapidsai:rapidsai
FROM nvcr.io/nvidia/rapidsai/rapidsai:cuda10.1-runtime-ubuntu18.04 

# RAPIDS is installed using conda and we need to work from this environment
ENV CONDA_ENV rapids

# Install some extra packages to ease development
RUN source activate ${CONDA_ENV} && \
    apt-get update && \
    apt-get install -y screen unzip git vim htop font-manager && \
    rm -rf /var/lib/apt/*

# Install the NVIDIA Jupyter Dashboard
RUN source activate ${CONDA_ENV} && \
    conda install -y -c conda-forge jupyterlab-nvdashboard==0.1.11 && conda clean -yac * && \
    jupyter labextension install jupyterlab-nvdashboard

# Install ipyvolume for clean HTML5 visualizations
RUN source activate ${CONDA_ENV} && \
    conda install -y -c conda-forge ipyvolume==0.5.2 && conda clean -yac * && \
    jupyter labextension install ipyvolume

# Install toc to build table of ontents in Jupyter, not available through Conda
RUN source activate ${CONDA_ENV} && \
    jupyter labextension install @jupyterlab/toc

# Install graphviz for clean graph/node/edge rendering
RUN source activate ${CONDA_ENV} && \
    conda install -c conda-forge python-graphviz=0.13.2 graphviz=2.42.3 && conda clean -yac *

# Install dask_kubernetes for deploying works through K8S and monitoring through Jupyter
RUN source activate ${CONDA_ENV} && \
    conda install -c conda-forge dask-kubernetes==0.10.1 && conda clean -yac *

# Expose Jupyter and Dask ports
EXPOSE 8888
EXPOSE 8787

# /rapids contains NVIDIA & contrib tutorials and example code
WORKDIR /rapids

# Start using the built in RAPIDS conda environment
ENTRYPOINT ["/bin/sh"]
CMD ["-c", "/opt/conda/envs/${CONDA_ENV}/bin/jupyter lab  --notebook-dir=/rapids --ip=0.0.0.0 --no-browser --allow-root --port=8888 --NotebookApp.token='' --NotebookApp.password='' --NotebookApp.allow_origin='*' --NotebookApp.base_url=${NB_PREFIX}"]
