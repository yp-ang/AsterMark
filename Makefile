# AsterMark — build, test, bundle and install without Xcode (Command Line Tools are enough).
#
#   make            build debug
#   make test       run unit tests
#   make bench      pipeline benchmarks (BENCH_ARGS="--dir ~/Pictures/Shoot --count 20")
#   make app        release .app in build/
#   make run        build + launch the .app
#   make install    copy to /Applications (or ~/Applications)
#   make dmg        build/AsterMark.dmg
#   make release    signed + notarised DMG (needs SIGN_IDENTITY and NOTARY_PROFILE)

BUNDLE_ID         ?= app.astermark.AsterMark
MARKETING_VERSION ?= 0.1.0
BUILD_NUMBER      ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
SIGN_IDENTITY     ?= -
NOTARY_PROFILE    ?=

BUILD_DIR := build
APP       := $(BUILD_DIR)/AsterMark.app
DMG       := $(BUILD_DIR)/AsterMark-$(MARKETING_VERSION).dmg

# Swift Testing lives outside the default search path when only Command Line Tools are installed.
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
HAS_XCODE := $(shell xcodebuild -version >/dev/null 2>&1 && echo yes)
ifeq ($(HAS_XCODE),)
# The CLT build ships a broken _Testing_Foundation overlay (no Modules dir), so disable cross-import overlays.
TEST_FLAGS := -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xswiftc -F$(CLT_FRAMEWORKS) -Xlinker -F$(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)
endif

INSTALL_DIR := $(shell [ -w /Applications ] && echo /Applications || echo $(HOME)/Applications)

export BUNDLE_ID MARKETING_VERSION BUILD_NUMBER SIGN_IDENTITY NOTARY_PROFILE

.PHONY: all build test bench app run install dmg release clean lint format open-xcode

all: build

build:
	swift build

test:
	swift test $(TEST_FLAGS)

bench:
	swift run -c release Benchmarks $(BENCH_ARGS)

app:
	swift build -c release
	@mkdir -p $(BUILD_DIR)
	scripts/bundle.sh "$$(swift build -c release --show-bin-path)" $(BUILD_DIR)

run: app
	open $(APP)

install: app
	@mkdir -p "$(INSTALL_DIR)"
	@if pgrep -xq AsterMark; then osascript -e 'quit app "AsterMark"'; sleep 1; fi
	rm -rf "$(INSTALL_DIR)/AsterMark.app"
	cp -R $(APP) "$(INSTALL_DIR)/"
	@echo "Installed to $(INSTALL_DIR)/AsterMark.app"

dmg: app
	scripts/make-dmg.sh $(APP) $(DMG)

release:
	@test "$(SIGN_IDENTITY)" != "-" || (echo "Set SIGN_IDENTITY to your Developer ID Application identity"; exit 1)
	@test -n "$(NOTARY_PROFILE)" || (echo "Set NOTARY_PROFILE (xcrun notarytool store-credentials)"; exit 1)
	$(MAKE) dmg

lint:
	@command -v swiftlint >/dev/null && swiftlint lint --quiet || echo "swiftlint not installed (brew install swiftlint) — skipped"

format:
	@command -v swiftformat >/dev/null && swiftformat . || echo "swiftformat not installed (brew install swiftformat) — skipped"

open-xcode:
	open -a Xcode Package.swift

clean:
	swift package clean
	rm -rf $(BUILD_DIR)
