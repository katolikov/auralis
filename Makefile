.PHONY: all project build run test archive previews clean xcodegen-check open

PROJECT := Auralis.xcodeproj
SCHEME := Auralis
CONFIG ?= Debug
DERIVED := build/DerivedData
PREVIEWS_DIR := docs/previews

all: project

xcodegen-check:
	@command -v xcodegen >/dev/null 2>&1 || { \
	  echo "xcodegen not installed."; \
	  echo "  brew install xcodegen"; \
	  exit 1; \
	}

project: xcodegen-check $(PROJECT)

$(PROJECT): project.yml
	xcodegen generate

build: project
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -configuration $(CONFIG) \
	  -derivedDataPath $(DERIVED) \
	  build

run: build
	@APP="$(DERIVED)/Build/Products/$(CONFIG)/$(SCHEME).app"; \
	if [ ! -d "$$APP" ]; then \
	  echo "Build output not found at $$APP"; exit 1; \
	fi; \
	echo "Launching $$APP"; \
	open "$$APP"

test: project
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -configuration $(CONFIG) \
	  -derivedDataPath $(DERIVED) \
	  test

archive: project
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -configuration Release \
	  -archivePath build/$(SCHEME).xcarchive \
	  archive

previews: build
	@mkdir -p $(PREVIEWS_DIR)
	@APP="$(DERIVED)/Build/Products/$(CONFIG)/$(SCHEME).app/Contents/MacOS/Auralis"; \
	if [ ! -x "$$APP" ]; then echo "Binary not found at $$APP"; exit 1; fi; \
	"$$APP" --render-previews "$(PREVIEWS_DIR)" || true; \
	ls -1 $(PREVIEWS_DIR)

open: project
	open $(PROJECT)

clean:
	rm -rf build $(PROJECT)
