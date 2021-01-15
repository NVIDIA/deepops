#!/bin/bash -e
for dir in `ls -d */ | sed 's:/::g'`; do
  cd ${dir}

  echo "Building deepops-${dir}-minimal"
  docker build -t deepops-${dir}-minimal -f Dockerfile-minimal .
  docker tag deepops-${dir}-minimal deepops-${dir}-minimal:kubeflow

  if [ "${1}" != "minimal" ]; then
    echo "Building deepops-${dir}"
    docker build -t deepops-${dir} -f Dockerfile .
    docker tag deepops-${dir} deepops-${dir}:kubeflow
  fi

 cd -
done
