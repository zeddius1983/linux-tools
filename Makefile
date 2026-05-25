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
	./manage.sh setup $*

build-%:
	./manage.sh build $*

export-%:
	./manage.sh export $*

rm-%:
	./manage.sh rm $*
