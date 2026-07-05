#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

pkill -x "Macked Updater" >/dev/null 2>&1 || true
pkill -x "macked-updater" >/dev/null 2>&1 || true

rm -rf .build .swiftpm/xcode dist/run
find . -name .DS_Store -type f -delete
find /private/tmp /tmp/ -maxdepth 1 \( \
  -name 'macked-updater-*' -o \
  -name 'macked-catalog-json-check*.txt' -o \
  -name 'macked-detail.html' -o \
  -name 'macked-home.html' -o \
  -name 'macked-search.html' -o \
  -name 'macked_hdiutil_verify*.log' \
\) -exec rm -rf {} + 2>/dev/null || true

cat <<MSG
Cleaned local debug artifacts.
Kept packaged apps and all historical DMGs under dist/.
MSG
