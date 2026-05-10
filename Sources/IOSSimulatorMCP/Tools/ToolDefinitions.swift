import MCP

enum ToolDefinitions {
    static let allTools: [Tool] = simctlTools + wdaTools

    // MARK: - xcrun simctl tools

    private static let simctlTools: [Tool] = [
        Tool(
            name: "list_simulators",
            description: "List all available iOS simulators and their state.",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        ),
        Tool(
            name: "get_booted_sim_id",
            description: "Get the UDID of the currently booted simulator.",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        ),
        Tool(
            name: "boot_simulator",
            description: "Boot a simulator. Provide udid or name (e.g. 'iPhone 16 Pro'). Waits until fully booted.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "udid": .object(["type": .string("string")]),
                    "name": .object(["type": .string("string")]),
                ]),
            ])
        ),
        Tool(
            name: "open_simulator",
            description: "Open Simulator.app so the window becomes visible.",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        ),
        Tool(
            name: "get_device_info",
            description: "Get name, OS, state, and type of the booted simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "udid": .object(["type": .string("string")]),
                ]),
            ])
        ),
        Tool(
            name: "screenshot",
            description: "Screenshot the simulator. Default: JPEG at scale=0.3 (low token cost). Use save_to_path to write to disk and return the path only — no image data in context (zero vision tokens).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "udid":         .object(["type": .string("string")]),
                    "type":         .object(["type": .string("string"), "description": .string("jpeg (default) or png")]),
                    "scale":        .object(["type": .string("number"), "description": .string("0–1, default 0.3. Use 1.0 for native resolution.")]),
                    "save_to_path": .object(["type": .string("string"), "description": .string("Save to this path and return path only (0 vision tokens).")]),
                ]),
            ])
        ),
        Tool(
            name: "record_video",
            description: "Start recording the simulator screen. Default output: ~/Movies/recording.mov. Use .mov for QuickTime. Call stop_recording when done.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "output_path": .object(["type": .string("string"), "description": .string("Default: ~/Movies/recording.mov")]),
                    "udid":        .object(["type": .string("string")]),
                    "codec":       .object(["type": .string("string"), "description": .string("h264 (default) or hevc")]),
                ]),
            ])
        ),
        Tool(
            name: "stop_recording",
            description: "Stop the current screen recording and return the file path.",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        ),
        Tool(
            name: "set_location",
            description: "Set a simulated GPS location on the simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "latitude":  .object(["type": .string("number")]),
                    "longitude": .object(["type": .string("number")]),
                    "udid":      .object(["type": .string("string")]),
                ]),
                "required": .array([.string("latitude"), .string("longitude")]),
            ])
        ),
        Tool(
            name: "clear_location",
            description: "Clear the simulated GPS location.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "udid": .object(["type": .string("string")]),
                ]),
            ])
        ),
        Tool(
            name: "install_app",
            description: "Install an .app bundle onto the simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_path": .object(["type": .string("string")]),
                    "udid":     .object(["type": .string("string")]),
                ]),
                "required": .array([.string("app_path")]),
            ])
        ),
        Tool(
            name: "open_url",
            description: "Open a URL in the simulator (http/https or custom schemes).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "url":  .object(["type": .string("string")]),
                    "udid": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("url")]),
            ])
        ),
        Tool(
            name: "wait",
            description: "Wait N seconds (default 1). Useful for animations to settle.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "seconds": .object(["type": .string("number")]),
                ]),
            ])
        ),
    ]

    // MARK: - WebDriverAgent tools

    private static let wdaTools: [Tool] = [
        Tool(
            name: "start_wda",
            description: "Pre-warm WebDriverAgent. Optional — UI tools (tap, swipe, etc.) auto-start WDA on first use.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "wda_project_path": .object(["type": .string("string"), "description": .string("Path to WebDriverAgent.xcodeproj (default: bundled Vendor/WebDriverAgent)")]),
                    "udid": .object(["type": .string("string")]),
                    "port": .object(["type": .string("number"), "description": .string("Default 8100")]),
                ]),
            ])
        ),
        Tool(
            name: "stop_wda",
            description: "Stop WebDriverAgent. Optional — only needed to explicitly free resources.",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        ),
        Tool(
            name: "tap_element",
            description: "Find a UI element by label/name/accessibility ID and tap it — no coordinates needed. Prefer over screenshot→estimate→tap.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object(["type": .string("string"), "description": .string("Case-insensitive label, name, or value to match. E.g. 'Start Walk', 'Continue'")]),
                ]),
                "required": .array([.string("query")]),
            ])
        ),
        Tool(
            name: "find_element",
            description: "Find visible UI elements matching a label/name — returns type, label, and coordinates without tapping.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object(["type": .string("string"), "description": .string("Case-insensitive label, name, or value to match.")]),
                ]),
                "required": .array([.string("query")]),
            ])
        ),
        Tool(
            name: "tap",
            description: "Tap at x,y coordinates.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "x": .object(["type": .string("number")]),
                    "y": .object(["type": .string("number")]),
                ]),
                "required": .array([.string("x"), .string("y")]),
            ])
        ),
        Tool(
            name: "long_press",
            description: "Long-press at x,y for a given duration.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "x":        .object(["type": .string("number")]),
                    "y":        .object(["type": .string("number")]),
                    "duration": .object(["type": .string("number"), "description": .string("Seconds, default 1.0")]),
                ]),
                "required": .array([.string("x"), .string("y")]),
            ])
        ),
        Tool(
            name: "swipe",
            description: "Swipe from (from_x, from_y) to (to_x, to_y).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "from_x":   .object(["type": .string("number")]),
                    "from_y":   .object(["type": .string("number")]),
                    "to_x":     .object(["type": .string("number")]),
                    "to_y":     .object(["type": .string("number")]),
                    "duration": .object(["type": .string("number"), "description": .string("Seconds, default 0.5")]),
                ]),
                "required": .array([.string("from_x"), .string("from_y"), .string("to_x"), .string("to_y")]),
            ])
        ),
        Tool(
            name: "type_text",
            description: "Type text into the currently focused field.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "text": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("text")]),
            ])
        ),
        Tool(
            name: "tap_and_type",
            description: "Tap x,y to focus a field, then type text.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "x":    .object(["type": .string("number")]),
                    "y":    .object(["type": .string("number")]),
                    "text": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("x"), .string("y"), .string("text")]),
            ])
        ),
        Tool(
            name: "press_button",
            description: "Press a hardware button. home/action via WDA; lock/siri via Simulator menu (requires Accessibility permission).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object(["type": .string("string"), "description": .string("home | action | lock | siri")]),
                ]),
                "required": .array([.string("name")]),
            ])
        ),
        Tool(
            name: "shake",
            description: "Shake the device (uses Simulator.app menu via AppleScript — requires Accessibility permission).",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        ),
        Tool(
            name: "ui_describe_all",
            description: "List all UI elements on screen as compact text. Pass raw=true for full WDA XML.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "raw": .object(["type": .string("boolean")]),
                ]),
            ])
        ),
        Tool(
            name: "ui_describe_point",
            description: "Describe the UI element at x,y.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "x": .object(["type": .string("number")]),
                    "y": .object(["type": .string("number")]),
                ]),
                "required": .array([.string("x"), .string("y")]),
            ])
        ),
        Tool(
            name: "find_app",
            description: "Find an installed app by display name (case-insensitive) and return its bundle ID. If not found, tell the user — do not build or install.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object(["type": .string("string"), "description": .string("Display name, e.g. 'Safari'. Case-insensitive substring match.")]),
                    "udid": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("name")]),
            ])
        ),
        Tool(
            name: "launch_app",
            description: "Launch an app by bundle_id (e.g. com.example.App) or name (display name). If not found, tell the user — do not build or install.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object(["type": .string("string")]),
                    "name":      .object(["type": .string("string")]),
                    "udid":      .object(["type": .string("string")]),
                ]),
            ])
        ),
        Tool(
            name: "terminate_app",
            description: "Terminate a running app by bundle ID.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object(["type": .string("string")]),
                    "udid":      .object(["type": .string("string")]),
                ]),
                "required": .array([.string("bundle_id")]),
            ])
        ),
    ]
}
