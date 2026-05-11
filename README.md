# ios-simulator-mcp

![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![Platform](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)
![MCP](https://img.shields.io/badge/MCP-compatible-6B4FBB)
![Transport](https://img.shields.io/badge/transport-stdio-lightgrey)

A Swift MCP server that lets AI assistants control the iOS Simulator via the [Model Context Protocol](https://modelcontextprotocol.io). Built on the official [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) over stdio.

```
Claude / MCP Client
       │  JSON-RPC (stdio)
       ▼
ios-simulator-mcp  ──→  xcrun simctl     (boot, screenshot, video, location, install)
                   ──→  WebDriverAgent   (tap, swipe, type, inspect UI)
```

---

## Requirements

- **Xcode** (with Command Line Tools) — provides `xcrun`, `xcodebuild`, `simctl`
- **macOS 13+**

---

## Setup

```bash
# Clone with submodules (WebDriverAgent is vendored at Vendor/WebDriverAgent)
git clone --recurse-submodules https://github.com/GovardhanaDevi/ios-simulator-mcp.git
cd ios-simulator-mcp

# One-time setup: bootstraps WDA and builds the release binary
bash Scripts/setup.sh
```

### Add to Claude Code

```bash
claude mcp add ios-simulator -- "$PWD/.build/release/ios-simulator-mcp"
```

### Add to Claude Desktop

`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "ios-simulator": {
      "command": "/path/to/ios-simulator-mcp/.build/release/ios-simulator-mcp"
    }
  }
}
```

### Build manually

```bash
swift build -c release
```

---

## Demo

https://github.com/GovardhanaDevi/ios-simulator-mcp/raw/main/presentation/Aruku_test_1080.mov
<img width="800" height="478" alt="Aruku_test_1080_new" src="https://github.com/user-attachments/assets/3c8cd5df-0bed-40da-92c5-13cd58715d55" />


---

## Usage

Boot a simulator in Xcode, connect this MCP, then just talk to Claude in plain English:

> *"Take a screenshot"*
> *"Open the My Weather app"*
> *"Tap the Sign In button"*
> *"Scroll down and tap Continue"*
> *"Record a demo of the app and save it to my Desktop"*
> *"What's on screen right now?"*
> *"Type 'hello@example.com' into the email field"*
> *"Simulate my location as Tokyo"*

Claude figures out which tools to use — you never need to know the tool names or coordinates.

---

## Available Tools for your AI

### Simulator

| Tool | Args | Description |
|---|---|---|
| `list_simulators` | — | List all simulators and their state |
| `get_booted_sim_id` | — | Get the UDID of the booted simulator |
| `boot_simulator` | `udid` or `name` | Boot a simulator and wait until ready |
| `open_simulator` | — | Bring Simulator.app to the foreground |
| `get_device_info` | `udid`? | Name, OS, UDID, state of the booted sim |

### Screen & Media

| Tool | Args | Description |
|---|---|---|
| `screenshot` | `type`?, `scale`?, `save_to_path`?, `udid`? | Capture screen. Default: JPEG at scale=0.3. Use `save_to_path` to write to disk without returning image data (0 vision tokens) |
| `record_video` | `output_path`?, `codec`?, `udid`? | Start recording. Default output: `~/Movies/recording.mov` |
| `stop_recording` | — | Stop recording and return the file path |

### App Control

| Tool | Args | Description |
|---|---|---|
| `find_app` | `name`, `udid`? | Find an installed app by display name, returns bundle ID |
| `launch_app` | `bundle_id` or `name`, `udid`? | Launch an app |
| `terminate_app` | `bundle_id`, `udid`? | Terminate a running app |
| `install_app` | `app_path`, `udid`? | Install a `.app` bundle |
| `open_url` | `url`, `udid`? | Open a URL or deep link |

### Device

| Tool | Args | Description |
|---|---|---|
| `set_location` | `latitude`, `longitude`, `udid`? | Simulate a GPS location |
| `clear_location` | `udid`? | Remove the simulated location |
| `wait` | `seconds`? (default 1) | Wait N seconds |
| `press_button` | `name` | `home`, `action`, `lock`, or `siri` |
| `shake` | — | Shake gesture |

### UI Interaction (WDA — auto-starts on first use)

| Tool | Args | Description |
|---|---|---|
| `tap_element` | `query` | Tap a UI element by label/name — no coordinates needed |
| `find_element` | `query` | Find elements by label/name, returns type and coordinates |
| `tap` | `x`, `y` | Tap at coordinates |
| `long_press` | `x`, `y`, `duration`? (default 1.0s) | Long-press at coordinates |
| `swipe` | `from_x`, `from_y`, `to_x`, `to_y`, `duration`? (default 0.5s) | Swipe |
| `type_text` | `text` | Type into the focused field |
| `tap_and_type` | `x`, `y`, `text` | Tap a field then type into it |
| `ui_describe_all` | `raw`? (default false) | Compact accessibility tree. Pass `raw=true` for full WDA XML |
| `ui_describe_point` | `x`, `y` | Describe the element at a coordinate |

### WDA Lifecycle (optional — managed automatically)

| Tool | Args | Description |
|---|---|---|
| `start_wda` | `wda_project_path`?, `udid`?, `port`? | Pre-warm WDA before first use |
| `stop_wda` | — | Stop the WDA process |

---

## How it works

- **`xcrun simctl`** — handles simulator management, screenshots, video, GPS, app install/launch. No WDA needed.
- **WebDriverAgent** — starts a local HTTP server (`localhost:8100`) exposing the XCTest accessibility API. Used for taps, swipes, text input, and UI inspection. **Auto-starts on first UI interaction** — you never need to call `start_wda` manually.

---

## License

WebDriverAgent is vendored as a submodule from [Appium](https://github.com/appium/WebDriverAgent), WebDriverAgent is [BSD-licensed](https://github.com/appium/WebDriverAgent/blob/master/LICENSE).
