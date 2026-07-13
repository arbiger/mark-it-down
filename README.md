# Mark-It-Down

A native macOS app that converts a folder of documents to Markdown using [markitdown](https://github.com/microsoft/markitdown).

Drag a folder in. Click Start. Get `.md` files next to the originals.

## Features

- Drag-and-drop a folder, recursive scan
- Supports PDF, DOCX, PPTX, XLSX, HTML, images (with OCR), audio (with transcription), and more
- Output never overwrites — collisions get `(N)` suffixes
- Up to 4 parallel conversions
- Native SwiftUI app, no Electron

## Requirements

- macOS 14 (Sonoma) or later
- Python 3.10 or later (Homebrew recommended)
- Internet access on first run (to install `markitdown[all]`)

## Install

```
git clone <your-fork-url> Mark-It-Down
cd Mark-It-Down
./make-app.sh release
open Mark-It-Down.app
```

Drag `Mark-It-Down.app` to `/Applications` if you want it installed permanently.

If macOS Gatekeeper blocks the first launch, right-click the app -> Open, or run:

```
xattr -dr com.apple.quarantine Mark-It-Down.app
```

## Usage

1. Launch `Mark-It-Down.app`.
2. On first run, the app installs `markitdown[all]` (~150 MB) automatically.
3. Drag a folder onto the drop zone, or click to pick one.
4. Review the file list. Click **Start**.
5. When done, click **Show in Finder** to see the output.

## Development

```
./run-dev.sh          # swift run for development
swift build           # compile only
```

## Acknowledgements

Powered by Microsoft's [markitdown](https://github.com/microsoft/markitdown). This app is not affiliated with or endorsed by Microsoft.