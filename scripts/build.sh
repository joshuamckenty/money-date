#!/usr/bin/env bash
# Build money-date AND compile the Dopamine effect shaders.
#
# Why: the Dopamine effect packages ship their Metal shaders as raw `.metal`
# source via `.process("Shaders")`. Xcode compiles those into `default.metallib`,
# but plain `swift build` only copies them — so `makeDefaultLibrary(bundle:)`
# fails at runtime ("no default library was found") and effects don't render.
# Here we compile each effect bundle's umbrella shader into `default.metallib`
# after the Swift build. (Proper long-term fix belongs in the Dopamine library:
# ship a prebuilt default.metallib, or have it compile under SwiftPM.)
set -euo pipefail

CONFIG="${1:-debug}"
cd "$(dirname "$0")/.."

xcrun --toolchain default swift build -c "$CONFIG"

BINDIR=".build/$CONFIG"
for bundle in "$BINDIR"/Dopamine_DopamineEffect*.bundle; do
    [ -d "$bundle" ] || continue
    # The umbrella shader is the one that #includes the sibling .metal helpers.
    umbrella=$(grep -l '#include "' "$bundle"/*.metal 2>/dev/null | head -1 || true)
    [ -n "$umbrella" ] || continue
    air="$(mktemp -t money-date-metal).air"
    xcrun -sdk macosx metal -c "$umbrella" -o "$air"
    xcrun -sdk macosx metallib "$air" -o "$bundle/default.metallib"
    rm -f "$air"
    echo "compiled metallib for $(basename "$bundle")"
done

echo "Done. Run: $BINDIR/MoneyDate"
