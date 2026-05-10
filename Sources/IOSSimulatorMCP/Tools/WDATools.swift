import Foundation
import MCP

// MARK: - start_wda

/// Resolves the WDA project path: explicit arg > Vendor submodule > error.
private func resolveWDAPath(_ args: [String: Value]?) -> String? {
    if let explicit = args?["wda_project_path"]?.stringValue { return explicit }
    let scriptDir = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()   // Tools/
        .deletingLastPathComponent()   // IOSSimulatorMCP/
        .deletingLastPathComponent()   // Sources/
        .deletingLastPathComponent()   // repo root
    let vendored = scriptDir.appendingPathComponent("Vendor/WebDriverAgent/WebDriverAgent.xcodeproj").path
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

    let port = args?["port"]?.intValue ?? 8100

    try await wdaManager.start(udid: udid, wdaProjectPath: wdaPath, port: port)
    try await wdaManager.waitForReady()
    return .text("WDA started and ready on port \(port) for simulator \(udid)")
}

// MARK: - stop_wda

func stopWDA(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    await wdaManager.stop()
    return .text("WDA stopped.")
}

// MARK: - tap

func tap(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let x = args?["x"]?.doubleValue, let y = args?["y"]?.doubleValue else {
        return .text("Error: 'x' and 'y' are required.")
    }
    try await wdaManager.tap(x: x, y: y)
    return .text("Tapped at (\(x), \(y))")
}

// MARK: - long_press

func longPress(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let x = args?["x"]?.doubleValue, let y = args?["y"]?.doubleValue else {
        return .text("Error: 'x' and 'y' are required.")
    }
    let duration = args?["duration"]?.doubleValue ?? 1.0
    try await wdaManager.longPress(x: x, y: y, durationSeconds: duration)
    return .text("Long-pressed at (\(x), \(y)) for \(duration)s")
}

// MARK: - swipe

func swipe(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let fromX = args?["from_x"]?.doubleValue,
          let fromY = args?["from_y"]?.doubleValue,
          let toX   = args?["to_x"]?.doubleValue,
          let toY   = args?["to_y"]?.doubleValue else {
        return .text("Error: 'from_x', 'from_y', 'to_x', and 'to_y' are required.")
    }
    let duration = args?["duration"]?.doubleValue ?? 0.5
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
    guard let x    = args?["x"]?.doubleValue,
          let y    = args?["y"]?.doubleValue,
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
    guard let x = args?["x"]?.doubleValue, let y = args?["y"]?.doubleValue else {
        return .text("Error: 'x' and 'y' are required.")
    }
    let result = try await wdaManager.describeElement(x: x, y: y)
    return .text(result)
}

// MARK: - launch_app

func launchApp(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let bundleId = args?["bundle_id"]?.stringValue else {
        return .text("Error: 'bundle_id' is required.")
    }
    try await wdaManager.launchApp(bundleId: bundleId)
    return .text("Launched app: \(bundleId)")
}

// MARK: - terminate_app

func terminateApp(_ args: [String: Value]?, wdaManager: WDAManager) async throws -> CallTool.Result {
    guard let bundleId = args?["bundle_id"]?.stringValue else {
        return .text("Error: 'bundle_id' is required.")
    }
    try await wdaManager.terminateApp(bundleId: bundleId)
    return .text("Terminated app: \(bundleId)")
}

// MARK: - Convenience extension

private extension CallTool.Result {
    static func text(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: false)
    }
}
