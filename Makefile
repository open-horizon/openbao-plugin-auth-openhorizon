SHELL := /bin/bash

# Get Arch for tag and hardware (Golang style) to run test
arch_tag ?= $(shell ./tools/arch-tag)
arch ?= $(arch_tag)

BAO_VERSION ?= 2.2.0
BAO_GPGKEY ?= ""
VAULT_PLUGIN_HASH := ""

EXECUTABLE := openbao-plugin-auth-openhorizon
DOCKER_INAME ?= openhorizon/bao
VERSION ?= 1.0.1
DEV_VERSION ?=testing
DOCKER_IMAGE_LABELS ?= --label "name=bao" --label "version=$(VERSION)" --label "bao_version=$(BAO_VERSION)" --label "release=$(shell git rev-parse --short HEAD)"
DUMB_INIT_VERSION ?= 1.2.5

DOCKER_DEV_OPTS ?= --rm --no-cache --build-arg ARCH=$(arch) --build-arg BAO_VERSION=$(BAO_VERSION) --build-arg BAO_GPGKEY=$(BAO_GPGKEY) --build-arg BAO_PLUGIN_HASH=$(BAO_PLUGIN_HASH) --build-arg DUMB_INIT_VERSION=$(DUMB_INIT_VERSION)

# license file name
export LICENSE_FILE = LICENSE.txt


GOOS ?= linux
GOARCH ?= amd64
CGO_ENABLED ?= 0
COMPILE_ARGS ?= CGO_ENABLED=$(CGO_ENABLED) GOARCH=$(GOARCH) GOOS=$(GOOS)

ifndef verbose
.SILENT:
endif

all: $(EXECUTABLE)
dev:  bao-dev-image
image: bao-image
check: test

clean:
	rm -f /bin/$(EXECUTABLE)
	-@docker rmi $(DOCKER_INAME):$(VERSION) 2> /dev/null || :
	-@docker rmi $(DOCKER_INAME):testing 2> /dev/null || :

.PHONY: format
format:
	@echo "Formatting all Golang source code with gofmt"
	find . -name '*.go' -exec gofmt -l -w {} \;

$(EXECUTABLE): $(shell find . -name '*.go')
	@echo "Producing $(EXECUTABLE) for arch: amd64"
	go mod tidy
	go generate ./...
	$(COMPILE_ARGS) go build -o bin/$(EXECUTABLE) ./cmd/$(EXECUTABLE)

bao-image: VAULT_PLUGIN_HASH=$(shell shasum -a 256 ./docker/bin/$(EXECUTABLE) | awk '{ print $$1 }')

bao-image: $(EXECUTABLE)
	@echo "Handling $(DOCKER_INAME):$(VERSION) with hash $(VAULT_PLUGIN_HASH)"
	if [ -n "$(shell docker images | grep '$(DOCKER_INAME):$(VERSION)')" ]; then \
		echo "Skipping since $(DOCKER_INAME):$(VERSION) image exists, run 'make clean && make' if a rebuild is desired"; \
	elif [[ $(arch) == "amd64" ]]; then \
		echo "Building container image $(DOCKER_INAME):$(VERSION)"; \
		docker build $(DOCKER_DEV_OPTS) $(DOCKER_IMAGE_LABELS) -t $(DOCKER_INAME):$(VERSION) -f docker/Dockerfile.ubi.$(arch) ./docker; \
	else echo "Building the openbao docker image is not supported on $(arch)"; fi

bao-dev-image: $(EXECUTABLE)
	@echo "Handling $(DOCKER_INAME):$(DEV_VERSION)"
	if [ -n "$(shell docker images | grep '$(DOCKER_INAME):$(DEV_VERSION)')" ]; then \
		echo "Skipping since $(DOCKER_INAME):$(DEV_VERSION) image exists, run 'make clean && make' if a rebuild is desired"; \
	elif [[ $(arch) == "amd64" ]]; then \
		echo "Building container image $(DOCKER_INAME):$(DEV_VERSION)"; \
		docker build $(DOCKER_DEV_OPTS)  $(DOCKER_IMAGE_LABELS) -t $(DOCKER_INAME):$(DEV_VERSION) -f docker/Dockerfile.ubi.$(arch) ./docker; \
	else echo "Building the openbap docker image is not supported on $(arch)"; fi

test:
	@echo "Executing unit tests"
	-@$(COMPILE_ARGS) go test -cover -tags=unit

.PHONY: dev-goreleaser
#dev-goreleaser: export GPG_KEY_FILE := /dev/null
dev-goreleaser: export GITHUB_REPOSITORY_OWNER = none
dev-goreleaser: export RELEASE_BUILD_GOOS = linux
dev-goreleaser:
	goreleaser release --clean --timeout=60m --verbose --parallelism 2 --snapshot --skip sbom,sign
