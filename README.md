# KOlumen — Brightness Swipe Plugin for KOReader

<div align="center">

[![KOReader Compatibility](https://img.shields.io/badge/KOReader-2023.01%2B-blue.svg)](https://github.com/koreader/koreader)
[![Release Version](https://img.shields.io/badge/version-1.1.0-brightgreen.svg)](https://github.com/xmb03/kolumen.koplugin/releases/latest)
[![Supported Platforms](https://img.shields.io/badge/Platform-Android%20%7C%20E--ink%20%7C%20Linux-orange.svg)](https://github.com/koreader/koreader)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/xmb03/kolumen.koplugin/pulls)

*A gesture plugin for KOReader providing continuous, real-time screen brightness control via vertical swipes in the center of the display.*

[Features](#features) • [Screen Layout](#screen-layout-and-zones) • [Installation](#installation) • [Configuration](#configuration) • [Repository Structure](#repository-structure) • [How It Works](#how-it-works) • [Packaging](#packaging-a-release) • [FAQ](#frequently-asked-questions) • [License](#license)

Read this in [Russian (Русский)](README_RU.md).

</div>

---

## Overview

In [KOReader](https://github.com/koreader/koreader), native brightness gestures are typically positioned along the extreme left or right borders of the screen. While functional on dedicated e-readers with hardware bezels, this design introduces frequent conflicts on modern Android smartphones and tablets:
* Border swipes trigger Android's system "Back" navigation gesture from the edges.
* Top-edge drags accidentally pull down the Android notification shade and quick settings.
* Bottom-edge drags conflict with gesture navigation bars and "Home" actions.
* Corner touches interfere with page-turning taps.

**KOlumen** repositions brightness adjustment into a dedicated, configurable vertical corridor in the center of the screen. With an adaptive zero-jump anchoring engine, real-time feedback, and full E-ink anti-ghosting compensation, it provides intuitive and friction-free illumination control.

---

## Features

* **Two Adjustment Modes:**
  * **Adaptive (Relative) [Default]:** Initial touch anchors directly to current device brightness. Dragging up or down shifts brightness smoothly by delta displacement. Touching the screen never causes sudden jumps in illumination.
  * **Fixed (Absolute):** Absolute screen coordinate mapping (bottom of active zone = 0%, middle = 50%, top = 100%).
* **Anti-Deadzone Re-Anchoring:**
  * If a swipe reaches 0% or 100% and movement continues, the anchor coordinate dynamically follows the finger. Reversing direction adjusts brightness immediately without any dead-zone delay.
* **Continuous Real-Time Tracking:**
  * Screen brightness and hardware frontlight update continuously as the finger moves across the screen.
* **Non-Blocking OSD Overlay:**
  * Clean badge overlay (`Brightness: 64%`) centered at the top of the display.
  * Fully transparent to touch events (`toast = true`): reading taps and page gestures pass through with zero input latency.
  * Theme-adaptive styling with automatic contrast matching for KOReader Light and Dark (Night) modes.
  * E-ink ghosting mitigation via full dirty-buffer invalidation (`UIManager:setDirty("all")`), preventing trailing numbers and smearing.
* **System Gesture Protection:**
  * **Top & Bottom Margins (default 15%):** Keeps upper and lower screen regions free for notification shades and navigation docks.
  * **Center Corridor (default 50% width):** Keeps outer 25% lateral margins free for page turns and edge navigation.

---

## Screen Layout and Zones

```text
+---------------------------------------------+  0% (Top edge)
|           Top Margin (default 15%)          |  <- Excluded (Android notification shade)
+---------------------------------------------+  15% (Upper limit = 100% in Fixed Mode)
|      |                               |      |
| Left |     Center Active Zone        | Right|  <- Dragging here adjusts brightness
| Edge |        (default 50%           | Edge |
| (25%)|        screen width)          | (25%)|  <- Middle of screen = 50% in Fixed Mode
|      |                               |      |
+---------------------------------------------+  85% (Lower limit = 0% in Fixed Mode)
|         Bottom Margin (default 15%)         |  <- Excluded (Android navigation bar)
+---------------------------------------------+  100% (Bottom edge)
```

* **Top Margin (0% to 15%):** Swipes starting here are ignored to preserve access to top status bars and menus.
* **Bottom Margin (85% to 100%):** Swipes starting here are ignored to prevent triggering system home gestures.
* **Lateral Margins (0%–25% and 75%–100%):** Left and right zones remain dedicated to KOReader page flips and Android side navigation.
* **Center Active Corridor:** Vertical drags here lock gesture tracking and update brightness.

---

## Installation

### Installation Steps

1. Download `kolumen.koplugin.zip` from the latest [GitHub Release](https://github.com/xmb03/kolumen.koplugin/releases/latest).
2. Connect your device to your computer via USB, or use a file manager on your device.
3. Extract `kolumen.koplugin.zip` so that the `kolumen.koplugin` folder is placed directly inside the `plugins/` directory of your KOReader installation.
4. Perform a complete restart of KOReader.
5. Open any document and swipe vertically in the center of the display.

### Device Directory Reference

| Platform / Device | Plugins Directory Path |
| :--- | :--- |
| **Android** | `/sdcard/koreader/plugins/`<br>*(or `/sdcard/Android/data/org.koreader.launcher/files/koreader/plugins/`)* |
| **Kindle** | `/koreader/plugins/` |
| **Kobo** | `/.adds/koreader/plugins/` |
| **PocketBook** | `/mnt/ext1/applications/koreader/plugins/` |
| **Desktop Linux** | `~/.config/koreader/plugins/` |

> [!IMPORTANT]
> A full restart of KOReader is required after installing or updating plugins. Simply returning to the home screen does not trigger plugin re-indexing.

---

## Configuration

To customize gesture settings:
1. Open any document in KOReader.
2. Tap the top edge of the screen to display the menu bar.
3. Tap the **Device (Gear)** icon.
4. Select **KOlumen**.

### Available Options

| Option | Available Settings | Default | Description |
| :--- | :--- | :--- | :--- |
| **Enable brightness swipe** | `On` / `Off` | `On` | Activates or disables gesture tracking. |
| **Adjustment mode** | `Adaptive (relative)`<br>`Fixed (absolute)` | `Adaptive` | **Adaptive:** Relative delta tracking without jumps.<br>**Fixed:** Direct position-to-percentage mapping. |
| **Top and bottom margin** | `10%`, `15%`, `20%`, `25%` | `15%` | Protective exclusion margin at top and bottom edges. |
| **Center zone width** | `30%`, `40%`, `50%`, `60%`, `70%` | `50%` | Horizontal screen width percentage for gesture detection. |
| **Show brightness indicator** | `On` / `Off` | `On` | Enables the non-blocking top OSD badge. |
| **Indicator display duration** | `1.0s`, `1.5s`, `2.0s`, `3.0s` | `1.5s` | Duration before the OSD badge disappears after release. |

Settings are automatically saved to `settings/kolumen.lua` and preserved across application updates.

---

## Repository Structure

```text
kolumen.koplugin/
├── .github/
│   └── workflows/
│       └── release.yml       <- Automated GitHub release & ZIP packager
├── l10n/
│   └── ru.lua                <- Russian localization catalog
├── _meta.lua                 <- Plugin manifest (name, version, category)
├── i18n.lua                  <- Standalone fallback translation engine
├── main.lua                  <- Gesture interception, OSD, and brightness controller
├── .gitignore                <- Ignored patterns
├── LICENSE                   <- GNU General Public License v3.0
├── README.md                 <- English documentation
└── README_RU.md              <- Russian documentation
```

---

## How It Works

### Fullscreen Touch Interception
KOReader's `GestureRange:match()` mechanism will abort gesture tracking if a touch zone is defined as a partial rectangle and the user's finger strays outside of its boundaries during a motion. KOlumen registers a fullscreen listener (`ratio_w = 1.0, ratio_h = 1.0`) and performs origin checks, vector slope analysis (`dy / dx > 1.2`), and distance checks internally inside `onPanMove()`.

### Adaptive Delta Calculations
In Adaptive Mode, displacement is calculated via:
* `delta_y = anchor_y - current_y`
* `delta_percent = (delta_y / active_height) * 100`

When the calculated brightness reaches `100%` or `0%`, continuing motion dynamically shifts `anchor_y` to maintain parity with the current touch point. When the user reverses the swipe direction, brightness changes immediately with zero dead-zone delay.

### E-ink Smearing Mitigation
To eliminate lingering digit artifacts on e-ink hardware, the OSD widget calls `UIManager:setDirty("all", function() return "ui", self.dimen end)` upon each value change, ensuring a full visual clean sweep of the dirty region.

---

## Packaging a Release

GitHub Actions automatically builds and publishes `kolumen.koplugin.zip` on every version tag (`v*`).

To build the release archive manually on Windows PowerShell:

```powershell
New-Item -ItemType Directory -Path build\kolumen.koplugin -Force | Out-Null
Copy-Item _meta.lua, main.lua, i18n.lua, LICENSE, README.md, README_RU.md build\kolumen.koplugin\
Copy-Item -Recurse l10n build\kolumen.koplugin\
Compress-Archive -Path build\kolumen.koplugin -DestinationPath kolumen.koplugin.zip -Force
Remove-Item -Recurse -Force build
```

The resulting `kolumen.koplugin.zip` contains the `kolumen.koplugin` folder, ready for direct extraction into KOReader's `plugins/` directory.

---

## Frequently Asked Questions

#### Why is the plugin not listed in the Device menu?
Ensure the folder extracted into `plugins/` is named exactly `kolumen.koplugin`. Exit KOReader completely (**Top Menu -> Exit**), then relaunch.

#### Can I adjust the swipe width if it interferes with fast reading?
Yes. If you frequently turn pages near the center of the screen, open **Device -> KOlumen** and change **Center zone width** to `30%` or `40%`.

#### Does the OSD indicator block screen taps?
No. The OSD widget operates as a transparent overlay (`toast = true`), allowing reading taps and navigation gestures to pass through without input latency.

---

## Localization (i18n)

The plugin automatically adapts to KOReader's current language selection.

Translations are stored in modular Lua tables under `l10n/`:
* `l10n/ru.lua` — Russian

To add a new translation, create `l10n/<lang_code>.lua`, translate the key-value pairs, and submit a Pull Request.

---

## License

This project is licensed under the **GNU General Public License v3.0 (GPLv3)**. See [LICENSE](LICENSE) for the full license text.
