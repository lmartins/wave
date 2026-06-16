APP_NAME := Wave
PROJECT := Wave.xcodeproj
SCHEME := Wave
CONFIGURATION := Release
DERIVED_DATA := $(CURDIR)/build
PRODUCTS_DIR := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)
APP_BUNDLE := $(PRODUCTS_DIR)/$(APP_NAME).app
DEBUG_PRODUCTS_DIR := $(DERIVED_DATA)/Build/Products/Debug
DEBUG_APP_BUNDLE := $(DEBUG_PRODUCTS_DIR)/$(APP_NAME).app
STAGING_DIR := $(CURDIR)/dmg-staging
DMG_NAME ?= Wave-Installer
DMG_PATH := $(CURDIR)/$(DMG_NAME).dmg
UPDATES_DIR := $(CURDIR)/updates/releases
APP_ZIP := $(UPDATES_DIR)/$(APP_NAME).zip
GENERATE_APPCAST := $(shell command -v generate_appcast 2>/dev/null || find "$(HOME)/Library/Developer/Xcode/DerivedData" -type f -name generate_appcast 2>/dev/null | head -n 1)

.PHONY: all build build-debug run run-cli release dmg zip appcast clean clean-dmg release-dmg release-appcast release-changelog

all: build

build: $(APP_BUNDLE)

$(APP_BUNDLE):
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		build

## build-debug: build the app with the Debug configuration
build-debug:
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Debug \
		-derivedDataPath "$(DERIVED_DATA)" \
		build

## run: build (Debug) and launch the app
run: build-debug
	open "$(DEBUG_APP_BUNDLE)"

## run-cli: build (Debug) and run the binary in the terminal (logs to stdout, Ctrl+C to quit)
run-cli: build-debug
	"$(DEBUG_APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"

dmg: build
	@command -v create-dmg >/dev/null 2>&1 || { \
		echo "error: create-dmg not found. Install it (e.g. brew install create-dmg)."; \
		exit 1; \
	}
	rm -rf "$(STAGING_DIR)"
	mkdir -p "$(STAGING_DIR)"
	cp -R "$(APP_BUNDLE)" "$(STAGING_DIR)/"
	rm -f "$(DMG_PATH)"
	create-dmg \
		--volname "$(APP_NAME)" \
		--window-pos 200 120 \
		--window-size 640 360 \
		--icon-size 96 \
		--icon "$(APP_NAME).app" 180 170 \
		--hide-extension "$(APP_NAME).app" \
		--app-drop-link 460 170 \
		"$(DMG_PATH)" \
		"$(STAGING_DIR)"

zip: build
	mkdir -p "$(UPDATES_DIR)"
	rm -f "$(APP_ZIP)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_BUNDLE)" "$(APP_ZIP)"

appcast: zip
	@test -n "$(GENERATE_APPCAST)" || { \
		echo "error: generate_appcast not found. Build once in Xcode after adding Sparkle, or install Sparkle tools."; \
		exit 1; \
	}
	"$(GENERATE_APPCAST)" "$(UPDATES_DIR)"

# ── Direct (self-distribution) release channel (modeled on Ayron) ─────────────
# Builds a Developer ID-signed + notarized DMG, produces a Sparkle appcast,
# and (after manual env load) publishes DMG + appcast to Cloudflare R2 under
# a custom updates domain so Sparkle (and the landing page) can consume them.
#
# One-time prep per machine:
#   - Set up R2 bucket + keys (see scripts/release/wave-release.env.example)
#   - Store notary credentials: xcrun notarytool store-credentials "wave-notary" ...
#   - Have a "Wave Self Distribution" Developer ID provisioning profile
#   - EdDSA keys for Sparkle (generate_keys once; public key in Info plist(s))
#
# Typical flow:
#   make release-dmg
#   make release-appcast
#   source scripts/release/load-release-env.sh && make publish-r2
#   # or the combined:
#   # (after sourcing env) make release
#
# The landing (Astro + wrangler) should be updated to offer the direct
# latest DMG and the site data should reference the stable Cloudflare URLs.

release-dmg:
	@bash scripts/release/build-dmg.sh $(VERSION) $(BUILD)

release-appcast:
	@bash scripts/release/update-appcast.sh

# Optional: if/when we add a node script to sync changelog entries into the
# landing or a docs site (see Ayron's update-website-changelog.mjs).
release-changelog:
	@echo "release-changelog: no-op for now (update landing manually or add a script modeled on Ayron). VERSION=$(VERSION) BUILD=$(BUILD)"

publish-r2:
	@bash scripts/release/publish-r2.sh

release: release-dmg release-appcast
	@echo "✅  Direct release artefacts ready in build/release/."
	@echo "   Next: source scripts/release/load-release-env.sh && make publish-r2"
	@echo "   Then deploy any landing updates that reference the direct DMG."

clean:
	rm -rf "$(DERIVED_DATA)"

clean-dmg:
	rm -rf "$(STAGING_DIR)" "$(DMG_PATH)"
