PKG=github.com/smallstep/cli/cmd/step
BINNAME=step

# Set V to 1 for verbose output from the Makefile
Q=$(if $V,,@)
SRC = $(shell find . -type f -name '*.go' -not -path "./vendor/*")
PREFIX?=/usr/local
GOOS_OVERRIDE?=

# Set shell to bash for `echo -e`
SHELL:=/bin/bash

all: build lint test

.PHONY: all

#########################################
# Bootstrapping
#########################################

bootstrap:
	$Q which dep || go get github.com/golang/dep/cmd/dep
	$Q dep ensure

vendor: Gopkg.lock
	$Q dep ensure

BOOTSTRAP=\
	github.com/golang/lint/golint \
	github.com/client9/misspell/cmd/misspell \
	github.com/gordonklaus/ineffassign \
	github.com/tsenart/deadcode \
	github.com/alecthomas/gometalinter

define VENDOR_BIN_TMPL
vendor/bin/$(notdir $(1)): vendor
	$Q go build -o $$@ ./vendor/$(1)
VENDOR_BINS += vendor/bin/$(notdir $(1))
endef

$(foreach pkg,$(BOOTSTRAP),$(eval $(call VENDOR_BIN_TMPL,$(pkg))))

.PHONY: bootstrap vendor

#########################################
# Build
#########################################

# Version flags to embed in the binaries
# VERSION := $(shell [ -d .git ] && git describe --tags --always --dirty="-dev")
DATE    := $(shell date -u '+%Y-%m-%d %H:%M UTC')
LDFLAGS := -ldflags='-w -X "main.Version=$(VERSION)" -X "main.BuildTime=$(DATE)"'
GOFLAGS := CGO_ENABLED=0

build: bin/$(BINNAME)
	@echo "Build Complete!"

bin/$(BINNAME): vendor $(call rwildcard,*.go)
	$Q mkdir -p $(@D)
	$Q $(GOOS_OVERRIDE) $(GOFLAGS) go build -i -v -o bin/$(BINNAME) $(LDFLAGS) $(PKG)

# Target for building without calling dep ensure
simple:
	$Q mkdir -p bin/
	$Q $(GOOS_OVERRIDE) $(GOFLAGS) go build -i -v -o bin/$(BINNAME) $(LDFLAGS) $(PKG)
	@echo "Build Complete!"

.PHONY: build simple

#########################################
# Go generate
#########################################

generate:
	$Q go generate ./...

.PHONY: generate

#########################################
# Test
#########################################
test:
	$Q $(GOFLAGS) go test -short -cover ./...

vtest:
	$(Q)for d in $$(go list ./... | grep -v vendor); do \
    echo -e "TESTS FOR: for \033[0;35m$$d\033[0m"; \
    $(GOFLAGS) go test -v -bench=. -run=. -short -coverprofile=profile.coverage.out -covermode=atomic $$d; \
	out=$$?; \
	if [[ $$out -ne 0 ]]; then ret=$$out; fi;\
    rm -f profile.coverage.out; \
	done; exit $$ret;

.PHONY: test vtest

integrate: integration

integration: bin/$(BINNAME)
	$Q $(GOFLAGS) go test -tags=integration ./integration/...

.PHONY: integrate integration

#########################################
# Linting
#########################################

LINTERS=\
	gofmt \
	golint \
	vet \
	misspell \
	ineffassign \
	deadcode

$(patsubst %,%-bin,$(filter-out gofmt vet,$(LINTERS))): %-bin: vendor/bin/%
gofmt-bin vet-bin:

$(LINTERS): %: vendor/bin/gometalinter %-bin vendor
	$Q PATH=`pwd`/vendor/bin:$$PATH gometalinter --tests --disable-all --vendor \
	     --deadline=5m -s data -s pkg --enable $@ ./...
fmt:
	$Q gofmt -l -w $(SRC)

lint: $(LINTERS)

.PHONY: $(LINTERS) lint fmt

#########################################
# Install
#########################################

install: bin/$(BINNAME)
	$Q install -D bin/$(BINNAME) $(DESTDIR)$(PREFIX)/bin/$(BINNAME)

uninstall:
	$Q rm -f $(DESTDIR)$(PREFIX)/bin/$(BINNAME)

.PHONY: install uninstall

#########################################
# Debian
#########################################

debian:
	$Q PREFIX=/usr dpkg-buildpackage -b -rfakeroot -us -uc

distclean: clean

.PHONY: debian distclean

#########################################
# Clean
#########################################

clean:
	@echo "You will need to run 'make bootstrap' or 'dep ensure' directly to re-download any dependencies."
	$Q rm -rf vendor
ifneq ($(BINNAME),"")
	$Q rm -f bin/$(BINNAME)
endif

.PHOMY: clean
