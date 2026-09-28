#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
CHECK_DIR="$(mktemp -d)"
cat "$PROJECT_ROOT/Sources/Parsec/Model/Constants.swift" "$PROJECT_ROOT/Sources/Parsec/Model/InputResolver.swift" "$PROJECT_ROOT/scripts/checks.swift" > "$CHECK_DIR/main.swift"
swiftc -Onone "$CHECK_DIR/main.swift" -o "$CHECK_DIR/checks" && "$CHECK_DIR/checks"
rm -rf "$CHECK_DIR"
