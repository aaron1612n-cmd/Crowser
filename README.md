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

- A floating bar that folds into a small pill while you scroll. Swipe it sideways to change tabs; long-press the tab counter for quick actions.
- Tap the address to open a search panel with live suggestions, Paste and go, favorites and history.
- Tab overview with page previews: tap to switch, swipe a card away to close, reopen closed tabs, private tabs on their own side.
- Game mode, remembered per site: no text selection, hold-to-copy menus, link previews, zoom, swipe-back or page bounce; optional scroll lock; full screen with a corner button for the bar; the screen stays awake.
- "This site" settings remembered per site: game mode, desktop version, text size, and ad blocking on or off.
- Optional hiding of cookie consent popups.
- Built-in ad and tracker blocking (third-party ad/tracking networks only, so sites keep working).
- Page panel: share, favorite, find on page, desktop/mobile site, text size, copy link.
- Long-press links for Open in New Tab / Private Tab / Copy Link. Downloads open the share sheet so you can save to Files.
- Works with sign-in popups, site alerts, camera/microphone/location prompts and saving images.
- Restored tabs load only when you look at them, so launch is instant.
- iPhone: bar at the bottom. iPad: bar on top, with keyboard shortcuts
  (⌘T, ⇧⌘N, ⌘W, ⇧⌘T reopen, ⌘L, ⌘R, ⌘[ ⌘], ⌘D, ⌘F, ⌘Y, ⇧⌘\\, ⇧⌘[ ⇧⌘]).

## Look

Warm paper `#F4F0E8`, a crow-black floating bar `#171614` (charcoal `#2B2926` at night), and one accent, ember `#E2531F`.
Titles are set in New York, everything you touch in SF Rounded. Motion uses one family of springs.

## Speed, honestly

Every iOS browser must use Apple's WebKit engine, the same one inside Safari, so page rendering itself can't beat Safari.
Crowser feels faster by not loading ad and tracking scripts, by restoring tabs lazily, and by caching icons and suggestions.

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
