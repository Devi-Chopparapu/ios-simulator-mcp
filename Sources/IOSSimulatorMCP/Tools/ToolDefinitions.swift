import MCP

enum ToolDefinitions {
    static let allTools: [Tool] = simctlTools + wdaTools

    // MARK: - xcrun simctl tools

    private static let simctlTools: [Tool] = [
        Tool(
            name: "list_simulators",
            description: "List all available iOS simulators and their current state.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ])
        ),
        Tool(
            name: "get_booted_sim_id",
            description: "Get the UDID of the currently booted iOS simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ])
        ),
        Tool(
            name: "boot_simulator",
            description: "Boot an iOS simulator and wait until it is fully ready. Provide 'udid' (preferred) or 'name' — at least one is required. Blocks until the simulator reaches Booted state (up to 2 minutes).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "udid": .object(["type": .string("string"), "description": .string("Simulator UDID to boot")]),
                    "name": .object(["type": .string("string"), "description": .string("Simulator name to boot (e.g. 'iPhone 16 Pro'). Used if udid not provided.")]),
                ]),
            ])
        ),
        Tool(
            name: "open_simulator",
            description: "Open the Simulator.app so the simulator window becomes visible.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ])
        ),
        Tool(
            name: "get_device_info",
            description: "Get detailed info about the currently booted simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "udid": .object(["type": .string("string"), "description": .string("Simulator UDID (optional, uses booted sim)")]),
                ]),
            ])
        ),
        Tool(
            name: "screenshot",
            description: "Take a screenshot of the iOS simulator screen and return the image. Downscaled by default (scale=0.5) to reduce vision token cost — pass scale=1.0 for native resolution.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "udid":  .object(["type": .string("string"), "description": .string("Simulator UDID (optional, uses booted sim)")]),
                    "type":  .object(["type": .string("string"), "description": .string("Image format: 'png' (default) or 'jpeg'")]),
                    "scale": .object(["type": .string("number"), "description": .string("Downsample factor 0–1 (default 0.5). 0.5 on a 3× Retina device ≈ 1.5× logical points, ~4× fewer tokens. Use 1.0 for native resolution.")]),
                ]),
            ])
        ),
        Tool(
            name: "record_video",
            description: "Start recording the simulator screen to a video file.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "output_path": .object(["type": .string("string"), "description": .string("Full path for the output video file (e.g. /tmp/recording.mp4)")]),
                    "udid": .object(["type": .string("string"), "description": .string("Simulator UDID (optional, uses booted sim)")]),
                    "codec": .object(["type": .string("string"), "description": .string("Video codec: 'h264' (default) or 'hevc'")]),
                ]),
                "required": .array([.string("output_path")]),
            ])
        ),
        Tool(
            name: "stop_recording",
            description: "Stop the current screen recording and return the output file path.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ])
        ),
        Tool(
            name: "set_location",
            description: "Set a simulated GPS location on the simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "latitude": .object(["type": .string("number"), "description": .string("Latitude in decimal degrees")]),
                    "longitude": .object(["type": .string("number"), "description": .string("Longitude in decimal degrees")]),
                    "udid": .object(["type": .string("string"), "description": .string("Simulator UDID (optional, uses booted sim)")]),
                ]),
                "required": .array([.string("latitude"), .string("longitude")]),
            ])
        ),
        Tool(
            name: "clear_location",
            description: "Clear the simulated GPS location and return to real location.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "udid": .object(["type": .string("string"), "description": .string("Simulator UDID (optional, uses booted sim)")]),
                ]),
            ])
        ),
        Tool(
            name: "install_app",
            description: "Install an .app bundle onto the simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_path": .object(["type": .string("string"), "description": .string("Path to the .app bundle to install")]),
                    "udid": .object(["type": .string("string"), "description": .string("Simulator UDID (optional, uses booted sim)")]),
                ]),
                "required": .array([.string("app_path")]),
            ])
        ),
        Tool(
            name: "open_url",
            description: "Open a URL in the simulator (supports http/https and custom URL schemes).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "url": .object(["type": .string("string"), "description": .string("URL to open")]),
                    "udid": .object(["type": .string("string"), "description": .string("Simulator UDID (optional, uses booted sim)")]),
                ]),
                "required": .array([.string("url")]),
            ])
        ),
        Tool(
            name: "wait",
            description: "Wait for a specified number of seconds (useful for letting animations settle). Defaults to 1 second.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "seconds": .object(["type": .string("number"), "description": .string("Number of seconds to wait (default 1)")]),
                ]),
            ])
        ),
    ]

    // MARK: - WebDriverAgent tools

    private static let wdaTools: [Tool] = [
        Tool(
            name: "start_wda",
            description: "Start WebDriverAgent on the simulator so UI interaction tools become available. wda_project_path defaults to the bundled Vendor/WebDriverAgent submodule.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "wda_project_path": .object(["type": .string("string"), "description": .string("Path to WebDriverAgent.xcodeproj (optional, defaults to bundled Vendor/WebDriverAgent)")]),
                    "udid": .object(["type": .string("string"), "description": .string("Simulator UDID (optional, uses booted sim)")]),
                    "port": .object(["type": .string("number"), "description": .string("WDA HTTP port (default 8100)")]),
                ]),
            ])
        ),
        Tool(
            name: "stop_wda",
            description: "Stop the running WebDriverAgent process.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ])
        ),
        Tool(
            name: "tap",
            description: "Tap at x,y coordinates on the iOS Simulator screen.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "x": .object(["type": .string("number"), "description": .string("X coordinate in points")]),
                    "y": .object(["type": .string("number"), "description": .string("Y coordinate in points")]),
                ]),
                "required": .array([.string("x"), .string("y")]),
            ])
        ),
        Tool(
            name: "long_press",
            description: "Long-press at x,y coordinates for a given duration.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "x": .object(["type": .string("number"), "description": .string("X coordinate in points")]),
                    "y": .object(["type": .string("number"), "description": .string("Y coordinate in points")]),
                    "duration": .object(["type": .string("number"), "description": .string("Duration in seconds (default 1.0)")]),
                ]),
                "required": .array([.string("x"), .string("y")]),
            ])
        ),
        Tool(
            name: "swipe",
            description: "Swipe from one coordinate to another on the simulator screen.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "from_x": .object(["type": .string("number"), "description": .string("Start X coordinate")]),
                    "from_y": .object(["type": .string("number"), "description": .string("Start Y coordinate")]),
                    "to_x": .object(["type": .string("number"), "description": .string("End X coordinate")]),
                    "to_y": .object(["type": .string("number"), "description": .string("End Y coordinate")]),
                    "duration": .object(["type": .string("number"), "description": .string("Swipe duration in seconds (default 0.5)")]),
                ]),
                "required": .array([.string("from_x"), .string("from_y"), .string("to_x"), .string("to_y")]),
            ])
        ),
        Tool(
            name: "type_text",
            description: "Type text into the currently focused text field.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "text": .object(["type": .string("string"), "description": .string("Text to type")]),
                ]),
                "required": .array([.string("text")]),
            ])
        ),
        Tool(
            name: "tap_and_type",
            description: "Tap a coordinate to focus a text field, then type text into it.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "x": .object(["type": .string("number"), "description": .string("X coordinate to tap")]),
                    "y": .object(["type": .string("number"), "description": .string("Y coordinate to tap")]),
                    "text": .object(["type": .string("string"), "description": .string("Text to type after tapping")]),
                ]),
                "required": .array([.string("x"), .string("y"), .string("text")]),
            ])
        ),
        Tool(
            name: "press_button",
            description: "Press a button on the simulator. Supported: 'home' and 'action' (via WDA); 'lock' and 'siri' (via Simulator.app menu bar — requires Accessibility permission). 'volumeup'/'volumedown' are not exposed by the simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object(["type": .string("string"), "description": .string("Button name: 'home', 'action', 'lock', or 'siri'")]),
                ]),
                "required": .array([.string("name")]),
            ])
        ),
        Tool(
            name: "shake",
            description: "Perform a shake gesture on the simulator (clicks Simulator.app's Device → Shake menu via AppleScript — requires Accessibility permission).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ])
        ),
        Tool(
            name: "ui_describe_all",
            description: "Get the UI elements on the current screen. Returns a compact text list by default (~90% fewer tokens than raw XML). Pass raw=true to get the full WDA XML for debugging.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "raw": .object(["type": .string("boolean"), "description": .string("Return full WDA XML instead of the compact list (default false)")]),
                ]),
            ])
        ),
        Tool(
            name: "ui_describe_point",
            description: "Describe the UI element at a given x,y coordinate.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "x": .object(["type": .string("number"), "description": .string("X coordinate")]),
                    "y": .object(["type": .string("number"), "description": .string("Y coordinate")]),
                ]),
                "required": .array([.string("x"), .string("y")]),
            ])
        ),
        Tool(
            name: "launch_app",
            description: "Launch an app by bundle ID using xcrun simctl (no WDA required).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object(["type": .string("string"), "description": .string("App bundle identifier (e.g. com.example.MyApp)")]),
                    "udid": .object(["type": .string("string"), "description": .string("Simulator UDID (optional, uses booted sim)")]),
                ]),
                "required": .array([.string("bundle_id")]),
            ])
        ),
        Tool(
            name: "terminate_app",
            description: "Terminate a running app by bundle ID using xcrun simctl (no WDA required).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object(["type": .string("string"), "description": .string("App bundle identifier to terminate")]),
                    "udid": .object(["type": .string("string"), "description": .string("Simulator UDID (optional, uses booted sim)")]),
                ]),
                "required": .array([.string("bundle_id")]),
            ])
        ),
    ]
}
