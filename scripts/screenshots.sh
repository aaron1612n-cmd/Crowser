#!/usr/bin/env bash
# Boots an iPhone and an iPad simulator, launches Crowser in a few states and saves screenshots.
# Usage: scripts/screenshots.sh path/to/Crowser.app out-dir
set -euo pipefail

APP="$1"
OUT="$2"
BUNDLE=com.aaron1612n.crowser
PAGES="https://en.wikipedia.org/wiki/Corvidae|https://news.ycombinator.com|https://www.audubon.org/field-guide/bird/american-crow"
mkdir -p "$OUT"

pick() {
  # Newest-runtime available device whose name starts with $1.
  xcrun simctl list devices available -j | python3 -c '
import json, sys
prefix = sys.argv[1]
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    for d in devices:
        if d["name"].startswith(prefix) and "Pro" in d["name"]:
            key = (runtime, d["name"])
            if best is None or key > best[0]:
                best = (key, d["udid"])
print(best[1] if best else "")
' "$1"
}

shoot() {
  local udid="$1" name="$2" wait="$3"; shift 3
  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$udid" screenshot "$OUT/$name.png" >/dev/null
  echo "saved $OUT/$name.png"
}

for kind in iPhone iPad; do
  udid=$(pick "$kind")
  if [ -z "$udid" ]; then echo "no $kind simulator found"; continue; fi
  label=$(echo "$kind" | tr '[:upper:]' '[:lower:]')
  echo "Using $kind $udid"
  xcrun simctl boot "$udid" || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 || true
  xcrun simctl install "$udid" "$APP"

  xcrun simctl ui "$udid" appearance light
  shoot "$udid" "$label-1-start" 6 -crowserSeed YES -crowserFresh YES
  shoot "$udid" "$label-2-page" 12 -crowserFresh YES -crowserOpen "https://en.wikipedia.org/wiki/Corvidae"
  shoot "$udid" "$label-3-tabs" 10 -crowserFresh YES -crowserOpen "$PAGES" -crowserSheet tabs
  xcrun simctl ui "$udid" appearance dark
  shoot "$udid" "$label-4-start-dark" 6 -crowserFresh YES

  xcrun simctl shutdown "$udid" || true
done
