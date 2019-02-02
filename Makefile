# Makefile: make(1) build file.

# Default task show help
default: help

.PHONY : clean clear-flags clobber idempotency info login logout pull \
	pull_or_build_if_changed push push_if_changed rebuild-all rmi run test \
	test-dind usershell

# Test-Kitchen provider
KITCHEN_PROVIDER ?= docker

# Normal account inside container
DOCKER_USER ?= dev
DOCKER_USER_UID ?= 8888
DOCKER_USER_GID ?= 8888

# Valid subuid group identifier or name for user namespace restriction
DOCKER_USERNS_GROUP ?= dock-g

# Get Docker info
DOCKER_INFO := $(shell docker info | tr "\n" '|')

# Docker registry settings (credential should be set in environment)
DOCKER_REGISTRY ?= $(shell \
	echo "$(DOCKER_INFO)" \
		| tr "\n" '|' \
		| sed -e 's~^.*|Registry: \(https\?://[^|]*\)|.*$$~\1~g' \
	)
DOCKER_REGISTRY_HOST ?= $(shell \
	echo "${DOCKER_REGISTRY}" \
		| sed -e 's|^https\?://||' -e 's|/.*$$||' \
	)
DOCKER_USERNAME ?= dumb
DOCKER_PASSWORD ?=

# Infer project root directory path and set project name if not defined
PROJECT_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
PROJECT_NAME ?= $(notdir $(PROJECT_ROOT))
PROJECT_OWNER ?= ${DOCKER_USERNAME}

# Define working directory inside container
WORKING_DIR ?= /src/${PROJECT_NAME}

# Writable stuff inside container
WRITABLE_DIRECTORIES := .bundle .kitchen
WRITABLE_FILES := Gemfile.lock

# Define Docker build tag to project name if not set
CURRENT_GIT_BRANCH = \
	$(shell basename $$(git symbolic-ref --short HEAD || printf ''))
DOCKER_BUILD_TAG_BASE = ${PROJECT_OWNER}/${PROJECT_NAME}
ifeq ($(CURRENT_GIT_BRANCH),)
	DOCKER_BUILD_TAG ?= ${DOCKER_BUILD_TAG_BASE}
else
	DOCKER_BUILD_TAG ?= ${DOCKER_BUILD_TAG_BASE}:${CURRENT_GIT_BRANCH}
endif

# Retrieve processor count (for Linux and OsX only)
UNAME = $(shell uname)
ifeq ($(UNAME),Darwin)
	NB_PROC ?= $(shell sysctl -n hw.ncpu)
else
	NB_PROC ?= $(shell nproc)
endif

BUNDLE_JOBS ?= ${NB_PROC}

# Docker build arguments
BUILD_ARGS = \
	--build-arg "DOCKER_USER=${DOCKER_USER}" \
	--build-arg "DOCKER_USER_GID=${DOCKER_USER_GID}" \
	--build-arg "DOCKER_USER_UID=${DOCKER_USER_UID}" \
	--build-arg "NB_PROC=${NB_PROC}"

# Docker run environment variables
ENV_VARS = \
	--env 'BUNDLE_DISABLE_SHARED_GEMS=true' \
	--env "BUNDLE_JOBS=${NB_PROC}" \
	--env "BUNDLE_PATH=${WORKING_DIR}/.bundle" \
	--env "KITCHEN_PROVIDER=${KITCHEN_PROVIDER}" \
	--env "MAKEFLAGS=-j ${NB_PROC}" \
	--env container=docker \
	--env LC_ALL=C.UTF-8

# Propagate TERM if defined
ifneq ($(TERM),)
	ENV_VARS += --env "TERM=${TERM}"
endif

# Other overridable build arguments
OVERRIDABLE_BUILD_ARGS := \
	DEB_COMPONENTS \
	DEB_DIST \
	DEB_DOCKER_GPGID \
	DEB_DOCKER_URL \
	DEB_MIRROR_URL \
	DEB_PACKAGES \
	DEB_SECURITY_MIRROR_URL \
	HTTP_PROXY

define add_to_build_args
	ifdef ${1}
		BUILD_ARGS += --build-arg "${1}=$(${1})"
	endif
endef

$(foreach v,$(OVERRIDABLE_BUILD_ARGS),$(eval $(call add_to_build_args,$v)))

# Other overridable environment variables
OVERRIDABLE_ENV_VARS := \
	BUNDLE_JOBS \
	CI \
	CIRCLECI \
	DOCKER_BUILD_TAG \
	DOCKER_PASSWORD \
	DOCKER_REGISTRY \
	DOCKER_USERNAME \
	GITLAB_CI \
	HTTP_PROXY \
	MAKEFLAGS \
	PROJECT_NAME \
	PROJECT_OWNER \
	TRAVIS \
	TZ \
	WORKING_DIR

define add_to_env_vars
	ifdef ${1}
		ENV_VARS += --env "${1}=$(${1})"
	endif
endef

$(foreach v,$(OVERRIDABLE_ENV_VARS),$(eval $(call add_to_env_vars,$v)))

# Normal account args
USER_MODE_ARG := \
	--user ${DOCKER_USER} \
	--env USER=${DOCKER_USER} \
	--env HOME=/home/${DOCKER_USER}

# Check if user namespace is activated
USERNS ?= $(shell \
	echo "$(DOCKER_INFO)" \
		| tr "\n" '|' \
		| sed -e 's/^.*| userns|.*$$/yes/g' \
	)

# Check if user is root
USER_UID := $(shell id -u)

# Set privileged if no user namespace remap and run docker with sudo if not root
DOCKER_SUDO_S :=
ifneq ($(USERNS),yes)
	ifneq ($(USER_UID),0)
		DOCKER_SUDO_S := sudo -S
	endif
	USER_MODE_ARG = --privileged
endif

# Do not mount Docker daemon socket if DOCKER_HOST is set
ifndef (DOCKER_HOST)
	USER_MODE_ARG += --volume /var/run/docker.sock:/var/run/docker.sock:rw
endif

# Add overridable local rc files
LOCAL_RC_FILES ?= \
	.bashrc \
	.gitconfig \
	.inputrc \
	.nanorc \
	.tmux.conf \
	.vimrc

define add_rc_file
	$(eval RC_${1} := $(shell if [ -f "$(HOME)/${1}" ]; then echo Ok; fi))
	ifeq ($(RC_${1}),Ok)
		RC_ENV_VARS += --volume "$(HOME)/${1}:/home/$(DOCKER_USER)/${1}:ro"
	endif
endef

$(foreach f,$(LOCAL_RC_FILES),$(eval $(call add_rc_file,$f)))

# Create writable directories related rules
define build_writable_directory
${1}:
	mkdir $$@
endef

$(foreach d,$(WRITABLE_DIRECTORIES),$(eval $(call build_writable_directory,$d)))

# Create writable files related rules
define touch_writable_file
${1}:
	touch $$@
endef

$(foreach f,$(WRITABLE_FILES),$(eval $(call touch_writable_file,$f)))

WRITABLE_VOLUMES_ARGS := \
	$(foreach p,\
		$(WRITABLE_DIRECTORIES) $(WRITABLE_FILES),\
		--volume ${PROJECT_ROOT}/$p:${WORKING_DIR}/$p:rw\
	)

# Define function to build Docker run command line
define docker_cmd
	${DOCKER_SUDO_S} docker run \
		--hostname ${PROJECT_NAME} \
		--rm \
		--workdir ${WORKING_DIR} \
		--volume ${PROJECT_ROOT}:${WORKING_DIR}:ro \
		${USER_MODE_ARG} \
		${ENV_VARS} \
		${1} \
		${DOCKER_BUILD_TAG} \
		${2}
endef

# Define function to pretty print (without password) and run Docker command line
define docker_run
	( \
		cmd='$(call docker_cmd,${1},${2})' ; \
		cmd=$$(echo $${cmd} | sed -e 's/^[[:space:]]*//g' | tr -d "\t") ; \
		pattern=$(shell printf "${DOCKER_PASSWORD}" | sed -e 's/\//\\/g') ; \
		if [ -n "${DOCKER_PASSWORD}" ]; then \
			printf "\n\033[33;1m$${cmd}\033[0m\n\n" \
			| sed -e "s/$${pattern}/hidden/g" ; \
		else \
			printf "\n\033[33;1m$${cmd}\033[0m\n\n" ; \
		fi ; \
		eval $${cmd} \
	)
endef

# Define function to check if Dockerfile has changed since last commit / master
define dockerfile_changed
	test -n "$$(git diff origin/master -- Dockerfile)" \
		-o -n "$$(git diff HEAD~1 -- Dockerfile)"
endef

# Check Docker daemon experimental features (for build squashing)
DOCKERD_EXPERIMENTAL := \
	$(shell docker version --format '{{ .Server.Experimental }}')

ifeq ($(DOCKERD_EXPERIMENTAL),true)
	BUILD_OPTS := --squash
else
	BUILD_OPTS :=
endif

# Handle specific Ruby release if needed
RUBY_RELEASE := $(shell cat ${PWD}/.ruby-version 2> /dev/null || true)
RUBY_TARBALL_SHA256 := \
	$(shell cat ${PWD}/.ruby-tarball-sha256 2> /dev/null || true)

ifneq ($(RUBY_RELEASE),)
	RUBY_LEVEL := $(shell sed -e 's/\.[0-9]*$$/.0/' ${PWD}/.ruby-version)
	CHRUBY_VERSION ?= 0.3.9
	RUBY_INSTALL_VERSION ?= 0.7.0
	RUBIES_TARBALL_CACHE_BASE_URL ?= http://rubies.free.fr

	RUBY_ROOT := /opt/rubies/ruby-$(RUBY_RELEASE)
	GEM_ROOT := $(RUBY_ROOT)/lib/ruby/gems/$(RUBY_LEVEL)
	GEM_HOME := $(BUNDLE_PATH)/gems
	GEM_PATH := $(GEM_HOME):$(GEM_ROOT)

	PATH := $(GEM_HOME)/bin:$(RUBY_ROOT)/bin:/usr/local/bin:/usr/bin:/bin

	CHRUBY_BUILD_ARGS := \
		CHRUBY_VERSION \
		RUBIES_TARBALL_CACHE_BASE_URL \
		RUBY_INSTALL_VERSION \
		RUBY_LEVEL \
		RUBY_RELEASE \
		RUBY_TARBALL_SHA256

	CHRUBY_ENV_VARS := \
		GEM_ROOT \
		GEM_HOME \
		GEM_PATH \
		PATH \
		RUBY_LEVEL \
		RUBY_RELEASE
endif

$(foreach v,$(CHRUBY_BUILD_ARGS),$(eval $(call add_to_build_args,$v)))
$(foreach v,$(CHRUBY_ENV_VARS),$(eval $(call add_to_env_vars,$v)))

acl: .acl_build ## Add nested ACLs rights (need sudo)
.acl_build: ${WRITABLE_DIRECTORIES} ${WRITABLE_FILES}
	@if [ "$(USERNS)" = 'yes' ]; then \
		cmd='sudo setfacl -Rm g:$(DOCKER_USERNS_GROUP):rwX /var/run/docker.sock' \
			&& printf "\n\033[31;1m$${cmd}\033[0m\n\n" \
			&& $${cmd} ; \
		if [ "$(TMUX_CONF)" = 'Ok' ]; then \
			cmd='sudo setfacl -Rm g:$(DOCKER_USERNS_GROUP):r $(HOME)/.tmux.conf' \
			&& printf "\n\033[31;1m$${cmd}\033[0m\n\n" \
			&& $${cmd} ; \
		fi ; \
	fi
ifeq ($(USERNS),yes)
	for dir in ${WRITABLE_DIRECTORIES}; do \
		args="-Rm g:${DOCKER_USERNS_GROUP}:rwX ${PROJECT_ROOT}/$${dir}" ; \
		printf "\033[31;1msudo setfacl $${args}\033[0m\n" ; \
		sudo setfacl $${args} ; \
	done
	for file in ${WRITABLE_FILES}; do \
		args="-m g:${DOCKER_USERNS_GROUP}:rwX ${PROJECT_ROOT}/$${file}" ; \
		printf "\033[31;1msudo setfacl $${args}\033[0m\n" ; \
		sudo setfacl $${args} ; \
	done
else
	for dir in ${WRITABLE_DIRECTORIES}; do \
		chmod a+rwX -R "${PROJECT_ROOT}/$${dir}" ; \
	done ; \
	for file in ${WRITABLE_FILES}; do \
		chmod a+rw "${PROJECT_ROOT}/$${file}" ; \
	done
endif
	touch .acl_build

build: .build ## Build project container
.build: Dockerfile .bash_profile
	docker build --rm $(BUILD_OPTS) $(BUILD_ARGS) -t $(DOCKER_BUILD_TAG) \
		--cache-from $(DOCKER_BUILD_TAG) .
	touch .build

bundle: .bundle_build ## Run bundle for project
.bundle_build: .bundle Gemfile Gemfile.lock .acl_build .build
	@$(call docker_run,${WRITABLE_VOLUMES_ARGS},bundle)
	touch .acl_build
	touch .bundle_build

clean: FLAGS = acl_build bundle_build
clean: clear-flags ## Remove writable directories
	find ${PROJECT_ROOT}/. -type f -name \*~ -delete
	for directory in ${WRITABLE_DIRECTORIES}; do \
		path=${PROJECT_ROOT}/$${directory}; \
		if [ -f $${path} ]; then \
			rm -rf $${path} 2> /dev/null || ( \
				printf "\033[31;1msudo rm -rf $${directory}\033[0m\n" ; \
				sudo rm -rf $${path} \
			) ; \
		fi ; \
	done

clear-flags:
	if [ -n "$(FLAG)" -a -f "${PROJECT_ROOT}/.$(FLAG)" ]; then \
		rm "${PROJECT_ROOT}/.$(FLAG)"; \
	fi
	if [ -n "$(FLAGS)" ]; then \
		for flag in $(FLAGS); do \
			if [ -f "${PROJECT_ROOT}/.$${flag}" ]; then \
				rm -f "${PROJECT_ROOT}/.$${flag}"; \
			fi ; \
		done ; \
	fi

clobber: FLAG = build
clobber: clean rmi clear-flags ## Do clean, rmi, remove backup (*~) files
	find . -type f -name \*~ -delete

help: ## Show this help
	@printf '\033[32mtargets:\033[0m\n'
	@grep -E '^[a-zA-Z _-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	| sort \
	| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n",$$1,$$2}'

info: MAKEFLAGS =
info: .build .acl_build ## Show Docker version and user id
	@if [ -n "$(DOCKER_SUDO_S)" ]; then \
		printf "${DOCKER_USER}\n\n" \
		| $(call docker_run,--interactive,$(DOCKER_SUDO_S) docker info) ; \
	else \
		$(call docker_run,,$(DOCKER_SUDO_S) docker info) ; \
	fi
	@$(call docker_run,,id)
	@$(call docker_run,,ruby --version)

kitchen: bundle ## Run kitchen tests
	@$(call docker_run,${WRITABLE_VOLUMES_ARGS},bundle exec kitchen test)

login: ## Login to Docker registry
	@echo "login to registry $(DOCKER_USERNAME) @ ${DOCKER_REGISTRY}"
	@docker login \
		--username="$(DOCKER_USERNAME)" \
		--password="$(DOCKER_PASSWORD)" \
		$(DOCKER_REGISTRY) || ( \
			printf "\n\033[31;1mDOCKER_(USERNAME/PASSWORD) must be set\033[0m\n\n" ; \
			exit 2 \
		)

logout: ## Logout from Docker registry
	docker logout $(DOCKER_REGISTRY)

pull: ## Run 'docker pull' with image
	docker pull $(DOCKER_REGISTRY_HOST)/$(DOCKER_BUILD_TAG)
	docker tag $(DOCKER_REGISTRY_HOST)/$(DOCKER_BUILD_TAG) $(DOCKER_BUILD_TAG)
	touch .build

pull_or_build_if_changed:
	+if $(call dockerfile_changed); then \
		make build; \
	else \
		( make login && make pull ) || make build ; \
	fi

push: login .build ## Run 'docker push' with image
	docker tag $(DOCKER_BUILD_TAG) $(DOCKER_REGISTRY_HOST)/$(DOCKER_BUILD_TAG)
	docker push $(DOCKER_REGISTRY_HOST)/$(DOCKER_BUILD_TAG)

pull_then_push_to_latest: login
	@if [ "x${CURRENT_GIT_BRANCH}" != 'xbootstrap' \
		-a "x${CURRENT_GIT_BRANCH}" != 'xmaster' ]; then \
			exit 0 ; \
	fi
	@make --no-print-directory pull
	docker tag "$(DOCKER_REGISTRY_HOST)/${DOCKER_BUILD_TAG}" \
		"${DOCKER_BUILD_TAG_BASE}:latest"
	@DOCKER_BUILD_TAG="${DOCKER_BUILD_TAG_BASE}" make --no-print-directory push

rmi: FLAG = build
rmi: clear-flags ## Remove project container
	-docker rmi -f $(DOCKER_BUILD_TAG)

rebuild-all: MAKEFLAGS =
rebuild-all: ## Clobber all, build and run test
	@make --no-print-directory clobber
	@make --no-print-directory test

test-dind: .build .acl_build ## Run 'docker run hello-world' within image
	@if [ -n "$(DOCKER_SUDO_S)" ]; then \
		printf "${DOCKER_USER}\n\n" \
		| $(call docker_run,-i,$(DOCKER_SUDO_S) docker run hello-world) ; \
	else \
		$(call docker_run,,$(DOCKER_SUDO_S) docker run hello-world) ; \
	fi

test: MAKEFLAGS =
test: .build .acl_build ## Test (CI)
	@make --no-print-directory info
	@make --no-print-directory test-dind
	@make --no-print-directory kitchen

usershell: .build .acl_build ## Run user shell
	@$(call docker_run,-it --env SHELL=/bin/bash $(RC_ENV_VARS),/bin/bash --login)
