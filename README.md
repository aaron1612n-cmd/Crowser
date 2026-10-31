# Crowser

A small, opinionated web browser for iPhone and iPad, built with SwiftUI and WebKit.

## Getting it onto your phone (SideStore)

Crowser ships as an **unsigned `.ipa`**. SideStore signs it with your own Apple ID when it installs.

1. Open the latest run of the **Build** workflow under the repo's **Actions** tab.
2. Download the `Crowser-…-unsigned-ipa` artifact. GitHub zips artifacts, so unzip it to get `Crowser.ipa`.
3. Get the file onto your phone (AirDrop, Files, iCloud Drive) and open it with SideStore, or tap **+** in SideStore's My Apps and pick it.
4. Free Apple IDs need the app refreshed in SideStore every 7 days.

Every build of the default branch also publishes the `.ipa` to a GitHub Release (`v` + `MARKETING_VERSION` from `project.yml`), which is easier to grab from a phone: it is the bare `.ipa`, not a zip.

## What it does

- Tabs, including private tabs that keep nothing (separate, in-memory website data).
- One bar for addresses and searches; DuckDuckGo by default, or Google, Startpage, Bing.
- Bookmarks ("Roost") and history ("Lately"), with suggestions as you type.
- Pull to refresh, swipe back and forward, share sheet, links that open new windows open new tabs.
- Phone: the bar sits at the bottom under your thumb. iPad: one row on top, with keyboard shortcuts:
  ⌘T new tab, ⇧⌘N private tab, ⌘W close, ⌘L address, ⌘R reload, ⌘[ / ⌘] back and forward,
  ⌘D bookmark, ⌘Y library, ⇧⌘\ tabs, ⇧⌘[ / ⇧⌘] switch tabs.
- Light and dark appearance.

## Look

The palette is called **Rookery**: soot `#15130F`, bone `#EEE7D7`, feather `#2A2722`, ash `#8A8476`,
and a single accent, ember `#D9481C`. Names and numbers are set in New York (Apple's serif); addresses
and labels in SF Mono. The only animation is the ember line that runs along the bar while a page loads.

## Building

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open Crowser.xcodeproj
```

Requires Xcode 16 or newer; the app targets iOS 16+.
CI (`.github/workflows/build.yml`) builds the unsigned `.ipa` on every push and captures simulator
screenshots of the iPhone and iPad layouts (`scripts/screenshots.sh`).
