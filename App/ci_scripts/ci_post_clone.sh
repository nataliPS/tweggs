#!/bin/sh
# Xcode Cloud: runs right after the repo is cloned, before Xcode resolves packages and builds.
# Xcode Cloud looks for ci_scripts/ next to the .xcodeproj, so this folder lives in App/.
# The project is generated from project.yml with XcodeGen (it is not committed).
set -eu

echo "== Mixlings: ci_post_clone =="

# Homebrew is preinstalled on Xcode Cloud runners. Skip auto-update to keep builds fast.
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi
xcodegen --version

# This script's cwd is ci_scripts/; the spec is one level up.
cd "$(dirname "$0")/.."
xcodegen generate --spec project.yml

echo "== Generated Mixlings.xcodeproj =="
