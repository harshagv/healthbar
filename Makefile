# Which app to build: Upright (default) or MiniMe.
#   make run APP=MiniMe
APP      ?= Upright
CONFIG   := release
BIN_DIR   = $(shell swift build -c $(CONFIG) --product $(APP) --show-bin-path)
APP_BUNDLE = $(BIN_DIR)/$(APP).app

.PHONY: build run install uninstall clean minime

build:
	./build.sh $(CONFIG) $(APP)

run: build
	open "$(APP_BUNDLE)"

# Shorthand for the hydration + eye-break app.
minime:
	$(MAKE) run APP=MiniMe

install: build
	@echo "› Installing to /Applications/$(APP).app"
	rm -rf "/Applications/$(APP).app"
	cp -R "$(APP_BUNDLE)" "/Applications/$(APP).app"
	@echo "✓ Installed. Launch from Spotlight or: open -a $(APP)"

uninstall:
	rm -rf "/Applications/$(APP).app"
	@echo "✓ Removed /Applications/$(APP).app"

clean:
	rm -rf .build
