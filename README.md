# Mark-It-Down

A native macOS app that converts documents to Markdown using [Firecrawl PDF Inspector](https://github.com/firecrawl/pdf-inspector) for PDFs and [Microsoft MarkItDown](https://github.com/microsoft/markitdown) for other supported formats. Drag one or more files, folders, or a mixture onto the window, click **Start**, and the `.md` files land next to the originals.

This is a personal-use SwiftUI app with a local hybrid conversion backend. It exists to make batch conversions frictionless: drop, click, done. Outputs never overwrite — collisions get `(N)` suffixes.

Both upstream engines are MIT-licensed. This project is **not** affiliated with or endorsed by Microsoft or Firecrawl; see `THIRD_PARTY_NOTICES.md`.

## What it does

- Drag-and-drop one or more **files** (only those files are selected), **folders** (recursive scan), or a mixture of both
- Routes native-text PDFs through fast, local PDF Inspector extraction
- Rejects scanned, image-only, or mixed PDFs that need OCR instead of silently writing incomplete Markdown
- Uses MarkItDown for DOCX, PPTX, XLSX, HTML, EPUB, CSV, JSON, XML, images, audio, archives, and other supported formats
- Output written next to each source — `foo.pdf` becomes `foo.md` in the same folder
- Never overwrites: existing and same-batch collisions get `(N)` suffixes
- Detects empty conversions and reports the PDF pages that need OCR when available
- Up to 4 parallel conversions via Swift `actor` + `TaskGroup`
- Stop cancels active subprocesses instead of leaving conversions running
- Native SwiftUI, no Electron

## Requirements

- macOS 14 (Sonoma) or later
- Python 3.10–3.13 somewhere on the system (Homebrew recommended, or any venv)
- Internet access on first run to prepare the app-private conversion environment

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

1. Locates a Python 3.10–3.13 interpreter to create a virtual environment. Python 3.14 is currently excluded because the pinned MarkItDown dependency set does not install successfully on it.
2. Creates or repairs `~/Library/Application Support/Mark-It-Down/runtime/venv`.
3. Installs the direct pins from `Resources/requirements-macos.txt`: `markitdown[all]==0.1.7` and `pdf-inspector==0.2.6`.
4. Verifies both exact versions before enabling conversion.

The app does not install into user-global or system Python. Once the private environment is ready, ordinary local conversions can run offline. A later dependency repair or reinstall requires internet access.

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
├── Tests/
│   ├── MarkItDownTests/                 Native automated core tests
│   └── ManualFixtures/                  ignored large/private manual fixtures
├── Resources/                             Info.plist template, AppIcon.icns
│   ├── markitdown_pdf_inspector.py     Versioned PDF helper contract
│   └── requirements-macos.txt          Direct dependency pins
├── scripts/                               Metadata-only benchmark harness
├── docs/                                  Designs, plans, and benchmark evidence
├── dist/                                  ignored local release artifacts
├── make-app.sh                            build → wrap into .app → codesign
├── run-dev.sh                             swift run wrapper
├── run-tests.sh                           compile and run automated tests
├── README.md                              this file
└── LICENSE                                MIT
```

## Credits

- [microsoft/markitdown](https://github.com/microsoft/markitdown) — the conversion engine, MIT-licensed
- [firecrawl/pdf-inspector](https://github.com/firecrawl/pdf-inspector) — PDF classification and structured extraction, MIT-licensed
- App icon: gradient "MARK" document logo, original to this repo

## License

MIT. See `LICENSE` and `THIRD_PARTY_NOTICES.md`.
