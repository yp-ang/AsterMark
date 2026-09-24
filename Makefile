# AsterMark — build, test, bundle and install without Xcode (Command Line Tools are enough).
#
#   make            build debug
#   make test       run unit tests
#   make coverage   AsterCore line coverage
#   make smoke      end-to-end check of the release app
#   make bench      pipeline benchmarks (BENCH_ARGS="--dir ~/Pictures/Shoot --count 20")
#   make app        release .app in build/
#   make run        build + launch the .app
#   make install    copy to /Applications (or ~/Applications)
#   make dmg        build/AsterMark.dmg
#   make release    signed + notarised DMG (needs SIGN_IDENTITY and NOTARY_PROFILE)

BUNDLE_ID         ?= app.astermark.AsterMark
# Version from the latest tag (v1.2.3 → 1.2.3), else 0.1.0.
MARKETING_VERSION ?= $(shell v=$$(git describe --tags --abbrev=0 2>/dev/null); echo $${v:-v0.1.0} | sed 's/^v//')
BUILD_NUMBER      ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
SIGN_IDENTITY     ?= -
NOTARY_PROFILE    ?=
# UNIVERSAL=1 builds arm64 + x86_64 and merges them with lipo (default for `make release`).
UNIVERSAL         ?= 0

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

.PHONY: all build test coverage smoke bench bench-check app run install dmg release clean lint format open-xcode

all: build

build:
	swift build

test:
	swift test $(TEST_FLAGS)

# Line coverage of AsterCore (the app target is UI and is covered by `make smoke`).
coverage:
	swift test --enable-code-coverage $(TEST_FLAGS)
	@xcrun llvm-cov report "$$(find .build/debug/ -name AsterMarkPackageTests -type f -perm +111 | head -1)" \
		-instr-profile "$$(dirname $$(swift test --show-codecov-path))/default.profdata" \
		-ignore-filename-regex='Tests|Benchmarks|AsterMarkApp|\.build' | tail -1

# End-to-end check of the sandboxed release app (opens a generated album and logo, then quits).
smoke: app
	scripts/smoke-test.sh

# Fails if the pipeline got more than 15% slower than Benchmarks/baseline.json.
bench-check:
	swift run -c release Benchmarks --count 4 --check Benchmarks/baseline.json

bench:
	swift run -c release Benchmarks $(BENCH_ARGS)

app:
ifeq ($(UNIVERSAL),1)
	swift build -c release --triple arm64-apple-macosx15.0 --product AsterMark
	swift build -c release --triple x86_64-apple-macosx15.0 --product AsterMark
	@mkdir -p $(BUILD_DIR)/universal
	lipo -create -output $(BUILD_DIR)/universal/AsterMark \
		.build/arm64-apple-macosx/release/AsterMark .build/x86_64-apple-macosx/release/AsterMark
	scripts/bundle.sh $(BUILD_DIR)/universal $(BUILD_DIR)
else
	swift build -c release
	@mkdir -p $(BUILD_DIR)
	scripts/bundle.sh "$$(swift build -c release --show-bin-path)" $(BUILD_DIR)
endif

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
	$(MAKE) dmg UNIVERSAL=1

lint:
	@command -v swiftlint >/dev/null && swiftlint lint --quiet || echo "swiftlint not installed (brew install swiftlint) — skipped"

format:
	@command -v swiftformat >/dev/null && swiftformat . || echo "swiftformat not installed (brew install swiftformat) — skipped"

open-xcode:
	open -a Xcode Package.swift

clean:
	swift package clean
	rm -rf $(BUILD_DIR)
