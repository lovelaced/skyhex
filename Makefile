# Skyhex dev loop. `make help` lists targets.

LUAJIT   ?= $(shell command -v luajit 2>/dev/null || echo /opt/homebrew/bin/luajit)
LUACHECK ?= $(shell command -v luacheck 2>/dev/null || echo $(HOME)/.luarocks/bin/luacheck)
T        ?=
WOW_DIR  ?= /Applications/World of Warcraft/_forever_
ADDON_DST = $(WOW_DIR)/Interface/AddOns/Skyhex/
VERSION  ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
RELEASE   = .release

.PHONY: help test fuzz boot lint check media icon render snap deploy package clean

help:
	@echo "make test      engine specs (T=pattern), includes a short fuzz"
	@echo "make fuzz      long fuzz: 40 runs per start level"
	@echo "make boot      boot the addon in the perl-infinity harness and walk the real flows"
	@echo "make lint      luacheck"
	@echo "make check     test + boot + lint"
	@echo "make media     regenerate Skyhex/Media/*.tga"
	@echo "make icon      rebuild assets/logo.png and Skyhex/Media/Icon.tga from the game's gem art"
	@echo "make render    rule scenario PNGs in tools/out/render"
	@echo "make snap      window mockups in tools/out/snap, with icon art from the local Forever install"
	@echo "make deploy    copy Skyhex/ into the WoW: Forever AddOns folder"
	@echo "make package   zip Skyhex/ to $(RELEASE)/Skyhex-<version>.zip"

test:
	$(LUAJIT) tests/run.lua $(T)

fuzz:
	SKYHEX_FUZZ=40 $(LUAJIT) tests/run.lua fuzz

boot:
	$(LUAJIT) tests/boot.lua

lint:
	$(LUACHECK) --config .luacheckrc Skyhex tests tools

check: test boot lint

media:
	python3 tools/mkmedia.py Skyhex/Media

icon:
	python3 -I tools/mkicon.py

render:
	$(LUAJIT) tools/render.lua

snap:
	$(LUAJIT) tools/snap.lua
	@for f in tools/out/snap/*.txt; do python3 -I tools/snap.py "$$f"; done

# A full client restart is needed when the TOC or the file list changes (new textures
# included); Lua-only changes need /reload.
deploy:
	@test -d "$(WOW_DIR)/Interface/AddOns" || { echo "WoW AddOns folder not found: $(WOW_DIR)"; exit 1; }
	rsync -a --delete Skyhex/ "$(ADDON_DST)"
	@echo "deployed to $(ADDON_DST)"

package:
	rm -rf $(RELEASE)/Skyhex
	mkdir -p $(RELEASE)
	cp -R Skyhex $(RELEASE)/Skyhex
	sed -i.bak 's/@project-version@/$(VERSION)/' $(RELEASE)/Skyhex/Skyhex.toc && rm -f $(RELEASE)/Skyhex/Skyhex.toc.bak
	rm -f $(RELEASE)/Skyhex-$(VERSION).zip
	cd $(RELEASE) && zip -rqX Skyhex-$(VERSION).zip Skyhex -x "*.DS_Store"
	rm -rf $(RELEASE)/Skyhex
	@echo "$(RELEASE)/Skyhex-$(VERSION).zip"

clean:
	rm -rf $(RELEASE) tools/out
