#!/usr/bin/env bash
# Boots an iPhone and an iPad simulator, launches Crowser in several states and saves screenshots.
# Usage: scripts/screenshots.sh path/to/Crowser.app out-dir
set -euo pipefail

APP="$1"
OUT="$2"
BUNDLE=com.aaron1612n.crowser
PAGE="https://en.wikipedia.org/wiki/Corvidae"
PAGES="https://en.wikipedia.org/wiki/Corvidae|https://news.ycombinator.com|https://www.audubon.org/field-guide/bird/american-crow"
mkdir -p "$OUT"

pick() {
  # Newest-runtime "Pro" device whose name starts with $1.
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
  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" -crowserFresh YES "$@" >/dev/null
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
  shoot "$udid" "$label-1-start" 8 -crowserSeed YES
  shoot "$udid" "$label-2-page" 12 -crowserOpen "$PAGE"
  shoot "$udid" "$label-3-tabs" 16 -crowserOpen "$PAGES" -crowserScene tabs
  shoot "$udid" "$label-4-more" 12 -crowserOpen "$PAGE" -crowserScene more
  if [ "$kind" = iPhone ]; then
    shoot "$udid" "$label-5-collapsed" 12 -crowserOpen "$PAGE" -crowserScene collapsed
    shoot "$udid" "$label-6-search" 10 -crowserSeed YES -crowserScene edit -crowserQuery "crow"
    shoot "$udid" "$label-7-settings" 14 -crowserScene settings
    shoot "$udid" "$label-14-groups" 18 -crowserOpen "$PAGES" -crowserScene groups
    shoot "$udid" "$label-15-palette" 12 -crowserOpen "$PAGE" -crowserScene palette
    shoot "$udid" "$label-16-qrcode" 12 -crowserOpen "$PAGE" -crowserScene qrcode
    shoot "$udid" "$label-13-tucked" 12 -crowserOpen "$PAGE" -crowserScene tucked
    shoot "$udid" "$label-10-shields" 12 -crowserOpen "$PAGE" -crowserScene shields
    shoot "$udid" "$label-11-more-full" 12 -crowserOpen "$PAGE" -crowserScene morefull
  fi
  xcrun simctl ui "$udid" appearance dark
  shoot "$udid" "$label-8-start-dark" 8
  shoot "$udid" "$label-9-tabs-dark" 16 -crowserOpen "$PAGES" -crowserScene tabs
  if [ "$kind" = iPhone ]; then
    shoot "$udid" "$label-12-settings-dark" 9 -crowserScene settings
  fi

  xcrun simctl shutdown "$udid" || true
done
