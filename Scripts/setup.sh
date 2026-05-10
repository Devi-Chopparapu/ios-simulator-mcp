#!/usr/bin/env bash
# setup.sh — one-time setup for ios-simulator-mcp
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
WDA_DIR="$REPO_DIR/Vendor/WebDriverAgent"

echo "=== ios-simulator-mcp setup ==="

# ── 1. Check Xcode ────────────────────────────────────────────────────────────
if ! command -v xcrun &>/dev/null; then
  echo "❌  Xcode Command Line Tools not found. Install with: xcode-select --install"
  exit 1
fi
echo "✅  Xcode: $(xcrun --version 2>&1 | head -1)"

if ! command -v xcodebuild &>/dev/null; then
  echo "❌  xcodebuild not found. Install Xcode from the App Store."
  exit 1
fi
echo "✅  xcodebuild: $(xcodebuild -version | head -1)"

# ── 2. Init submodule (handles both fresh clone and missing --recurse-submodules) ──
echo "📦  Initialising WebDriverAgent submodule (v12.2.2)..."
git -C "$REPO_DIR" submodule update --init --recursive
echo "✅  WebDriverAgent ready at $WDA_DIR"

# ── 3. Bootstrap WDA dependencies ─────────────────────────────────────────────
if [ -f "$WDA_DIR/Scripts/bootstrap.sh" ]; then
  echo "🔧  Running WDA bootstrap (Carthage/SPM deps)..."
  pushd "$WDA_DIR" > /dev/null
  bash Scripts/bootstrap.sh
  popd > /dev/null
  echo "✅  WDA bootstrap complete"
else
  echo "ℹ️   No bootstrap.sh found — WDA uses SPM only, no extra step needed"
fi

# ── 4. Optional: libimobiledevice for real device support ─────────────────────
if command -v brew &>/dev/null; then
  if ! command -v iproxy &>/dev/null; then
    echo "📦  Installing libimobiledevice (needed for real device USB port-forward)..."
    brew install libimobiledevice
  else
    echo "✅  libimobiledevice already installed"
  fi
else
  echo "ℹ️   Homebrew not found — skipping libimobiledevice (only needed for real device)"
fi

# ── 5. Build the MCP server ───────────────────────────────────────────────────
echo "🔨  Building ios-simulator-mcp (release)..."
cd "$REPO_DIR"
swift build -c release

BINARY="$REPO_DIR/.build/release/ios-simulator-mcp"
echo ""
echo "✅  Build complete!"
echo ""
echo "=== Next steps ==="
echo ""
echo "1. Add to Claude Code:"
echo "   claude mcp add ios-simulator -- $BINARY"
echo ""
echo "2. Or add to Claude Desktop (~/.../claude_desktop_config.json):"
cat <<JSON
   {
     "mcpServers": {
       "ios-simulator": {
         "command": "$BINARY"
       }
     }
   }
JSON
echo ""
echo "3. Boot a simulator in Xcode, then call the 'start_wda' tool — no arguments needed."
