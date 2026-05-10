import Foundation
import MCP

// MARK: - list_simulators

func listSimulators(_ args: [String: Value]?) async throws -> CallTool.Result {
    let json: String
    do {
        json = try await shell("/usr/bin/xcrun", ["simctl", "list", "devices", "--json"], timeout: 60)
    } catch ShellError.timeout {
        return .text("""
            CoreSimulator timed out (>60s). The service may be stuck.
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
            // Sort descending so highest OS version wins when name matches multiple runtimes
            let sorted = list.devices.sorted(by: { $0.key > $1.key })
            outer: for (_, devices) in sorted {
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

    do {
        _ = try await shell("/usr/bin/xcrun", ["simctl", "boot", targetUDID], timeout: 60)
    } catch ShellError.commandFailed(let out, _) where out.contains("current state: Booted") {
        // already booted — not an error
    }
    await manager.invalidateCache()

    // xcrun simctl boot returns immediately on newer Xcode — poll until state is "Booted"
    // so callers don't fail with "device in Booting state" on the very next tool call.
    let bootDeadline = Date().addingTimeInterval(120)
    while Date() < bootDeadline {
        let statusJson = try await shell(
            "/usr/bin/xcrun", ["simctl", "list", "devices", "booted", "--json"], timeout: 20
        )
        if let data = statusJson.data(using: .utf8),
           let list = try? JSONDecoder().decode(SimctlDeviceList.self, from: data) {
            let booted = list.devices.values.flatMap { $0 }.contains { $0.udid == targetUDID && $0.isBooted }
            if booted { break }
        }
        try await Task.sleep(for: .seconds(2))
    }

    return .text("Booted simulator \(targetUDID)")
}

// MARK: - open_simulator

func openSimulator(_ args: [String: Value]?) async throws -> CallTool.Result {
    _ = try await shell("/usr/bin/open", ["-a", "Simulator"])
    return .text("Simulator.app opened.")
}

// MARK: - get_device_info

func getDeviceInfo(_ args: [String: Value]?, manager: SimulatorManager) async throws -> CallTool.Result {
    let explicitUDID = args?["udid"]?.stringValue
    let udid: String
    if let provided = explicitUDID {
        udid = provided
    } else {
        udid = try await manager.bootedUDID()
    }

    // Use full list when UDID is explicit — device may not be booted
    let filter = explicitUDID != nil ? [] : ["booted"]
    let json = try await shell("/usr/bin/xcrun", ["simctl", "list", "devices"] + filter + ["--json"])
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

    // Default jpeg — ~3× smaller than png for UI screenshots, big token saving.
    let format   = args?["type"]?.stringValue ?? "jpeg"
    // scale=0.3 on a 3× Retina device ≈ ~11× fewer tokens vs native, still readable.
    // Pass scale=1.0 for full native resolution.
    let scale    = args?["scale"]?.numericDoubleValue ?? 0.3
    let mimeType = format == "jpeg" ? "image/jpeg" : "image/png"
    let ext      = format == "jpeg" ? "jpg" : "png"
    let uuid     = UUID().uuidString
    let fullPath = NSTemporaryDirectory() + "sim_shot_\(uuid).\(ext)"

    _ = try await shell("/usr/bin/xcrun", ["simctl", "io", udid, "screenshot", "--type", format, fullPath])
    defer { try? FileManager.default.removeItem(atPath: fullPath) }

    // save_to_path: save the screenshot to disk and return only the path — zero vision tokens.
    // Use this when you need to capture but don't need Claude to analyse the image.
    if let savePath = args?["save_to_path"]?.stringValue {
        // Remove existing file first so copyItem/write don't fail silently on overwrite.
        try? FileManager.default.removeItem(atPath: savePath)
        if scale > 0 && scale < 1.0,
           let scaledData = await downscaleImage(at: fullPath, scale: scale, ext: ext) {
            try? scaledData.write(to: URL(fileURLWithPath: savePath))
        } else {
            try? FileManager.default.copyItem(atPath: fullPath, toPath: savePath)
        }
        return .text("Screenshot saved to \(savePath)")
    }

    guard let fullData = FileManager.default.contents(atPath: fullPath) else {
        return .text("Screenshot taken but could not read file at \(fullPath)")
    }

    // Downscale via sips (built-in macOS) when scale < 1.0.
    // On failure we fall through to the full-res image rather than erroring.
    var imageData = fullData
    if scale > 0 && scale < 1.0 {
        if let scaledData = await downscaleImage(at: fullPath, scale: scale, ext: ext) {
            imageData = scaledData
        }
    }

    return CallTool.Result(
        content: [.image(data: imageData.base64EncodedString(), mimeType: mimeType, annotations: nil, _meta: nil)],
        isError: false
    )
}

/// Uses `sips` (macOS built-in) to resample an image file by a scale factor.
/// Returns nil if anything goes wrong — callers fall back to the original.
private func downscaleImage(at path: String, scale: Double, ext: String) async -> Data? {
    // Query pixel width (sips -g outputs lines like "  pixelWidth: 1179")
    guard let info = try? await shell("/usr/bin/sips", ["-g", "pixelWidth", path]),
          let widthLine = info.split(separator: "\n").first(where: { $0.contains("pixelWidth") }),
          let widthStr  = widthLine.split(separator: ":").last.map(String.init),
          let pixelWidth = Int(widthStr.trimmingCharacters(in: .whitespaces)),
          pixelWidth > 0 else { return nil }

    let scaledWidth = max(1, Int(Double(pixelWidth) * scale))
    let scaledPath  = path + "_scaled.\(ext)"
    defer { try? FileManager.default.removeItem(atPath: scaledPath) }

    guard (try? await shell("/usr/bin/sips",
                            ["--resampleWidth", "\(scaledWidth)", path, "--out", scaledPath])) != nil
    else { return nil }

    return FileManager.default.contents(atPath: scaledPath)
}

// MARK: - record_video

func recordVideo(_ args: [String: Value]?, manager: SimulatorManager) async throws -> CallTool.Result {
    // Default: ~/Movies/recording.mov — same location QuickTime Player uses, always accessible.
    let moviesDir = (NSHomeDirectory() as NSString).appendingPathComponent("Movies")
    try? FileManager.default.createDirectory(atPath: moviesDir, withIntermediateDirectories: true)
    let outputPath = args?["output_path"]?.stringValue
        ?? (moviesDir as NSString).appendingPathComponent("recording.mov")

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
    let path = try await manager.stopRecording()  // now async — won't block thread pool
    return .text("Recording saved to: \(path)")
}

// MARK: - set_location

func setLocation(_ args: [String: Value]?, manager: SimulatorManager) async throws -> CallTool.Result {
    guard let lat = args?["latitude"]?.numericDoubleValue,
          let lng = args?["longitude"]?.numericDoubleValue else {
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
    // numericDoubleValue accepts both JSON floats and integers (e.g. seconds: 3 vs seconds: 3.0)
    let seconds = args?["seconds"]?.numericDoubleValue ?? 1.0
    try await Task.sleep(for: .seconds(seconds))
    return .text("Waited \(seconds) seconds.")
}

// MARK: - find_app

/// Find an installed app by name (case-insensitive substring match) and return its bundle ID.
func findApp(_ args: [String: Value]?, manager: SimulatorManager) async throws -> CallTool.Result {
    guard let name = args?["name"]?.stringValue, !name.isEmpty else {
        return .text("Error: 'name' is required.")
    }
    let udid: String
    if let provided = args?["udid"]?.stringValue {
        udid = provided
    } else {
        udid = try await manager.bootedUDID()
    }

    // Use `defaults` to read the app registry plist that simctl writes.
    // More reliable than parsing simctl listapps plist output directly.
    let raw = try await shell("/usr/bin/xcrun", ["simctl", "listapps", udid])

    // Convert XML plist string → Data → NSDictionary
    guard let plistData = raw.data(using: .utf8) else {
        return .text("Error: could not read app list output.")
    }

    var format = PropertyListSerialization.PropertyListFormat.xml
    guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData, options: [], format: &format),
          let apps = plist as? [String: Any] else {
        // Fallback: grep bundle IDs and display names from the raw plist text
        let q = name.lowercased()
        let lines = raw.components(separatedBy: "\n")
        var bundleIds: [String] = []
        for (i, line) in lines.enumerated() {
            if line.contains("CFBundleIdentifier") {
                // Next non-empty line has the value
                let valueLine = lines.dropFirst(i + 1).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
                if let id = valueLine.components(separatedBy: ">").dropFirst().first?.components(separatedBy: "<").first,
                   id.lowercased().contains(q) {
                    bundleIds.append(id)
                }
            }
        }
        if bundleIds.isEmpty {
            return .text("No app matching \"\(name)\" found. Make sure the app is installed on the simulator — do not build it, ask the user to install it.")
        }
        return .text(bundleIds.map { "  \($0)" }.joined(separator: "\n"))
    }

    let q = name.lowercased()
    var matches: [(bundleId: String, displayName: String)] = []

    for (bundleId, value) in apps {
        guard let info = value as? [String: Any] else { continue }
        let displayName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? bundleId
        if displayName.lowercased().contains(q) || bundleId.lowercased().contains(q) {
            matches.append((bundleId, displayName))
        }
    }

    if matches.isEmpty {
        return .text("No app matching \"\(name)\" found on the simulator. The app must be installed by the user — do not attempt to build or install it.")
    }

    return .text(matches
        .sorted { $0.displayName < $1.displayName }
        .map { "  \($0.displayName)  →  \($0.bundleId)" }
        .joined(separator: "\n"))
}

// MARK: - launch_app

/// Launch an app by bundle ID or display name using xcrun simctl. Does not require WDA.
/// If `name` is provided instead of `bundle_id`, the installed app list is searched first.
func launchApp(_ args: [String: Value]?, manager: SimulatorManager) async throws -> CallTool.Result {
    let udid: String
    if let provided = args?["udid"]?.stringValue {
        udid = provided
    } else {
        udid = try await manager.bootedUDID()
    }

    let bundleId: String
    if let explicit = args?["bundle_id"]?.stringValue {
        bundleId = explicit
    } else if let name = args?["name"]?.stringValue, !name.isEmpty {
        // Resolve name → bundle ID via simctl listapps
        let json = try await shell("/usr/bin/xcrun", ["simctl", "listapps", udid])
        guard let plistData = json.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
              let apps = plist as? [String: [String: Any]] else {
            return .text("Error: could not read installed apps list.")
        }
        let q = name.lowercased()
        let match = apps.first(where: { (bid, info) in
            let dn = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? bid
            return dn.lowercased().contains(q) || bid.lowercased().contains(q)
        })
        guard let found = match else {
            return .text("Error: no app matching \"\(name)\" found. Use find_app to list installed apps.")
        }
        bundleId = found.key
    } else {
        return .text("Error: provide 'bundle_id' or 'name'.")
    }

    _ = try await shell("/usr/bin/xcrun", ["simctl", "launch", udid, bundleId])
    return .text("Launched app: \(bundleId)")
}

// MARK: - terminate_app

/// Terminate a running app by bundle ID using xcrun simctl. Does not require WDA.
func terminateApp(_ args: [String: Value]?, manager: SimulatorManager) async throws -> CallTool.Result {
    guard let bundleId = args?["bundle_id"]?.stringValue else {
        return .text("Error: 'bundle_id' is required.")
    }
    let udid: String
    if let provided = args?["udid"]?.stringValue {
        udid = provided
    } else {
        udid = try await manager.bootedUDID()
    }
    do {
        _ = try await shell("/usr/bin/xcrun", ["simctl", "terminate", udid, bundleId])
    } catch ShellError.commandFailed(let out, _) where out.lowercased().contains("not running") {
        // App wasn't running — treat as success rather than an error
    }
    return .text("Terminated app: \(bundleId)")
}

// CallTool.Result.text() is defined in ToolHelpers.swift
