APPS := $(notdir $(wildcard apps/*))

.PHONY: help $(addprefix setup-,$(APPS)) $(addprefix build-,$(APPS)) $(addprefix rm-,$(APPS))

help:
	@echo "Usage:"
	@echo "  make setup-<app>   Full install (build + create + export)"
	@echo "  make build-<app>   Build image only"
	@echo "  make export-<app>  Re-export app to host menu"
	@echo "  make rm-<app>      Remove distrobox"
	@echo ""
	@echo "Available apps: $(APPS)"

setup-%:
	./tools.sh setup $*

build-%:
	./tools.sh build $*

export-%:
	./tools.sh export $*

rm-%:
	./tools.sh rm $*
