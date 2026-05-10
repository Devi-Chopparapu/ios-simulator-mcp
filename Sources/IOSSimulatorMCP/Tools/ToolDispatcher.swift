import MCP

struct ToolDispatcher: Sendable {
    let simulatorManager: SimulatorManager
    let wdaManager: WDAManager

    func dispatch(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            return try await route(params)
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    /// Tools that require WDA. WDA is auto-started if not already running — the user
    /// never needs to call start_wda explicitly.
    /// NOTE: press_button(lock/siri) and shake use AppleScript, NOT WDA — keep them out of
    /// this set so we don't trigger a 2-minute WDA build for those operations.
    private static let wdaInteractionTools: Set<String> = [
        "tap", "tap_element", "find_element", "long_press", "swipe",
        "type_text", "tap_and_type",
        "ui_describe_all", "ui_describe_point",
    ]

    private func route(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let args = params.arguments

        // Auto-start WDA transparently before any UI interaction tool.
        if Self.wdaInteractionTools.contains(params.name) {
            try await wdaManager.ensureRunning(simManager: simulatorManager)
        }

        switch params.name {
        // --- simctl ---
        case "list_simulators":   return try await listSimulators(args)
        case "get_booted_sim_id": return try await getBootedSimId(args, manager: simulatorManager)
        case "boot_simulator":    return try await bootSimulator(args, manager: simulatorManager)
        case "open_simulator":    return try await openSimulator(args)
        case "get_device_info":   return try await getDeviceInfo(args, manager: simulatorManager)
        case "screenshot":        return try await screenshot(args, manager: simulatorManager)
        case "record_video":      return try await recordVideo(args, manager: simulatorManager)
        case "stop_recording":    return try await stopRecording(args, manager: simulatorManager)
        case "set_location":      return try await setLocation(args, manager: simulatorManager)
        case "clear_location":    return try await clearLocation(args, manager: simulatorManager)
        case "find_app":          return try await findApp(args, manager: simulatorManager)
        case "install_app":       return try await installApp(args, manager: simulatorManager)
        case "open_url":          return try await openURL(args, manager: simulatorManager)
        case "wait":              return try await wait(args)
        // --- WDA ---
        case "start_wda":         return try await startWDA(args, simManager: simulatorManager, wdaManager: wdaManager)
        case "stop_wda":          return try await stopWDA(args, wdaManager: wdaManager)
        case "tap_element":       return try await tapElement(args, wdaManager: wdaManager)
        case "find_element":      return try await findElement(args, wdaManager: wdaManager)
        case "tap":               return try await tap(args, wdaManager: wdaManager)
        case "long_press":        return try await longPress(args, wdaManager: wdaManager)
        case "swipe":             return try await swipe(args, wdaManager: wdaManager)
        case "type_text":         return try await typeText(args, wdaManager: wdaManager)
        case "tap_and_type":      return try await tapAndType(args, wdaManager: wdaManager)
        case "press_button":      return try await pressButton(args, wdaManager: wdaManager)
        case "shake":             return try await shake(args, wdaManager: wdaManager)
        case "ui_describe_all":   return try await uiDescribeAll(args, wdaManager: wdaManager)
        case "ui_describe_point": return try await uiDescribePoint(args, wdaManager: wdaManager)
        case "launch_app":        return try await launchApp(args, manager: simulatorManager)
        case "terminate_app":     return try await terminateApp(args, manager: simulatorManager)
        default:
            return CallTool.Result(
                content: [.text(text: "Unknown tool: \(params.name)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }
}
