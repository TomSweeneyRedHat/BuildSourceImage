pkgname		:= BuildSourceImage
CTR_IMAGE	:= localhost/containers/buildsourceimage
CTR_ENGINE	?= podman
BATS_OPTS	?=
cleanfiles	=
# these are packages whose src.rpms are very small
srpm_urls	= \
	https://archive.kernel.org/centos-vault/7.0.1406/os/Source/SPackages/basesystem-10.0-7.el7.centos.src.rpm \
	https://archive.kernel.org/centos-vault/7.0.1406/os/Source/SPackages/rootfiles-8.1-11.el7.src.rpm \
	https://archive.kernel.org/centos-vault/7.0.1406/os/Source/SPackages/centos-bookmarks-7-1.el7.src.rpm
srpms		= $(addprefix ./.testprep/srpms/,$(notdir $(rpms)))

spec		:= $(pkgname).spec
cwd		:= $(shell dirname $(shell realpath $(spec)))
NAME		= $(pkgname)
ifeq (,$(shell command -v git))
gitcommit	:= HEAD
gitdate		:= $(shell date +%s)
else
gitcommit	:= $(shell git rev-parse --verify HEAD)
gitdate		:= $(shell git log -1 --pretty=format:%ct $(gitcommit))
endif
VERSION		:= 0.2.0
RELEASE		= $(shell rpmspec -q --qf "%{release}" $(spec) 2>/dev/null)
ARCH		= $(shell rpmspec -q --qf "%{arch}" $(spec) 2>/dev/null)
NVR		= $(NAME)-$(VERSION)-$(RELEASE)
outdir		?= $(cwd)

SHELL_SRC		:= ./BuildSourceImage.sh
DIST_FILES		:= \
	$(SHELL_SRC) \
	LICENSE \
	layout.md \
	README.md

export CTR_IMAGE
export CTR_ENGINE

all: validate

validate: .validate

cleanfiles += .validate
.validate: $(SHELL_SRC)
	shellcheck $(SHELL_SRC) && touch $@

build-container: .build-container

cleanfiles += .build-container
.build-container: .validate Dockerfile $(SHELL_SRC)
	@echo
	@echo "==> Building BuildSourceImage Container"
	$(CTR_ENGINE) build --quiet --file Dockerfile --tag $(CTR_IMAGE) . && touch $@

cleanfiles += .testprep $(srpms)
.testprep:
	@echo "==> Fetching SRPMs for testing against"
	mkdir -p $@/{srpms,tmp}
	wget -P $@/srpms/ $(srpm_urls)

.PHONY: test-integration
test-integration: .build-container .testprep
	@echo
	@echo "==> Running integration tests"
	TMPDIR=$(realpath .testprep/tmp) bats $(BATS_OPTS) test/

.PHONY: srpm
srpm: $(NVR).src.rpm
	@echo $^

.PHONY: $(spec)
cleanfiles += $(spec)
$(spec): $(spec).in
	sed \
		's/MYVERSION/$(VERSION)/g; s/GITCOMMIT/$(gitcommit)/g; s/TIMESTAMP/$(gitdate)/g' \
		$(spec).in > $(spec)

cleanfiles += $(NVR).src.rpm
$(NVR).src.rpm: $(spec) $(DIST_FILES)
	rpmbuild \
                --define '_sourcedir $(cwd)' \
                --define '_specdir $(cwd)' \
                --define '_builddir $(cwd)' \
                --define '_srcrpmdir $(outdir)' \
                --define '_rpmdir $(outdir)' \
                --nodeps \
                -bs $(spec)

.PHONY: rpm
rpm: $(ARCH)/$(NVR).$(ARCH).rpm
	@echo $^

cleanfiles += $(ARCH)/$(NVR).$(ARCH).rpm
$(ARCH)/$(NVR).$(ARCH).rpm: $(spec) $(DIST_FILES)
	rpmbuild \
                --define '_sourcedir $(cwd)' \
                --define '_specdir $(cwd)' \
                --define '_builddir $(cwd)' \
                --define '_srcrpmdir $(outdir)' \
                --define '_rpmdir $(outdir)' \
                -bb ./$(spec)

clean:
	if [ -n "$(cleanfiles)" ] ; then rm -rf $(cleanfiles) ; fi
