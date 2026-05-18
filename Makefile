.PHONY: all project build run archive clean xcodegen-check open

PROJECT := Auralis.xcodeproj
SCHEME := Auralis
CONFIG ?= Debug
DERIVED := build/DerivedData

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

archive: project
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -configuration Release \
	  -archivePath build/$(SCHEME).xcarchive \
	  archive

open: project
	open $(PROJECT)

clean:
	rm -rf build $(PROJECT)
