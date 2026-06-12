# Vorssaint Utils

> A premium, native utility hub for macOS — living quietly in your menu bar.

[![Release](https://img.shields.io/github/v/release/vorssaint/vorssaint-utils?label=release)](https://github.com/vorssaint/vorssaint-utils/releases)
[![CI](https://github.com/vorssaint/vorssaint-utils/actions/workflows/ci.yml/badge.svg)](https://github.com/vorssaint/vorssaint-utils/actions/workflows/ci.yml)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B%20(Apple%20Silicon)-black)](#requirements)
[![License: PolyForm NC](https://img.shields.io/badge/license-PolyForm%20Noncommercial-blue)](LICENSE)

*Leia em [Português (Brasil)](docs/README.pt-BR.md).*

Vorssaint Utils keeps your Mac awake on demand, shows the system readings that
actually matter, gives your mouse Windows-style scrolling without touching the
trackpad, and replaces ⌘Tab with a window switcher that shows real thumbnails.
100% native (SwiftUI + AppKit), bilingual (en-US / pt-BR), no Electron, no
analytics, no network calls.

## Features

### ⚡ Keep awake
- Toggle from the panel, the right-click menu or the global shortcut **⌃⌥⌘K**
- Sessions from 15 min to 8 h, or indefinite — with +15/+30/+60 min extensions
- Keep the display on, or let it sleep while the system stays awake
- **Closed-lid mode**: keep a MacBook running with the lid shut
  (`pmset disablesleep`, automatically reverted when the session ends, the app
  quits or after a crash)
- **Optional password-free toggling**: a `sudoers` rule restricted to
  `pmset disablesleep 0/1`, validated with `visudo -c`, removable at any time
- **Battery protection**: the session shuts off below a charge threshold
- Menu bar countdown and end-of-session notifications

### 🌡️ System monitor
- **Temperatures** for CPU, GPU and battery — the most relevant reading per
  component, straight from the SMC
- **Hardware usage**: CPU % and GPU %
- **Memory pressure** with a traffic-light indicator
  (green = normal, yellow = caution, red = critical) plus used/total memory

### 🖱️ Windows-style scrolling
- Inverts the **mouse wheel only** — the trackpad keeps macOS natural scrolling
- Applies instantly, no restart, no kernel extension

### 🪟 Window switcher
- Replaces **⌘Tab** with a grid showing every window as a live thumbnail —
  not just app icons
- Multiple windows of the same app appear individually
- Hold ⌘ and tap Tab to cycle; Shift/← goes back; release to switch; **Q** quits
  the highlighted app; Esc cancels — follows the real most-recently-used order,
  fluid, animated, Mission Control & Spaces friendly
- Falls back gracefully to app icons when Screen Recording is not granted

### 🧰 Utilities
- Hide desktop icons (presentations, recordings)
- Show hidden files in Finder
- Turn off the display · Eject all disks · Empty Trash (with confirmation)

## Install

### Download (recommended)
Grab the latest DMG from [**Releases**](https://github.com/vorssaint/vorssaint-utils/releases),
open it and drag **Vorssaint Utils** into **Applications**.

> Releases are ad-hoc signed (no paid Apple Developer certificate). On first
> launch, right-click the app → **Open**, or clear the quarantine flag:
> `xattr -d com.apple.quarantine "/Applications/Vorssaint Utils.app"`

### Build from source
```sh
git clone https://github.com/vorssaint/vorssaint-utils.git
cd vorssaint-utils
./build.sh            # compile, generate the icon, assemble the signed bundle
./build.sh --install  # same + install into /Applications and launch
```

### Requirements
- macOS 14 (Sonoma) or newer
- Apple Silicon
- Xcode Command Line Tools (to build from source)

### Uninstall
```sh
./Tools/uninstall.sh   # from a clone, or download it from the repo
```
It quits the app, unregisters the login item, resets its Accessibility and
Screen Recording permissions, deletes the app, preferences and saved state,
and removes the optional closed-lid `sudoers` rule — leaving nothing behind.
Or just drag the app to the Trash and run
`tccutil reset All com.vorssaint.utils` to clear its permissions.

## Permissions

Everything is optional — features degrade gracefully and the onboarding walks
you through each grant:

| Permission | Used by | Without it |
|---|---|---|
| **Accessibility** | Scroll inverter, switcher keyboard handling | Both features stay off |
| **Screen Recording** | Window titles & thumbnails in the switcher | Switcher shows app icons only |
| **Notifications** | Session end & battery protection alerts | Silent operation |
| **Administrator (once, optional)** | Password-free closed-lid toggling | Password prompt per toggle |

The first launch opens a 7-step onboarding (language, permissions, monitor
tour, optional features, status check). Revisit it anytime from
**Settings › About › Review introduction**.

## Architecture

```
Sources/VorssaintUtils/
├── main.swift                  # entry point (--selftest, --sensors)
├── App/                        # AppDelegate, menu bar status item
├── Core/                       # localization (pt-BR/en-US), permissions, defaults
├── Services/
│   ├── KeepAwakeManager.swift  # IOKit assertions, closed lid, battery watch
│   ├── ScrollInverter.swift    # CGEventTap, mouse-only inversion
│   ├── SystemMonitor/          # SMC client, CPU/GPU usage, memory pressure
│   ├── Switcher/               # enumeration, AX activation, SCK previews, tap
│   └── …                       # hotkey, notifications, shell helpers
├── Support/                    # selftest & sensor dump
└── UI/                         # SwiftUI: panel, settings, onboarding, switcher
```

Strict separation: **UI** observes **services**; services never import SwiftUI.
Every user-facing string lives in `Core/Localization.swift`, compiler-checked
for both languages.

Diagnostics:
```sh
"/Applications/Vorssaint Utils.app/Contents/MacOS/VorssaintUtils" --selftest  # SELFTEST OK
"/Applications/Vorssaint Utils.app/Contents/MacOS/VorssaintUtils" --sensors   # SMC sensor dump
```

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md)
for the build setup, project conventions and how to add a translation or port
the sensor mapping to a new chip.

## License

[PolyForm Noncommercial License 1.0.0](LICENSE) — © 2026 Vorssaint.
Free to use, modify and share for any **noncommercial** purpose, with attribution.
Commercial use is not permitted.
