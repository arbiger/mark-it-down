# Mark-It-Down

A native macOS app that converts documents to Markdown using [microsoft/markitdown](https://github.com/microsoft/markitdown). Drag a folder or a single file onto the window, click **Start**, and the `.md` files land next to the originals.

This is a personal-use SwiftUI wrapper around the `markitdown` Python CLI. It exists to make batch conversions frictionless: drop, click, done. Outputs never overwrite — collisions get `(N)` suffixes.

Powered by [microsoft/markitdown](https://github.com/microsoft/markitdown) (MIT). This project is **not** affiliated with or endorsed by Microsoft; the app name is hyphenated to make that distinction clear.

## What it does

- Drag-and-drop a **folder** (recursive scan) or a **single file** (its parent folder is scanned)
- Supports PDF, DOCX, PPTX, XLSX, HTML, EPUB, CSV, JSON, XML, images (with OCR), audio (with transcription), and more
- Output written next to each source — `foo.pdf` becomes `foo.md` in the same folder
- Never overwrites: existing and same-batch collisions get `(N)` suffixes
- Up to 4 parallel conversions via Swift `actor` + `TaskGroup`
- Stop cancels active subprocesses instead of leaving conversions running
- Native SwiftUI, no Electron

## Requirements

- macOS 14 (Sonoma) or later
- Python 3.10+ somewhere on the system (Homebrew recommended, or any venv)
- Internet access on first run if markitdown isn't already installed anywhere

## Install

```bash
git clone <your-fork-url> Mark-It-Down
cd Mark-It-Down
./make-app.sh release
open Mark-It-Down.app
```

If macOS Gatekeeper blocks the first launch (ad-hoc codesign):

```bash
xattr -dr com.apple.quarantine Mark-It-Down.app
```

Drag `Mark-It-Down.app` to `/Applications` if you want it permanently installed.

## How bootstrap works

On first launch the app:

1. Probes candidate Python 3.10+ installs (Homebrew Apple Silicon / Intel, python.org framework, `/usr/bin/python3`)
2. For each candidate, tries `python -c "import markitdown"` — a broken candidate does not block the next one
3. If none do, runs `pip install --user --break-system-packages 'markitdown[all]'` automatically (`--break-system-packages` is needed because Homebrew Python 3.11+ is externally-managed per PEP 668)
4. Falls back to system-wide install if `--user` fails

## Usage

1. Launch `Mark-It-Down.app`
2. Bootstrap runs in the background (one-time, ~30–60s on first launch if markitdown needs installing)
3. Drag a folder (or any number of files) onto the drop zone, or click to pick
4. Review the file list — `<name>.pdf → <name>.md`
5. Click **Start**
6. When done, click **Show in Finder** to see the output

## Development

```bash
./run-dev.sh      # swift run for development
./run-tests.sh    # compile and run the native core test suite
swift build       # compile only
```

The test runner is intentionally framework-free because Apple Command Line Tools on this host does not expose a usable XCTest/Swift Testing runner. It compiles the production sources (excluding the app entry point) together with the tests, then runs the resulting executable. No full Xcode install or third-party dependency is required.

## Project structure

```
Mark-It-Down/
├── Package.swift                          SwiftPM macOS executable
├── Sources/MarkItDown/                    App and conversion-engine code
├── Tests/MarkItDownTests/                 Native automated core tests
├── Resources/                             Info.plist template, AppIcon.icns
├── make-app.sh                            build → wrap into .app → codesign
├── run-dev.sh                             swift run wrapper
├── run-tests.sh                           compile and run automated tests
├── README.md                              this file
└── LICENSE                                MIT
```

## Credits

- [microsoft/markitdown](https://github.com/microsoft/markitdown) — the conversion engine, MIT-licensed
- App icon: gradient "MARK" document logo, original to this repo

## License

MIT. See `LICENSE`.
