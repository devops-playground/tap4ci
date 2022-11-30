# Makefile: make(1) build file.

# Use bash shell
SHELL := /bin/bash

# Load .env file if present (see sample env.default)
ENVFILE := $(shell if [ -r .env ]; then echo 'true'; else echo 'false'; fi)
ifeq ($(ENVFILE),true)
	include .env
	export $(shell sed 's/=.*//' .env | egrep -v '^\#')
endif

# Default task show help
default: help

.PHONY : auto clean clear-flags clobber idempotency info kitchen login logout \
	lxctest pull pull_or_build_if_changed push push_if_changed rebuild-all rmi \
	test test-dind usershell

# Inotify wait time in second for auto tests
AUTO_SLEEP ?= 2

# Adjust Ruby MRI's standard glibc malloc behavior (close to jemalloc)
MALLOC_MAX_ARENA ?= 2

# Test-Kitchen provider
KITCHEN_PROVIDER ?= docker

# Vagrant default provider
VAGRANT_DEFAULT_PROVIDER ?= lxc

# Normal account inside container
DOCKER_USER ?= dev
DOCKER_USER_UID ?= 8888
DOCKER_USER_GID ?= 8888

# Valid subuid user identifier or name for user namespace restriction
DOCKER_USERNS_USER ?= dock-u

# Get Docker info
DOCKER_INFO := $(shell docker info | tr "\n" '|')

# Docker registry settings (credential should be set in environment)
DOCKER_REGISTRY ?= $(shell \
	echo "$(DOCKER_INFO)" \
		| tr '|' "\n" \
		| awk '/^ *Registry: / { print $$2; }' \
	)
DOCKER_REGISTRY_HOST ?= $(shell \
	echo "$(DOCKER_REGISTRY)" \
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

# Define Ruby bundle path inside container
BUNDLE_PATH := ${WORKING_DIR}/.bundle

# Writable stuff inside container
WRITABLE_DIRECTORIES := .bundle .kitchen .kitchen_cache_directory
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
	--build-arg "MAKEFLAGS=-j${NB_PROC}" \
	--build-arg "NB_PROC=${NB_PROC}"

# Docker run environment variables
ENV_VARS = \
	--env 'BUNDLE_DISABLE_SHARED_GEMS=true' \
	--env "BUNDLE_JOBS=${NB_PROC}" \
	--env "BUNDLE_PATH=${BUNDLE_PATH}" \
	--env "KITCHEN_PROVIDER=${KITCHEN_PROVIDER}" \
	--env "MAKEFLAGS=-j${NB_PROC}" \
	--env "MALLOC_MAX_ARENA=${MALLOC_MAX_ARENA}" \
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
	KITCHEN_PROVIDER \
	MAKEFLAGS \
	PROJECT_NAME \
	PROJECT_OWNER \
	TRAVIS \
	TZ \
	VAGRANT_DEFAULT_PROVIDER \
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
		| tr '|' "\n" \
		| awk '/^  ?userns$$/ { print "yes" }' \
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
		-o -n "$$(git diff HEAD~1 -- Dockerfile)" \
		-o -n "$$(git diff origin/master -- .bash_profile)" \
		-o -n "$$(git diff HEAD~1 -- .bash_profile)" \
		-o -n "$$(git diff origin/master -- .ruby-tarball-sha256)" \
		-o -n "$$(git diff HEAD~1 -- .ruby-tarball-sha256)" \
		-o -n "$$(git diff origin/master -- .ruby-version)" \
		-o -n "$$(git diff HEAD~1 -- .ruby-version)"
endef

# Check Docker daemon experimental features (for build squashing)
DOCKERD_EXPERIMENTAL := \
	$(shell docker version --format '{{ .Server.Experimental }}')

BUILD_OPTS :=

ifeq ($(DOCKERD_EXPERIMENTAL),true)
ifeq ($(CURRENT_GIT_BRANCH),master)
	BUILD_OPTS := --squash
endif
endif

# TTY support Docker args
CIRCLECI ?=
GITLAB_CI ?=
TRAVIS ?=

TTY_ARGS :=

ifeq ($(CIRCLECI)$(TRAVIS)$(GITLAB_CI),)
	TTY_ARGS := -t
endif

# Handle specific Ruby release if needed
RUBY_RELEASE := $(shell cat ${PWD}/.ruby-version 2> /dev/null || true)
RUBY_TARBALL_SHA256 := \
	$(shell cat ${PWD}/.ruby-tarball-sha256 2> /dev/null || true)

ifneq ($(RUBY_RELEASE),)
	RUBY_LEVEL := $(shell sed -e 's/\.[0-9]*$$/.0/' ${PWD}/.ruby-version)
	CHRUBY_VERSION ?= 0.3.9
	RUBY_INSTALL_VERSION ?= 0.8.5
	RUBIES_TARBALL_CACHE_BASE_URL ?= http://rubies.free.fr

	RUBY_ROOT := /opt/rubies/ruby-$(RUBY_RELEASE)

	OLD_GEM_ROOT := $(GEM_ROOT)
	OLD_GEM_HOME := $(GEM_HOME)
	OLD_GEM_PATH := $(GEM_PATH)
	OLD_PATH := $(PATH)

	GEM_ROOT := $(RUBY_ROOT)/lib/ruby/gems/$(RUBY_LEVEL)
	GEM_HOME := $(BUNDLE_PATH)/ruby/$(RUBY_LEVEL)
	GEM_PATH := $(GEM_HOME):$(GEM_ROOT)

	RUBY_PATH := $(GEM_HOME)/bin:$(RUBY_ROOT)/bin

	BUNDLER_VERSION := \
		$(strip $(shell tail -n 1 ${PWD}/Gemfile.lock 2> /dev/null || true))

	CHRUBY_BUILD_ARGS := \
		CHRUBY_VERSION \
		BUNDLER_VERSION \
		RUBIES_TARBALL_CACHE_BASE_URL \
		RUBY_INSTALL_VERSION \
		RUBY_LEVEL \
		RUBY_RELEASE \
		RUBY_TARBALL_SHA256

	CHRUBY_ENV_VARS := \
		BUNDLER_VERSION \
		GEM_ROOT \
		GEM_HOME \
		GEM_PATH \
		RUBY_LEVEL \
		RUBY_PATH \
		RUBY_RELEASE
endif

$(foreach v,$(CHRUBY_BUILD_ARGS),$(eval $(call add_to_build_args,$v)))
$(foreach v,$(CHRUBY_ENV_VARS),$(eval $(call add_to_env_vars,$v)))

WATCH := $(shell git ls-files -z | tr "\0" ' ')

ifeq (${UNAME},Darwin)
	inotify_program = fswatch
	make_inotifywait = $(inotify_program) -1 -r $(WATCH)
	notify_ok = terminal-notifier -appIcon file://${PWD}/.complete.png \
		-title "$(PROJECT_NAME) $(1)" -message passed
	notify_fail = terminal-notifier -appIcon file://${PWD}/.reject.png \
		-title "$(PROJECT_NAME) $(1)" -message failed
else
	inotify_program = inotifywait
	make_inotifywait = $(inotify_program) -qq -e close_write -r $(WATCH)
	notify_ok = notify-send -i ${PWD}/.complete.svg "$(PROJECT_NAME) $(1)" passed
	notify_fail = notify-send -i ${PWD}/.reject.svg "$(PROJECT_NAME) $(2)" failed
endif

has_inotify = $(shell [ -n "$$(which $(inotify_program))" ] && echo Ok)

tty_notify_ok = printf "\033[1;49;92m$(PROJECT_NAME) $(1) passed\033[0m\n"
tty_notify_fail = printf "\033[1;49;91m$(PROJECT_NAME) $(1) failed\033[0m\n"

ifeq ($(has_inotify),Ok)
	exec_notify = \
		( $(1) \
			&& $(call tty_notify_ok,"$(2)") && $(call notify_ok,"$(2)") \
			|| ( \
				$(call tty_notify_fail,"$(2)") && $(call notify_fail,"$(2)"); \
				false ) )
else
	exec_notify = \
		( $(1) \
			&& $(call tty_notify_ok,"$(2)") \
			|| ( $(call tty_notify_fail,"$(2)"); false ) )
endif

define make_notify
	$(call exec_notify,$(MAKE) --no-print-directory $(1),"$(2)")
endef

.%.png: .%.svg
	convert -background none -resize 256x256 $< $@

auto: ## Run tests suite continuously on writes
	@+while true; do \
		$(MAKE) --no-print-directory test && \
			echo "⇒ \033[1;49;92mauto test done\033[0m, sleeping $(AUTO_SLEEP)s…"; \
		sleep $(AUTO_SLEEP); \
		$(call make_inotifywait); \
	done

autolxc: ## Run LXC test suite continuously on writes
	@+while true; do \
		GEM_HOME=$(OLD_GEM_HOME) \
		GEM_ROOT=$(OLD_GEM_ROOT) \
		GEM_PATH=$(OLD_GEM_PATH) \
		PATH=$(OLD_PATH) \
		$(MAKE) --no-print-directory lxctest && \
		echo "⇒ \033[1;49;92mauto LXC test done\033[0m, sleeping $(AUTO_SLEEP)s…"; \
		sleep $(AUTO_SLEEP); \
		$(call make_inotifywait); \
	done

define sudo
	cmd="sudo ${1}" && printf "\n\033[31;1m$${cmd}\033[0m\n\n" && $${cmd}
endef

define add_writable_directories_acls
	for dir in ${WRITABLE_DIRECTORIES}; do \
		$(call sudo,setfacl -Rm u:${1}:rwX ${PROJECT_ROOT}/$${dir}) ; \
	done
endef

define add_writable_files_acls
	for file in ${WRITABLE_FILES}; do \
		$(call sudo,setfacl -m u:${1}:rwX ${PROJECT_ROOT}/$${file}) ; \
	done
endef

acl: .acl_build ## Add nested ACLs rights (need sudo)
.acl_build: ${WRITABLE_DIRECTORIES} ${WRITABLE_FILES}
ifeq ($(USERNS),yes)
	$(call sudo,setfacl -m u:$(DOCKER_USERNS_USER):rw /var/run/docker.sock) ; \
	$(call add_writable_directories_acls,$(DOCKER_USERNS_USER))
	$(call add_writable_files_acls,$(DOCKER_USERNS_USER))
	if [ -f $(PROJECT_ROOT)/.env ] ; then \
		$(call sudo,setfacl -m u:$(DOCKER_USERNS_USER):r ${PROJECT_ROOT}/.env) ; \
	fi
else
	for dir in ${WRITABLE_DIRECTORIES}; do \
		chmod a+rwX -R "${PROJECT_ROOT}/$${dir}" 2> /dev/null; \
	done ; \
	for file in ${WRITABLE_FILES}; do \
		chmod a+rw "${PROJECT_ROOT}/$${file}" 2> /dev/null; \
	done
endif
	touch .acl_build

ansible_check: bundle ## Run kitchen converge with Ansible in check mode
	@$(call docker_run,\
		-i $(TTY_ARGS) ${WRITABLE_VOLUMES_ARGS} --env=ANSIBLE_CHECK_MODE=1,\
		bash -l -c "bundle exec kitchen converge")

build: .build ## Build project container
.build: Dockerfile .bash_profile
	DOCKER_BUILDKIT=1 docker build --rm $(BUILD_OPTS) $(BUILD_ARGS) \
		-t $(DOCKER_BUILD_TAG) --cache-from $(DOCKER_BUILD_TAG) .
	touch .build

bundle: .bundle_build ## Run bundle for project
.bundle_build: .bundle Gemfile Gemfile.lock .acl_build .build
	@$(call docker_run,\
		-i $(TTY_ARGS) ${WRITABLE_VOLUMES_ARGS},bash -l -c bundle)
	touch .acl_build
	touch .bundle_build

clean: FLAGS = acl_build bundle_build
clean: clear-flags ## Remove writable directories
	find ${PROJECT_ROOT}/. -type f -name \*~ -delete
	for directory in ${WRITABLE_DIRECTORIES}; do \
		path=${PROJECT_ROOT}/$${directory}; \
		if [ -d $${path} ]; then \
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

dev4osx: ## Prepare for dev. on Osx
	brew tap veelenga/tap
	brew install ameba crystal fswatch imagemagick terminal-notifier

githook: ## Install Git pre-commit hook
	@printf "#!/bin/sh\nset -e\nmake lxctest\nmake test\n" > .git/hooks/pre-commit
	@chmod a+rx .git/hooks/pre-commit

help: ## Show this help
	@printf '\033[32mtargets:\033[0m\n'
	@grep -E '^[a-zA-Z _-]+:.*?## .*$$' $(filter-out .env,$(MAKEFILE_LIST)) \
	| sort \
	| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n",$$1,$$2}'

info: MAKEFLAGS =
info: .build .acl_build ## Show Docker version and user id
	@if [ -n "$(DOCKER_SUDO_S)" ]; then \
		printf "${DOCKER_USER}\n\n" \
		| $(call docker_run,-i $(TTY_ARGS),$(DOCKER_SUDO_S) docker info) ; \
	else \
		$(call docker_run,-i $(TTY_ARGS),$(DOCKER_SUDO_S) docker info) ; \
	fi
	@$(call docker_run,-i $(TTY_ARGS),id)
	@$(call docker_run,-i $(TTY_ARGS),bash -l -c "ruby --version")
	@$(call docker_run,-i $(TTY_ARGS) $(WRITABLE_VOLUMES_ARGS),\
		bash -l -c "bundle --version")

kitchen: bundle ## Run kitchen tests
	@$(call docker_run,-i $(TTY_ARGS) ${WRITABLE_VOLUMES_ARGS},\
		bash -l -c "bundle exec kitchen test")

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
	@+if $(call dockerfile_changed); then \
		$(MAKE) --no-print-directory build; \
	else \
		( $(MAKE) --no-print-directory login \
			&& $(MAKE) --no-print-directory pull ) \
		|| $(MAKE) --no-print-directory build ; \
	fi

push: login .build ## Run 'docker push' with image
	docker tag $(DOCKER_BUILD_TAG) $(DOCKER_REGISTRY_HOST)/$(DOCKER_BUILD_TAG)
	docker push $(DOCKER_REGISTRY_HOST)/$(DOCKER_BUILD_TAG)

pull_then_push_to_latest: login
	@if [ "x${CURRENT_GIT_BRANCH}" != 'xbootstrap' \
		-a "x${CURRENT_GIT_BRANCH}" != 'xmaster' ]; then \
			exit 0 ; \
	fi
	@$(MAKE) --no-print-directory pull
	docker tag "$(DOCKER_REGISTRY_HOST)/${DOCKER_BUILD_TAG}" \
		"${DOCKER_BUILD_TAG_BASE}:latest"
	@DOCKER_BUILD_TAG="${DOCKER_BUILD_TAG_BASE}" $(MAKE) --no-print-directory push

rmi: FLAG = build
rmi: clear-flags ## Remove project container
	-docker rmi -f $(DOCKER_BUILD_TAG)

rebuild-all: MAKEFLAGS =
rebuild-all: ## Clobber all, build and run test
	@$(MAKE) --no-print-directory clobber
	@$(MAKE) --no-print-directory test

test-dind: .build .acl_build ## Run 'docker run hello-world' within image
	@if [ -n "$(DOCKER_SUDO_S)" ]; then \
		printf "${DOCKER_USER}\n\n" \
		| $(call docker_run,\
			-i $(TTY_ARGS),$(DOCKER_SUDO_S) docker run hello-world) ; \
	else \
		$(call docker_run,\
			-i $(TTY_ARGS),$(DOCKER_SUDO_S) docker run hello-world) ; \
	fi

test: MAKEFLAGS =
test: .bundle_build .build .acl_build ## Test (CI)
	@+$(call make_notify,info,'Docker info') && \
	$(call make_notify,test-dind,'Docker-in-Docker') && \
	$(call make_notify,bundle,'Bundle') && \
	$(call make_notify,ansible_check,'Ansible check') && \
	$(call make_notify,kitchen,'Kitchen test')

lxctest: ## Test (CI) with LXC (without Docker-in-Docker)
	@$(call exec_notify,GEM_HOME=$(OLD_GEM_HOME) \
		GEM_PATH=$(OLD_GEM_PATH) \
		GEM_ROOT=$(OLD_GEM_ROOT) \
		PATH=$(OLD_PATH) \
		bundle install,'Bundle') && \
	$(call exec_notify,GEM_HOME=$(OLD_GEM_HOME) \
		ANSIBLE_CHECK_MODE=1 \
		GEM_PATH=$(OLD_GEM_PATH) \
		GEM_ROOT=$(OLD_GEM_ROOT) \
		KITCHEN_PROVIDER=vagrant \
		PATH=$(OLD_PATH) \
		VAGRANT_DEFAULT_PROVIDER=lxc \
		bundle exec kitchen converge,'LXC Ansible check') && \
	$(call exec_notify,GEM_HOME=$(OLD_GEM_HOME) \
		GEM_PATH=$(OLD_GEM_PATH) \
		GEM_ROOT=$(OLD_GEM_ROOT) \
		KITCHEN_PROVIDER=vagrant \
		PATH=$(OLD_PATH) \
		VAGRANT_DEFAULT_PROVIDER=lxc \
		bundle exec kitchen test,'LXC Kitchen test')

usershell: .bundle_build .build .acl_build ## Run user shell
	@$(call docker_run,--env SHELL=/bin/bash $(RC_ENV_VARS) \
		-i $(TTY_ARGS) $(WRITABLE_VOLUMES_ARGS),/bin/bash -l)
