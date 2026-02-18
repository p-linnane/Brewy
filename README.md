# Brewy

A native macOS app for managing [Homebrew](https://brew.sh) packages. Browse, search, install, and update formulae and casks — all without opening Terminal.

> **Note:** Brewy is in early development and currently provides only basic functionality. Expect rough edges, missing features, and breaking changes.

## Features

- Browse installed formulae and casks
- Search Homebrew/core and Homebrew/cask repositories
- View package details, dependencies, and reverse dependencies
- Install, uninstall, upgrade, pin, and unpin packages
- Upgrade all outdated packages at once
- Manage taps (add/remove third-party repositories)
- Run `brew doctor`, remove orphaned packages, and clear the download cache
- Menu bar extra showing outdated package count
- Configurable auto-refresh interval and brew path

## Requirements

- macOS 15.0 or later (Apple Silicon)
- [Homebrew](https://brew.sh) installed (defaults to `/opt/homebrew/bin/brew`, configurable in Settings)

## Building

1. Clone the repository
2. Open `Brewy.xcodeproj` in Xcode
3. Build and run (Cmd+R)

## Contributing

Contributions are welcome. Feel free to open a pull request.

## Acknowledgements

Thanks to [@bevanjkay](https://github.com/bevanjkay) for the logo idea.

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE) (`GPL-3.0-only`).

Copyright (C) 2026 Patrick Linnane
