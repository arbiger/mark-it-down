#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

sources=()
while IFS= read -r -d '' file; do
    sources+=("$file")
done < <(find Sources/MarkItDown -name '*.swift' ! -name 'MarkItDownApp.swift' -print0)

mkdir -p .build/manual-tests
swiftc -parse-as-library \
    "${sources[@]}" \
    Tests/MarkItDownTests/*.swift \
    -o .build/manual-tests/MarkItDownTests

.build/manual-tests/MarkItDownTests
