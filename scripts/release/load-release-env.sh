#!/usr/bin/env bash
# Load persistent Wave release credentials into the current shell.
# Usage: source scripts/release/load-release-env.sh
#
# Looks for $WAVE_RELEASE_ENV or $HOME/.pi/agent/wave-release.env by default.
# Create from wave-release.env.example and fill real R2 + domain values.

set -euo pipefail

CREDENTIAL_FILE="${WAVE_RELEASE_ENV:-$HOME/.pi/agent/wave-release.env}"

if [[ ! -f "$CREDENTIAL_FILE" ]]; then
  echo "Missing $CREDENTIAL_FILE" >&2
  echo "Create it from scripts/release/wave-release.env.example, then run: source scripts/release/load-release-env.sh" >&2
  return 1 2>/dev/null || exit 1
fi

# shellcheck disable=SC1090
source "$CREDENTIAL_FILE"

echo "Loaded Wave release credentials from $CREDENTIAL_FILE"
