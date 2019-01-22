BASE_IMAGE ?= python:3.6-slim
IMAGE_NAME ?= deepops_deploy
RELEASE_IMAGE ?= deepops/deploy
RELEASE_VERSION = '0.1.6'
DEEPOPS_VERSION ?= dev
#HELM_VERSION ?= 2.10.0
HELM_VERSION ?= 2.9.1

APT_PROXY ?= "false"
APT_CACHE="RUN echo 'Acquire::HTTP::Proxy \"${APT_PROXY}\";' >> /etc/apt/apt.conf.d/01proxy"
ifdef PYPI_PROXY
PYPI_CACHE="RUN mkdir -p ~/.pip && echo [global] > ~/.pip/pip.conf && echo trusted-host = ${PYPI_PROXY} >> ~/.pip/pip.conf && echo index-url = http://${PYPI_PROXY}:3141/root/pypi/+simple/ >> ~/.pip/pip.conf"
else
PYPI_CACHE=""
endif

.PHONY: build tag push release clean distclean

default: clean build

build: Dockerfile
	@echo FROM ${BASE_IMAGE} > .Dockerfile
	@echo ${APT_CACHE} >> .Dockerfile
	@echo ${PYPI_CACHE} >> .Dockerfile
	@echo ENV DEEPOPS_VERSION=${DEEPOPS_VERSION} >> .Dockerfile
	@echo ENV HELM_VERSION=${HELM_VERSION} >> .Dockerfile
	@cat Dockerfile >> .Dockerfile
	@echo "RUN rm -f /etc/apt/apt.conf.d/01proxy" >> .Dockerfile
	@echo "RUN rm -rf ~/.pip" >> .Dockerfile
	docker build -t ${IMAGE_NAME} -f .Dockerfile .

tag: build
	docker tag ${IMAGE_NAME} ${RELEASE_IMAGE}:${RELEASE_VERSION}
	docker tag ${IMAGE_NAME} ${RELEASE_IMAGE}:latest

push: tag
	docker push ${RELEASE_IMAGE}:${RELEASE_VERSION}
	docker push ${RELEASE_IMAGE}:latest

release: push

clean:
	@rm -f .Dockerfile 2> /dev/null ||:
	@docker rm -v `docker ps -a -q -f "status=exited"` 2> /dev/null ||:
	@docker rmi `docker images -q -f "dangling=true"` 2> /dev/null ||:

distclean: clean
	@docker rmi ${BASE_IMAGE} 2> /dev/null ||:
	@docker rmi ${IMAGE_NAME} 2> /dev/null ||:
	@docker rmi ${RELEASE_IMAGE} 2> /dev/null ||:

