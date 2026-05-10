import Foundation
import MCP

// MARK: - start_wda

/// Resolves the WDA project path: explicit arg > Vendor submodule next to binary > error.
private func resolveWDAPath(_ args: [String: Value]?) -> String? {
    if let explicit = args?["wda_project_path"]?.stringValue { return explicit }
    // CommandLine.arguments[0] is the running binary path — works on any machine.
    // Binary lives at <repo>/.build/release/ios-simulator-mcp, so repo root is 3 levels up.
    let binaryURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let repoRoot = binaryURL
        .deletingLastPathComponent()  // ios-simulator-mcp
        .deletingLastPathComponent()  // release/
        .deletingLastPathComponent()  // .build/
    let vendored = repoRoot.appendingPathComponent("Vendor/WebDriverAgent/WebDriverAgent.xcodeproj").path
    return FileManager.default.fileExists(atPath: vendored) ? vendored : nil
}

func startWDA(_ args: [String: Value]?, simManager: SimulatorManager, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let wdaPath = resolveWDAPath(args) else {
        return .text("Error: 'wda_project_path' not specified and Vendor/WebDriverAgent submodule not found. Run Scripts/setup.sh first.")
    }

    let udid: String
    if let provided = args?["udid"]?.stringValue {
        udid = provided
    } else {
        udid = try await simManager.bootedUDID()
    }

    let port = args?["port"]?.numericDoubleValue.map(Int.init) ?? 8100

    try await wdaManager.start(udid: udid, wdaProjectPath: wdaPath, port: port)
    try await wdaManager.waitForReady()

    // Eagerly create a WDA session now so the first tap/swipe doesn't have to wait,
    // and so any session-creation failure surfaces here with a clear error rather than
    // appearing as a confusing "WDA not started" failure inside a later interaction tool.
    let sid = try await wdaManager.session()
    log("[WDA] Session ready: \(sid)")

    return .text("WDA started and ready on port \(port) for simulator \(udid)")
}

// MARK: - stop_wda

func stopWDA(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    await wdaManager.stop()  // now async — waits for xcodebuild to fully exit
    return .text("WDA stopped.")
}

// MARK: - tap

func tap(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let x = args?["x"]?.numericDoubleValue, let y = args?["y"]?.numericDoubleValue else {
        return .text("Error: 'x' and 'y' are required.")
    }
    try await wdaManager.tap(x: x, y: y)
    return .text("Tapped at (\(x), \(y))")
}

// MARK: - long_press

func longPress(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let x = args?["x"]?.numericDoubleValue, let y = args?["y"]?.numericDoubleValue else {
        return .text("Error: 'x' and 'y' are required.")
    }
    let duration = args?["duration"]?.numericDoubleValue ?? 1.0
    try await wdaManager.longPress(x: x, y: y, durationSeconds: duration)
    return .text("Long-pressed at (\(x), \(y)) for \(duration)s")
}

// MARK: - swipe

func swipe(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let fromX = args?["from_x"]?.numericDoubleValue,
          let fromY = args?["from_y"]?.numericDoubleValue,
          let toX   = args?["to_x"]?.numericDoubleValue,
          let toY   = args?["to_y"]?.numericDoubleValue else {
        return .text("Error: 'from_x', 'from_y', 'to_x', and 'to_y' are required.")
    }
    let duration = args?["duration"]?.numericDoubleValue ?? 0.5
    try await wdaManager.swipe(fromX: fromX, fromY: fromY, toX: toX, toY: toY, durationSeconds: duration)
    return .text("Swiped from (\(fromX), \(fromY)) to (\(toX), \(toY))")
}

// MARK: - type_text

func typeText(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let text = args?["text"]?.stringValue else {
        return .text("Error: 'text' is required.")
    }
    try await wdaManager.typeText(text)
    return .text("Typed: \(text)")
}

// MARK: - tap_and_type

func tapAndType(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let x    = args?["x"]?.numericDoubleValue,
          let y    = args?["y"]?.numericDoubleValue,
          let text = args?["text"]?.stringValue else {
        return .text("Error: 'x', 'y', and 'text' are required.")
    }
    try await wdaManager.tap(x: x, y: y)
    try await Task.sleep(for: .milliseconds(300))
    try await wdaManager.typeText(text)
    return .text("Tapped (\(x), \(y)) and typed: \(text)")
}

// MARK: - press_button

/// Press a button on the simulator.
///
/// The iOS Simulator only virtualises a tiny subset of physical buttons:
///   - `home`, `action` — handled by WDA's pressButton endpoint (works in-process)
///   - `lock`, `siri`   — only reachable via the Simulator.app menu bar (AppleScript)
///   - `volumeup`, `volumedown` — not exposed by anything (no menu item, no simctl,
///     no WDA support); we return a clear error rather than failing opaquely.
func pressButton(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let raw = args?["name"]?.stringValue else {
        return .text("Error: 'name' is required (home, action, lock, siri).")
    }
    let name = raw.lowercased()

    switch name {
    case "home", "action":
        try await wdaManager.pressButton(name)
        return .text("Pressed button: \(name)")

    case "lock":
        try await clickSimulatorMenuItem([
            (menu: "Device",   item: "Lock"),
            (menu: "Hardware", item: "Lock Screen"),
        ])
        return .text("Pressed button: lock (via Simulator menu bar)")

    case "siri":
        try await clickSimulatorMenuItem([
            (menu: "Device",   item: "Siri"),
            (menu: "Features", item: "Siri"),
            (menu: "Hardware", item: "Siri"),
        ])
        return .text("Pressed button: siri (via Simulator menu bar)")

    case "volumeup", "volumedown":
        return .text("""
            Error: '\(name)' is not supported on the iOS Simulator. Volume hardware buttons \
            are not exposed by simctl, WebDriverAgent, or the Simulator menu bar in modern \
            Xcode. Use a real device for volume-button testing.
            """)

    default:
        return .text("Error: invalid button '\(raw)'. Valid: home, action, lock, siri.")
    }
}

// MARK: - shake

/// Shake gesture. WDA v12.2.2 has no `/wda/shake` endpoint, and simctl has no shake
/// command, so we drive it via Simulator.app's menu bar (Device → Shake on modern
/// Xcode, Hardware → Shake Device on older versions).
func shake(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    try await clickSimulatorMenuItem([
        (menu: "Device",   item: "Shake"),
        (menu: "Hardware", item: "Shake Device"),
        (menu: "Hardware", item: "Shake Gesture"),
    ])
    return .text("Shake gesture performed (via Simulator menu bar).")
}

// MARK: - ui_describe_all

func uiDescribeAll(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    let source = try await wdaManager.uiSource()
    // Default: compact text list (~90% fewer tokens than raw XML).
    // Pass raw=true to get the full WDA XML for debugging or fine-grained parsing.
    let raw = args?["raw"]?.boolValue ?? false
    return .text(raw ? source : WDAManager.compactUISource(source))
}

// MARK: - ui_describe_point

func uiDescribePoint(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let x = args?["x"]?.numericDoubleValue, let y = args?["y"]?.numericDoubleValue else {
        return .text("Error: 'x' and 'y' are required.")
    }
    let result = try await wdaManager.describeElement(x: x, y: y)
    return .text(result)
}

// MARK: - tap_element

/// Find the first visible element whose name/label/value contains the query and tap its centre.
/// Much more reliable than screenshot → estimate coordinates → tap.
func tapElement(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let query = args?["query"]?.stringValue, !query.isEmpty else {
        return .text("Error: 'query' is required.")
    }
    let result = try await wdaManager.tapElement(matching: query)
    return .text(result)
}

// MARK: - find_element

/// Find visible elements matching a query — returns their coordinates without tapping.
func findElement(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let query = args?["query"]?.stringValue, !query.isEmpty else {
        return .text("Error: 'query' is required.")
    }
    let result = try await wdaManager.findElement(matching: query)
    return .text(result)
}

// CallTool.Result.text() is defined in ToolHelpers.swift
// launch_app and terminate_app are implemented in SimctlTools.swift (no WDA dependency).
