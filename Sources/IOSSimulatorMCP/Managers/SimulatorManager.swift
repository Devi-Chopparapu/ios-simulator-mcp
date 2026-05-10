import Foundation
import Darwin

enum SimulatorError: Error, LocalizedError {
    case noBootedSimulator
    case alreadyRecording
    case notRecording
    case jsonParseError(String)

    var errorDescription: String? {
        switch self {
        case .noBootedSimulator:       return "No booted iOS Simulator found. Use boot_simulator first."
        case .alreadyRecording:        return "A recording is already in progress. Call stop_recording first."
        case .notRecording:            return "No recording is currently in progress."
        case .jsonParseError(let m):   return "Failed to parse simctl JSON: \(m)"
        }
    }
}

actor SimulatorManager {

    // MARK: - UDID cache

    private var cachedUDID: String?

    /// Returns the UDID of the currently booted simulator, caching the result.
    func bootedUDID() async throws -> String {
        if let cached = cachedUDID { return cached }
        let udid = try await findBootedUDID()
        cachedUDID = udid
        return udid
    }

    func invalidateCache() { cachedUDID = nil }

    // MARK: - Video recording

    private var recordingProcess: Process?
    private var recordingOutputPath: String?

    func startRecording(udid: String, outputPath: String, codec: String) async throws {
        // Check isRunning so a crashed/externally-killed process doesn't block a new recording
        if let existing = recordingProcess, existing.isRunning {
            throw SimulatorError.alreadyRecording
        }
        recordingProcess = nil  // clean up any stale reference

        // Kill any simctl recordVideo processes left over from a previous MCP session.
        // On restart the actor state is fresh but OS-level processes are not.
        try await killStaleRecordingProcesses(udid: udid)

        // simctl infers the container format from the output file extension (.mov, .mp4, .fmp4).
        // --type is only valid for `simctl io screenshot`, not recordVideo.
        let process = try launchBackground(
            "/usr/bin/xcrun",
            ["simctl", "io", udid, "recordVideo", "--codec", codec, "--force", outputPath]
        ) { line in
            log("[recorder] \(line)")
        }
        recordingProcess = process
        recordingOutputPath = outputPath
    }

    /// Stops recording. Sends SIGINT (not SIGTERM) so simctl can finalize/flush the video file,
    /// then offloads waitUntilExit to a background thread to avoid blocking the cooperative thread pool.
    func stopRecording() async throws -> String {
        guard let process = recordingProcess else { throw SimulatorError.notRecording }
        let path = recordingOutputPath ?? "unknown"
        kill(process.processIdentifier, SIGINT)
        let proc = process
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async { proc.waitUntilExit(); cont.resume() }
        }
        recordingProcess = nil
        recordingOutputPath = nil
        return path
    }

    var isRecording: Bool { recordingProcess?.isRunning == true }

    // MARK: - Private helpers

    /// Sends SIGINT to any OS-level simctl recordVideo processes for this UDID.
    /// Necessary after MCP restarts, where actor state is fresh but processes linger.
    private func killStaleRecordingProcesses(udid: String) async throws {
        let output = (try? await shell("/usr/bin/pgrep", ["-f", "simctl io \(udid) recordVideo"])) ?? ""
        let pids = output.split(separator: "\n").compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
        guard !pids.isEmpty else { return }
        for pid in pids {
            log("[recorder] Killing stale recordVideo process PID=\(pid)")
            kill(pid, SIGINT)
        }
        try await Task.sleep(for: .seconds(1))  // allow stale process to finalize before starting new one
    }

    private func findBootedUDID() async throws -> String {
        let json = try await shell("/usr/bin/xcrun", ["simctl", "list", "devices", "booted", "--json"])
        guard let data = json.data(using: .utf8) else {
            throw SimulatorError.jsonParseError("empty output")
        }
        let list = try JSONDecoder().decode(SimctlDeviceList.self, from: data)
        for (_, devices) in list.devices {
            if let booted = devices.first(where: { $0.isBooted }) {
                return booted.udid
            }
        }
        throw SimulatorError.noBootedSimulator
    }
}
