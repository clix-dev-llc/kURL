.PHONY: clean deps code
SHELL := /bin/bash

include Manifest

clean:
	rm -rf build tmp dist

deps:
	go get github.com/linuxkit/linuxkit/src/cmd/linuxkit
	go get github.com/linuxkit/kubernetes || :

code: build/Manifest build/scripts build/yaml

build: code build/ubuntu-16.04 build/ubuntu-18.04 build/rhel-7

build/ubuntu-16.04: code build/ubuntu-16.04/packages/docker build/ubuntu-16.04/packages/k8s

build/ubuntu-18.04: code build/ubuntu-18.04/packages/docker build/ubuntu-18.04/packages/k8s

build/rhel-7: code build/rhel-7/packages/docker build/rhel-7/packages/k8s

build/ubuntu-16.04/packages/docker:
	docker build \
		--build-arg DOCKER_VERSION=${DOCKER_VERSION} \
		-t aka/ubuntu-1604-docker:${DOCKER_VERSION} \
		-f bundles/docker-ubuntu1604/Dockerfile \
		bundles/docker-ubuntu1604
	source Manifest && docker run --rm \
		-v ${PWD}/build/ubuntu-16.04/packages/docker:/out \
		aka/ubuntu-1604-docker:${DOCKER_VERSION}

build/ubuntu-18.04/packages/docker:
	docker build \
		--build-arg DOCKER_VERSION=${DOCKER_VERSION} \
		-t aka/ubuntu-1804-docker:${DOCKER_VERSION} \
		-f bundles/docker-ubuntu1804/Dockerfile \
		bundles/docker-ubuntu1804
	docker run --rm \
		-v ${PWD}/build/ubuntu-18.04/packages/docker:/out \
		aka/ubuntu-1804-docker:${DOCKER_VERSION}

build/rhel-7/packages/docker:
	docker build \
		--build-arg DOCKER_VERSION=${DOCKER_VERSION} \
		-t aka/rhel-7-docker:${DOCKER_VERSION} \
		-f bundles/docker-rhel7/Dockerfile \
		bundles/docker-rhel7
	docker run --rm \
		-v ${PWD}/build/rhel-7/packages/docker:/out \
		aka/rhel-7-docker:${DOCKER_VERSION} \

build/ubuntu-16.04/packages/k8s:
	docker build \
		--build-arg KUBERNETES_VERSION=${KUBERNETES_VERSION} \
		-t aka/ubuntu-1604-k8s:${KUBERNETES_VERSION} \
		-f bundles/k8s-ubuntu1604/Dockerfile \
		bundles/k8s-ubuntu1604
	docker run --rm \
		-v ${PWD}/build/ubuntu-16.04/packages/k8s:/out \
		aka/ubuntu-1604-k8s:${KUBERNETES_VERSION}

build/ubuntu-18.04/packages/k8s:
	docker build \
		--build-arg KUBERNETES_VERSION=${KUBERNETES_VERSION} \
		-t aka/ubuntu-1804-k8s:${KUBERNETES_VERSION} \
		-f bundles/k8s-ubuntu1804/Dockerfile \
		bundles/k8s-ubuntu1804
	docker run --rm \
		-v ${PWD}/build/ubuntu-18.04/packages/k8s:/out \
		aka/ubuntu-1804-k8s:${KUBERNETES_VERSION}

build/rhel-7/packages/k8s:
	docker build \
		--build-arg KUBERNETES_VERSION=${KUBERNETES_VERSION} \
		-t aka/rhel-7-k8s:${KUBERNETES_VERSION} \
		-f bundles/k8s-rhel7/Dockerfile \
		bundles/k8s-rhel7
	docker run --rm \
		-v ${PWD}/build/rhel-7/packages/k8s:/out \
		aka/rhel-7-k8s:${KUBERNETES_VERSION}

tmp/kubernetes/pkg/kubernetes-docker-image-cache-common/images.lst:
	mkdir -p tmp/kubernetes
	# CircleCI GOPATH is two paths separated by :
	cp -r $(shell echo ${GOPATH} | cut -d ':' -f 1)/src/github.com/linuxkit/kubernetes/pkg ./tmp/kubernetes/
	cp -r $(shell echo ${GOPATH} | cut -d ':' -f 1)/src/github.com/linuxkit/kubernetes/.git ./tmp/kubernetes/
	rm tmp/kubernetes/pkg/kubernetes-docker-image-cache-common/images.lst
	KUBERNETES_VERSION=1.15.1 PAUSE_VERSION=3.1 ETCD_VERSION=3.3.10 COREDNS_VERSION=1.3.1 WEAVE_VERSION=2.5.2 ROOK_VERSION=1.0.4 CEPH_VERSION=14.2.0-20190410 CONTOUR_VERSION=0.14.0 ENVOY_VERSION=1.10.0 ./bundles/k8s-containers/mk-image-cache-lst common > tmp/kubernetes/pkg/kubernetes-docker-image-cache-common/images.lst

build/k8s-images.tar: tmp/kubernetes/pkg/kubernetes-docker-image-cache-common/images.lst
	mkdir -p build
	$(eval k8s_images_image = $(shell linuxkit pkg build ./tmp/kubernetes/pkg/kubernetes-docker-image-cache-common | grep 'Tagging linuxkit/kubernetes-docker-image-cache' | awk '{print $$2}'))
	echo ${k8s_images_image}
	docker tag ${k8s_images_image} quay.io/replicated/k8s-images
	docker save quay.io/replicated/k8s-images > build/k8s-images.tar

build/Manifest:
	mkdir -p build
	cp Manifest build/

build/scripts:
	mkdir -p build
	cp -r scripts build/

build/yaml:
	mkdir -p build
	cp -r yaml build/

dist/aka.tar.gz: build
	mkdir -p dist
	tar cf dist/aka.tar -C build .
	gzip dist/aka.tar

dist/aka-ubuntu-1604.tar.gz: clean build/ubuntu-16.04
	mkdir -p dist
	tar cf dist/aka-ubuntu-1604.tar -C build .
	gzip dist/aka-ubuntu-1604.tar -C build .

dist/aka-ubuntu-1804.tar.gz: clean build/ubuntu-18.04
	mkdir -p dist
	tar cf dist/aka-ubuntu-1804.tar -C build .
	gzip dist/aka-ubuntu-1804.tar

dist/aka-rhel-7.tar.gz: clean build/rhel-7
	mkdir -p dist
	tar cf dist/aka-rhel7.tar -C build .
	gzip dist/aka-rhel7.tar

watchrsync:
	rsync -r build/ ${USER}@${HOST}:aka
	bin/watchrsync.js
