# klassy-deb — build the Klassy KDE Plasma theme as .deb packages for several
# Debian releases, each compiled in its own Docker container.

#==========================================================================================
# Configuration
#==========================================================================================
KLASSY_REPO ?= https://github.com/paulmcauley/klassy
SRC_DIR     ?= src/klassy
DIST_DIR    ?= dist
IMAGE_NAME  ?= klassy-deb

# Extra flags passed to the initial `git clone` (e.g. --filter=blob:none, --depth=1).
CLONE_FLAGS ?=

# Release definitions — RELEASES plus REF_<release>/QT_<release>/IMAGE_<release> —
# live in one file so the Makefile and the CI matrix share a single source of
# truth. Override any value on the CLI, e.g.  make build RELEASE=debian_sid REF_debian_sid=v6.5
include releases.mk

# The release this invocation targets. Override on the CLI:
#   make build RELEASE=debian_sid
RELEASE ?= debian13_trixie
REF     ?= $(REF_$(RELEASE))
QT      ?= $(QT_$(RELEASE))
IMAGE   ?= $(IMAGE_$(RELEASE))

# Debian suite/codename for the .deb version suffix, derived from the release key
# (debian13_trixie -> trixie, debian_sid -> sid). Override with SUITE=... if needed.
SUITE   ?= $(lastword $(subst _, ,$(RELEASE)))

# Debian packaging revision — bump to re-release the SAME klassy version after a
# packaging-only change (deps fix, etc.). The .deb version is <klassy>-<PKGREV>~<suite>.
# Per-release override: set PKGREV_<release> in releases.mk.
PKGREV  ?= $(or $(PKGREV_$(RELEASE)),1)

# Git tag that triggers the publish workflow — release + klassy version, derived
# (never typed by hand), e.g. debian_sid-v6.7.2.
TAG     ?= $(RELEASE)-$(REF)

# Optional package metadata forwarded to the container.
DEB_MAINTAINER ?=

CURDIR_ABS := $(CURDIR)

.DEFAULT_GOAL := help

#==========================================================================================
##@ Source
#==========================================================================================
.PHONY: clone
clone: ## clone klassy into $(SRC_DIR) (idempotent; git-ignored)
	@if [ -d "$(SRC_DIR)/.git" ]; then \
		echo ">> $(SRC_DIR) already present (use 'make update RELEASE=..' to switch ref)"; \
	else \
		echo ">> cloning $(KLASSY_REPO) -> $(SRC_DIR)"; \
		git clone $(CLONE_FLAGS) "$(KLASSY_REPO)" "$(SRC_DIR)"; \
	fi

.PHONY: update
update: check-release clone ## fetch + checkout the ref for RELEASE in $(SRC_DIR)
	@echo ">> $(SRC_DIR): checkout $(REF) (for $(RELEASE))"
	@git -C "$(SRC_DIR)" fetch --tags --force --quiet origin
	@git -C "$(SRC_DIR)" checkout --quiet "$(REF)"
	@git -C "$(SRC_DIR)" submodule update --init --recursive --quiet || true

.PHONY: clean-src
clean-src: ## remove the local klassy clone ($(SRC_DIR))
	@rm -rf "$(SRC_DIR)" && echo ">> removed $(SRC_DIR)"

#==========================================================================================
##@ Build (Docker)
#==========================================================================================
.PHONY: image
image: check-release ## build the builder image for RELEASE
	@echo ">> building image $(IMAGE_NAME):$(RELEASE) (base $(IMAGE))"
	@docker build \
		--build-arg BASE_IMAGE=$(IMAGE) \
		--build-arg RELEASE=$(RELEASE) \
		-t $(IMAGE_NAME):$(RELEASE) \
		-f docker/Dockerfile \
		docker

.PHONY: build
build: update image ## compile klassy in Docker and emit a .deb -> $(DIST_DIR)/RELEASE/
	@mkdir -p "$(DIST_DIR)/$(RELEASE)"
	@echo ">> building klassy .deb for $(RELEASE) (ref $(REF), Qt$(QT), suite $(SUITE), rev $(PKGREV))"
	@docker run --rm \
		-v "$(CURDIR_ABS)/$(SRC_DIR):/src:ro" \
		-v "$(CURDIR_ABS)/$(DIST_DIR)/$(RELEASE):/out" \
		-e QT_MAJOR="$(QT)" \
		-e DEB_SUITE="$(SUITE)" \
		-e PKGREV="$(PKGREV)" \
		-e DEB_MAINTAINER="$(DEB_MAINTAINER)" \
		$(IMAGE_NAME):$(RELEASE)

.PHONY: build-all
build-all: ## build a .deb for every release in $(RELEASES)
	@for r in $(RELEASES); do \
		echo "==================== build $$r ===================="; \
		$(MAKE) --no-print-directory build RELEASE=$$r || exit 1; \
	done

.PHONY: shell
shell: check-release image ## open a shell in the builder image for RELEASE (debugging)
	@docker run --rm -it \
		-v "$(CURDIR_ABS)/$(SRC_DIR):/src:ro" \
		-v "$(CURDIR_ABS)/$(DIST_DIR)/$(RELEASE):/out" \
		-e QT_MAJOR="$(QT)" -e DEB_SUITE="$(SUITE)" \
		--entrypoint /bin/bash \
		$(IMAGE_NAME):$(RELEASE)

#==========================================================================================
##@ Artifacts
#==========================================================================================
.PHONY: list
list: ## list built .deb packages in $(DIST_DIR)
	@find "$(DIST_DIR)" -name '*.deb' -printf '%p\t%s bytes\n' 2>/dev/null | sort || true
	@find "$(DIST_DIR)" -name '*.deb' >/dev/null 2>&1 || echo ">> no packages yet (run 'make build')"

.PHONY: clean
clean: ## remove built packages ($(DIST_DIR))
	@rm -rf "$(DIST_DIR)" && echo ">> removed $(DIST_DIR)"

.PHONY: clean-all
clean-all: clean clean-src ## remove packages and the local clone

#==========================================================================================
##@ Release
#==========================================================================================
.PHONY: tag
tag: check-release ## publish a new release (make tag RELEASE=debian_sid [FORCE=1])
	@if git rev-parse -q --verify "refs/tags/$(TAG)" >/dev/null && [ "$(FORCE)" != "1" ]; then \
		echo ">> tag $(TAG) already exists — bump PKGREV_$(RELEASE) in releases.mk, then re-run with FORCE=1"; \
		exit 1; \
	fi
	@git tag $(if $(filter 1,$(FORCE)),-f,) -a "$(TAG)" -m "Publish klassy $(REF) for $(RELEASE)"
	@git push $(if $(filter 1,$(FORCE)),-f,) origin "$(TAG)"
	@echo ">> $(RELEASE): CI is now building + publishing klassy $(REF) (tag $(TAG))"

#==========================================================================================
##@ CI
#==========================================================================================
.PHONY: ci-build
ci-build: ## build entrypoint used by GitHub Actions (expects RELEASE=..)
	@$(MAKE) --no-print-directory build RELEASE=$(RELEASE)

.PHONY: print-releases
print-releases: ## print $(RELEASES) as a JSON array (feeds the CI matrix)
	@awk 'BEGIN{n=split("$(RELEASES)",a," ");printf "[";for(i=1;i<=n;i++)printf "%s\"%s\"",(i>1?",":""),a[i];print "]"}'

.PHONY: print-ref
print-ref: ## print the klassy ref/tag for RELEASE (used by publish.yml)
	@echo "$(REF)"

#==========================================================================================
# Guards
#==========================================================================================
.PHONY: check-release
check-release:
	@[ -n "$(REF)" ] && [ -n "$(QT)" ] && [ -n "$(IMAGE)" ] || { \
		echo ">> RELEASE '$(RELEASE)' is missing REF/QT/IMAGE in releases.mk."; \
		echo ">> known releases: $(RELEASES)"; \
		exit 1; \
	}
	@[ -f "docker/deps/$(RELEASE).list" ] || { \
		echo ">> missing docker/deps/$(RELEASE).list for RELEASE '$(RELEASE)'"; \
		echo ">> create it (apt build-deps, one per line) then re-run"; \
		exit 1; \
	}

#==========================================================================================
# Help
#==========================================================================================
.PHONY: help
help: ## display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m [RELEASE=<release>]\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
