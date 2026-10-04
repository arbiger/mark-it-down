import json, sys
from pdf_inspector import process_pdf

def main():
    if len(sys.argv) != 3:
        return 2
    source, temp = sys.argv[1], sys.argv[2]
    result = process_pdf(source)
    classification = getattr(result, "pdf_type", "unknown")
    pages = list(getattr(result, "pages_needing_ocr", []) or [])
    markdown = getattr(result, "markdown", None)
    written = False
    if markdown and markdown.strip():
        with open(temp, "w", encoding="utf-8") as f:
            f.write(markdown)
        written = True
    print(json.dumps({"schemaVersion": 1, "classification": classification, "pagesNeedingOCR": pages, "encodingSuspect": bool(getattr(result, "has_encoding_issues", False)), "markdownWritten": written}))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
