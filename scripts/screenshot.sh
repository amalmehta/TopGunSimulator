#!/bin/bash
# Launches the app with the given arguments and saves a window screenshot. Usage: scripts/screenshot.sh out.png [--start id] [--camera X]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$1"; shift
pkill -f "Top Gun Simulator.app" 2>/dev/null || true
sleep 1
"build/Top Gun Simulator.app/Contents/MacOS/Top Gun Simulator" -ApplePersistenceIgnoreState YES "$@" >/dev/null 2>&1 &
sleep "${WAIT:-6}"
ID=$(swift -e 'import CoreGraphics
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in l where (w[kCGWindowOwnerName as String] as? String) == "Top Gun Simulator" && (w[kCGWindowLayer as String] as? Int) == 0 { print(w[kCGWindowNumber as String]!); break }')
screencapture -x -o -l "$ID" "$OUT"
echo "$OUT"
