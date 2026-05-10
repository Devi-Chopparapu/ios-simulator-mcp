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

    let port = args?["port"]?.doubleValue.map { Int($0) } ?? args?["port"]?.intValue ?? 8100

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
    await wdaManager.stop()
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

func pressButton(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let name = args?["name"]?.stringValue else {
        return .text("Error: 'name' is required (home, volumeup, volumedown, lock, siri).")
    }
    let valid = ["home", "volumeup", "volumedown", "lock", "siri"]
    guard valid.contains(name) else {
        return .text("Error: invalid button '\(name)'. Valid options: \(valid.joined(separator: ", "))")
    }
    try await wdaManager.pressButton(name)
    return .text("Pressed button: \(name)")
}

// MARK: - shake

func shake(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    try await wdaManager.shake()
    return .text("Shake gesture performed.")
}

// MARK: - ui_describe_all

func uiDescribeAll(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    let source = try await wdaManager.uiSource()
    return .text(source)
}

// MARK: - ui_describe_point

func uiDescribePoint(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let x = args?["x"]?.numericDoubleValue, let y = args?["y"]?.numericDoubleValue else {
        return .text("Error: 'x' and 'y' are required.")
    }
    let result = try await wdaManager.describeElement(x: x, y: y)
    return .text(result)
}

// CallTool.Result.text() is defined in ToolHelpers.swift
// launch_app and terminate_app are implemented in SimctlTools.swift (no WDA dependency).
