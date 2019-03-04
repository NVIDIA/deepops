FROM ubuntu:18.04

RUN apt-get update && apt-get -y install software-properties-common
RUN apt-add-repository -y ppa:ansible/ansible && \
    apt-get update && \
    apt-get -y install ansible
