.PHONY: help lint build

# Use bash for inline if-statements in arch_patch target
SHELL:=bash

# Enable BuildKit for Docker build
export DOCKER_BUILDKIT:=1
export COMPOSE_DOCKER_CLI_BUILD:=1
export BUILDKIT_PROGRESS:=plain

# https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help:
	@$(MAKE) -pRrq -f $(lastword $(MAKEFILE_LIST)) : 2>/dev/null | awk -v RS= -F: '/^# Fichiers/,/^# Base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | egrep -v -e '^[^[:alnum:]]' -e '^$@$$'

lint: ## stop all containers
	@echo "lint dockerfile ..."
	docker run -i --rm hadolint/hadolint < Dockerfile

build: ## build image
	@echo "build image ..."
	docker buildx use default
	docker compose build

run:
	docker-compose up

check:
	@echo "makemkv version :"$((curl -s "http://www.makemkv.com/download/" | grep -Eom1 "MakeMKV [0-9].[0-9]+\.[0-9]+" | sed 's/MakeMKV //'))
	@echo "libevent: "