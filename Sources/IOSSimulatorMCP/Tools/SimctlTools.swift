import Foundation
import MCP

// MARK: - list_simulators

func listSimulators(_ args: [String: Value]?) async throws -> CallTool.Result {
    let json: String
    do {
        json = try await shell("/usr/bin/xcrun", ["simctl", "list", "devices", "--json"], timeout: 20)
    } catch ShellError.timeout {
        return .text("""
            CoreSimulator timed out (>20s). The service may be stuck.
            Fix: run this in Terminal, then retry:
              sudo killall -9 com.apple.CoreSimulator.CoreSimulatorService
            Or open Xcode once to wake it up.
            """)
    }
    guard let data = json.data(using: .utf8) else {
        return .text("Failed to parse simulator list")
    }
    let list = try JSONDecoder().decode(SimctlDeviceList.self, from: data)

    var lines: [String] = []
    for (runtimeKey, devices) in list.devices.sorted(by: { $0.key < $1.key }) {
        let available = devices.filter { $0.isAvailable }
        guard !available.isEmpty else { continue }
        let osName = SimctlDevice.osName(from: runtimeKey)
        lines.append("\n\(osName):")
        for device in available {
            let status = device.isBooted ? " [BOOTED]" : ""
            lines.append("  \(device.name)\(status)")
            lines.append("    UDID: \(device.udid)")
        }
    }

    return .text(lines.isEmpty ? "No available simulators found." : lines.joined(separator: "\n"))
}

// MARK: - get_booted_sim_id

func getBootedSimId(_ args: [String: Value]?, manager: SimulatorManager) async throws -> CallTool.Result {
    let udid = try await manager.bootedUDID()
    return .text(udid)
}

// MARK: - boot_simulator

func bootSimulator(_ args: [String: Value]?, manager: SimulatorManager) async throws -> CallTool.Result {
    var udid = args?["udid"]?.stringValue

    if udid == nil, let name = args?["name"]?.stringValue {
        let json = try await shell("/usr/bin/xcrun", ["simctl", "list", "devices", "--json"])
        if let data = json.data(using: .utf8),
           let list = try? JSONDecoder().decode(SimctlDeviceList.self, from: data) {
            outer: for (_, devices) in list.devices {
                for device in devices where device.name == name && device.isAvailable {
                    udid = device.udid
                    break outer
                }
            }
        }
    }

    guard let targetUDID = udid else {
        return .text("Error: provide 'udid' or 'name' to identify the simulator to boot.")
    }

    _ = try await shell("/usr/bin/xcrun", ["simctl", "boot", targetUDID], timeout: 60)
    await manager.invalidateCache()
    return .text("Booted simulator \(targetUDID)")
}

// MARK: - open_simulator

func openSimulator(_ args: [String: Value]?) async throws -> CallTool.Result {
    _ = try await shell("/usr/bin/open", ["-a", "Simulator"])
    return .text("Simulator.app opened.")
}

// MARK: - get_device_info

func getDeviceInfo(_ args: [String: Value]?, manager: SimulatorManager) async throws -> CallTool.Result {
    let udid: String
    if let provided = args?["udid"]?.stringValue {
        udid = provided
    } else {
        udid = try await manager.bootedUDID()
    }

    let json = try await shell("/usr/bin/xcrun", ["simctl", "list", "devices", "booted", "--json"])
    guard let data = json.data(using: .utf8),
          let list = try? JSONDecoder().decode(SimctlDeviceList.self, from: data) else {
        return .text("Failed to parse device info")
    }

    for (runtimeKey, devices) in list.devices {
        if let device = devices.first(where: { $0.udid == udid }) {
            let os = SimctlDevice.osName(from: runtimeKey)
            var info = [
                "Name: \(device.name)",
                "UDID: \(device.udid)",
                "OS: \(os)",
                "State: \(device.state)",
            ]
            if let booted = device.lastBootedAt {
                info.append("Last Booted: \(booted)")
            }
            if let type_ = device.deviceTypeIdentifier {
                info.append("Type: \(type_)")
            }
            return .text(info.joined(separator: "\n"))
        }
    }
    return .text("Device \(udid) not found in booted simulators.")
}

// MARK: - screenshot

func screenshot(_ args: [String: Value]?, manager: SimulatorManager) async throws -> CallTool.Result {
    let udid: String
    if let provided = args?["udid"]?.stringValue {
        udid = provided
    } else {
        udid = try await manager.bootedUDID()
    }

    let format = args?["type"]?.stringValue ?? "png"
    let mimeType = format == "jpeg" ? "image/jpeg" : "image/png"
    let ext = format == "jpeg" ? "jpg" : "png"
    let outputPath = NSTemporaryDirectory() + "simulator_screenshot_\(UUID().uuidString).\(ext)"

    _ = try await shell("/usr/bin/xcrun", ["simctl", "io", udid, "screenshot", "--type", format, outputPath])

    guard let imageData = FileManager.default.contents(atPath: outputPath) else {
        return .text("Screenshot taken but could not read file at \(outputPath)")
    }
    try? FileManager.default.removeItem(atPath: outputPath)

    return CallTool.Result(
        content: [.image(data: imageData.base64EncodedString(), mimeType: mimeType, annotations: nil, _meta: nil)],
        isError: false
    )
}

// MARK: - record_video

func recordVideo(_ args: [String: Value]?, manager: SimulatorManager) async throws -> CallTool.Result {
    guard let outputPath = args?["output_path"]?.stringValue else {
        return .text("Error: 'output_path' is required.")
    }

    let udid: String
    if let provided = args?["udid"]?.stringValue {
        udid = provided
    } else {
        udid = try await manager.bootedUDID()
    }

    let codec = args?["codec"]?.stringValue ?? "h264"
    try await manager.startRecording(udid: udid, outputPath: outputPath, codec: codec)
    return .text("Recording started. Output: \(outputPath). Call stop_recording when done.")
}

// MARK: - stop_recording

func stopRecording(_ args: [String: Value]?, manager: SimulatorManager) async throws -> CallTool.Result {
    let path = try await manager.stopRecording()
    return .text("Recording saved to: \(path)")
}

// MARK: - set_location

func setLocation(_ args: [String: Value]?, manager: SimulatorManager) async throws -> CallTool.Result {
    guard let lat = args?["latitude"]?.doubleValue,
          let lng = args?["longitude"]?.doubleValue else {
        return .text("Error: 'latitude' and 'longitude' are required.")
    }

    let udid: String
    if let provided = args?["udid"]?.stringValue {
        udid = provided
    } else {
        udid = try await manager.bootedUDID()
    }

    _ = try await shell("/usr/bin/xcrun", ["simctl", "location", udid, "set", "\(lat),\(lng)"])
    return .text("Location set to \(lat), \(lng)")
}

// MARK: - clear_location

func clearLocation(_ args: [String: Value]?, manager: SimulatorManager) async throws -> CallTool.Result {
    let udid: String
    if let provided = args?["udid"]?.stringValue {
        udid = provided
    } else {
        udid = try await manager.bootedUDID()
    }

    _ = try await shell("/usr/bin/xcrun", ["simctl", "location", udid, "clear"])
    return .text("Location cleared.")
}

// MARK: - install_app

func installApp(_ args: [String: Value]?, manager: SimulatorManager) async throws -> CallTool.Result {
    guard let appPath = args?["app_path"]?.stringValue else {
        return .text("Error: 'app_path' is required.")
    }

    let udid: String
    if let provided = args?["udid"]?.stringValue {
        udid = provided
    } else {
        udid = try await manager.bootedUDID()
    }

    _ = try await shell("/usr/bin/xcrun", ["simctl", "install", udid, appPath])
    return .text("App installed from \(appPath)")
}

// MARK: - open_url

func openURL(_ args: [String: Value]?, manager: SimulatorManager) async throws -> CallTool.Result {
    guard let url = args?["url"]?.stringValue else {
        return .text("Error: 'url' is required.")
    }

    let udid: String
    if let provided = args?["udid"]?.stringValue {
        udid = provided
    } else {
        udid = try await manager.bootedUDID()
    }

    _ = try await shell("/usr/bin/xcrun", ["simctl", "openurl", udid, url])
    return .text("Opened URL: \(url)")
}

// MARK: - wait

func wait(_ args: [String: Value]?) async throws -> CallTool.Result {
    let seconds = args?["seconds"]?.doubleValue ?? 1.0
    try await Task.sleep(for: .seconds(seconds))
    return .text("Waited \(seconds) seconds.")
}

// MARK: - Convenience extension

private extension CallTool.Result {
    static func text(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: false)
    }
}
