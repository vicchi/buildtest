SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -O extglob -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

.DEFAULT_GOAL := help
ENVIRONMENT := build
VERSION := $(shell cat ./VERSION)
COMMIT_HASH := $(shell git log -1 --pretty=format:"sha-%h")
ECR_REPO_ROOT := kamma
PLATFORMS := "linux/arm64/v8,linux/amd64"
# PLATFORMS := "linux/amd64"
# PLATFORMS := "linux/arm64/v8"

BUILD_FLAGS ?=
# BUILD_PROGRESS := auto
BUILD_PROGRESS := plain

BUILDTEST := buildtest
BUILDTEST_REPO := $(GITHUB_REGISTRY)/$(GITHUB_USER)
BUILDTEST_IMAGE := $(BUILDTEST)
BUILDTEST_DOCKERFILE := ./docker/$(BUILDTEST)/Dockerfile

DOCKER_BUILDER := buildtest-builder
HADOLINT_IMAGE := hadolint/hadolint

ifndef OP_SERVICE_ACCOUNT_TOKEN
$(error OP_SERVICE_ACCOUNT_TOKEN is not set in your environment)
endif

.PHONY: help
help: ## Show this help message
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' Makefile

.PHONY: setup
setup: dependencies dotenv	## Setup the build environment

.PHONY: dependencies
dependencies:	## Install build dependencies
	uv sync

.PHONY: dotenv
dotenv: .env	## Setup build secrets in .env files

.env: .env.sample
	cp $< $@

# Wrap the build in a check for an existing .env file
ifeq ($(shell test -f .env; echo $$?), 0)
include .env
export $(shell sed -ne '/^\#/d; /./ s/=.*//' .env)

.PHONY: lint
lint: ruff prettify lint-docker	## Run all linters on the code base

.PHONY: ruff
ruff:	## Run ruff lint/check
	ruff check .

.PHONY: prettify
prettify:	## Run ruff format
	ruff format .

.PHONY: lint-docker
lint-docker: lint-dockerfiles ## Lint all Docker related files

.PHONY: lint-dockerfiles
.PHONY: _lint-dockerfiles ## Lint all Dockerfiles
lint-dockerfiles: lint-$(BUILDTEST)-dockerfile

.PHONY: lint-$(BUILDTEST)-dockerfile
lint-$(BUILDTEST)-dockerfile:
	$(MAKE) _lint_dockerfile -e BUILD_DOCKERFILE="$(BUILDTEST_DOCKERFILE)"

.PHONY: bump-patch
bump-patch:	## Bump the patch version number
	bump-my-version bump patch -v

.PHONY: bump-minor
bump-minor:	## Bump the minor version number
	bump-my-version bump minor -v

.PHONY: bump-major
bump-major:	## Bump the major version number
	bump-my-version bump major -v

BUILD_TARGETS := build_buildtest_service

.PHONY: build
build: $(BUILD_TARGETS) ## Build all images

REBUILD_TARGETS := rebuild_buildtest_service

.PHONY: rebuild
rebuild: $(REBUILD_TARGETS) ## Rebuild all images (no cache)

RELEASE_TARGETS := release_buildtest_service

.PHONY: release
release: $(RELEASE_TARGETS)	## Tag and push all images

# buildtest-service targets

build_buildtest_service:	## Build the buildtest_service image
	$(MAKE) _build_image \
		-e BUILD_DOCKERFILE=./docker/$(BUILDTEST)/Dockerfile \
		-e BUILD_REPO=$(BUILDTEST_REPO) \
		-e BUILD_IMAGE=$(BUILDTEST_IMAGE)

rebuild_buildtest_service:	## Rebuild the buildtest_service image (no cache)
	$(MAKE) _build_image \
		-e BUILD_DOCKERFILE=./docker/$(BUILDTEST)/Dockerfile \
		-e BUILD_REPO=$(BUILDTEST_REPO) \
		-e BUILD_IMAGE=$(BUILDTEST_IMAGE) \
		-e BUILD_FLAGS="--no-cache"

release_buildtest_service: build_buildtest_service	## Tag and push buildtest_service image
	$(MAKE) _tag_image \
		-e BUILD_IMAGE=$(BUILDTEST_REPO) \
		-e BUILD_TAG=$(COMMIT_HASH)
	$(MAKE) _tag_image \
		-e BUILD_IMAGE=$(BUILDTEST_REPO) \
		-e BUILD_TAG=$(VERSION)

.PHONY: pull
pull:	## Pull all current Docker images
	docker pull ${BUILD_REPO}/${BUILDTEST_IMAGE}:latest


.PHONY: _lint_dockerfile
_lint_dockerfile:
	docker run --rm -i -e HADOLINT_IGNORE=DL3008 $(HADOLINT_IMAGE) < ${BUILD_DOCKERFILE}

.PHONY: _init_builder
_init_builder:
	docker buildx inspect $(DOCKER_BUILDER) > /dev/null 2>&1 || \
		docker buildx create --name $(DOCKER_BUILDER) --bootstrap --use

.PHONY: _build_image
_build_image: repo_login _init_builder
	docker buildx use $(DOCKER_BUILDER)
	docker buildx build --platform=$(PLATFORMS) \
		--file ${BUILD_DOCKERFILE} \
		--push \
		--tag ${BUILD_REPO}/${BUILD_IMAGE}:latest \
		--provenance=false \
		--progress=$(BUILD_PROGRESS) \
		--ssh default \
		--build-arg VERSION=${VERSION} \
		${BUILD_FLAGS} .

.PHONY: _tag_image
_tag_image: repo_login
	docker buildx imagetools create ${BUILD_REPO}/$(BUILD_IMAGE):latest \
		--tag ${BUILD_REPO}/$(BUILD_IMAGE):$(BUILD_TAG)

.PHONY: repo_login
repo_login:	## Login to GHCR
		echo "${GITHUB_TOKEN}" | docker login ${GITHUB_REGISTRY} -u ${GITHUB_USER} --password-stdin

# No .env file; fail the build
else
.DEFAULT:
	$(error Cannot find a .env file; run "make dotenv" first)
endif
