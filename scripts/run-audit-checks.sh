#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
AUDIT_DIR="$(mktemp -d)"
AUDIT_FOLDER="ParsecAudit-$(uuidgen)"
REPORT_DIR="$PROJECT_ROOT/.gstack/audit/evidence"
SERVER_PID=""
cleanup() {
    if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null || true; fi
    rm -rf "$AUDIT_DIR" "$HOME/Library/Application Support/$AUDIT_FOLDER" "$HOME/Library/WebKit/dev.tommy.parsec.audit/WebsiteDataStore"
}
trap cleanup EXIT
mkdir -p "$REPORT_DIR"
python3 "$PROJECT_ROOT/scripts/audit-server.py" "$AUDIT_DIR/port" &
SERVER_PID=$!
for attempt in {1..100}; do
    [ -s "$AUDIT_DIR/port" ] && break
    sleep 0.05
done
[ -s "$AUDIT_DIR/port" ]
python3 - "$PROJECT_ROOT" "$AUDIT_DIR" "$AUDIT_FOLDER" <<'PY'
from pathlib import Path
import sys
root, target = map(Path, sys.argv[1:3])
constants = (root / 'Sources/Parsec/Model/Constants.swift').read_text()
(target / 'Constants.swift').write_text(constants.replace('static let appFolderName = "Parsec"', 'static let appFolderName = "' + sys.argv[3] + '"'))
PY
APP_PATH="$AUDIT_DIR/ParsecAudit.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
SOURCES=("$PROJECT_ROOT"/Sources/Parsec/**/*.swift)
SOURCES=("${(@)SOURCES:#*/App/main.swift}")
SOURCES=("${(@)SOURCES:#*/Model/Constants.swift}")
swiftc -swift-version 5 -parse-as-library -Onone -lsqlite3 "${SOURCES[@]}" "$AUDIT_DIR/Constants.swift" "$PROJECT_ROOT/scripts/audit-checks.swift" -o "$APP_PATH/Contents/MacOS/ParsecAudit"
cp -R "$PROJECT_ROOT/Support/Resources/." "$APP_PATH/Contents/Resources/"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string dev.tommy.parsec.audit' "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string ParsecAudit' "$APP_PATH/Contents/Info.plist"
codesign --force --sign - "$APP_PATH"
PARSEC_AUDIT_URL="http://127.0.0.1:$(cat "$AUDIT_DIR/port")" PARSEC_AUDIT_REPORT_DIR="$REPORT_DIR" "$APP_PATH/Contents/MacOS/ParsecAudit" | tee "$REPORT_DIR/checks.txt"
