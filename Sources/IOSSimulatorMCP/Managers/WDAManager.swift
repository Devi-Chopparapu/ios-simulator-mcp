import Foundation

enum WDAError: Error, LocalizedError {
    case notStarted
    case startTimeout
    case sessionFailed(String)
    case httpError(Int, String)
    case decodingError(String)
    case noSession

    var errorDescription: String? {
        switch self {
        case .notStarted:              return "WDA is not running. Call start_wda first."
        case .startTimeout:            return "WDA did not become ready within 120 seconds."
        case .sessionFailed(let m):    return "WDA session creation failed: \(m)"
        case .httpError(let c, let m): return "WDA HTTP \(c): \(m)"
        case .decodingError(let m):    return "WDA response decode error: \(m)"
        case .noSession:               return "No active WDA session. WDA may have restarted."
        }
    }
}

actor WDAManager {

    // MARK: - State

    private var xcodebuildProcess: Process?
    private var sessionId: String?
    private var wdaPort: Int = 8100
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    var baseURL: URL { URL(string: "http://localhost:\(wdaPort)")! }

    // MARK: - Lifecycle

    /// Start WDA for the given simulator UDID using xcodebuild.
    func start(udid: String, wdaProjectPath: String, port: Int = 8100) async throws {
        self.wdaPort = port

        if let existing = xcodebuildProcess, existing.isRunning {
            existing.terminate()
            // Offload waitUntilExit to a background thread — blocking inside an actor
            // method holds a cooperative thread pool thread for the entire duration.
            let proc = existing
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async { proc.waitUntilExit(); cont.resume() }
            }
        }
        sessionId = nil

        let derivedDataPath = NSTemporaryDirectory() + "wda-deriveddata"

        let args: [String] = [
            "test",
            "-project", wdaProjectPath,
            "-scheme", "WebDriverAgentRunner",
            "-destination", "id=\(udid)",
            "-derivedDataPath", derivedDataPath,
            "USE_PORT=\(port)",
            "MJPEG_SERVER_PORT=\(port + 1000)",
        ]

        log("[WDA] Starting: xcodebuild \(args.joined(separator: " "))")

        let process = try launchBackground("/usr/bin/xcodebuild", args) { line in
            log("[WDA] \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        xcodebuildProcess = process
    }

    /// Poll GET /status until WDA reports ready or timeout expires.
    func waitForReady(timeoutSeconds: Double = 120) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var delay: UInt64 = 1_000_000_000

        while Date() < deadline {
            if let proc = xcodebuildProcess, !proc.isRunning {
                throw WDAError.sessionFailed("xcodebuild exited early — check WDA project path and scheme")
            }
            if let status = try? await getStatus(), status.ready == true {
                log("[WDA] Ready ✓")
                return
            }
            try await Task.sleep(nanoseconds: delay)
            delay = min(delay * 2, 8_000_000_000)
        }
        throw WDAError.startTimeout
    }

    func stop() {
        xcodebuildProcess?.terminate()
        xcodebuildProcess = nil
        sessionId = nil
    }

    var isRunning: Bool { xcodebuildProcess?.isRunning == true }

    // MARK: - Session

    /// Get or lazily create a WDA session.
    func session() async throws -> String {
        if let existing = sessionId {
            do {
                // Validate the session itself exists, not just WDA liveness
                _ = try await get("/session/\(existing)")
                return existing
            } catch WDAError.httpError(let code, _) where code == 404 {
                // Session genuinely gone (WDA restarted) — create a new one
                sessionId = nil
            } catch {
                // Transient error (timeout, network blip) — assume session still valid
                return existing
            }
        }

        let req = WDACreateSessionRequest.make(bundleId: nil)
        let data = try await post("/session", body: req)

        struct SessionResp: Decodable {
            struct Val: Decodable { let sessionId: String }
            let value: Val
        }

        guard let resp = try? JSONDecoder().decode(SessionResp.self, from: data),
              !resp.value.sessionId.isEmpty else {
            throw WDAError.sessionFailed("Could not parse sessionId from response")
        }

        sessionId = resp.value.sessionId
        log("[WDA] Session: \(resp.value.sessionId)")
        return resp.value.sessionId
    }

    func deleteSession() async throws {
        guard let sid = sessionId else { return }
        _ = try? await delete("/session/\(sid)")
        sessionId = nil
    }

    // MARK: - UI Actions

    func tap(x: Double, y: Double) async throws {
        let sid = try await session()
        let body = WDAActionsRequest.tap(x: x, y: y)
        _ = try await post("/session/\(sid)/actions", body: body)
    }

    func longPress(x: Double, y: Double, durationSeconds: Double) async throws {
        let sid = try await session()
        let body = WDAActionsRequest.longPress(x: x, y: y, durationMs: Int(durationSeconds * 1000))
        _ = try await post("/session/\(sid)/actions", body: body)
    }

    func swipe(fromX: Double, fromY: Double, toX: Double, toY: Double, durationSeconds: Double = 0.5) async throws {
        let sid = try await session()
        let body = WDAActionsRequest.swipe(fromX: fromX, fromY: fromY, toX: toX, toY: toY,
                                           durationMs: Int(durationSeconds * 1000))
        _ = try await post("/session/\(sid)/actions", body: body)
    }

    func typeText(_ text: String) async throws {
        let sid = try await session()
        let body = WDAKeysRequest.make(text)
        _ = try await post("/session/\(sid)/wda/keys", body: body)
    }

    func pressButton(_ name: String) async throws {
        let sid = try await session()
        let body = WDAButtonRequest(name: name)
        _ = try await post("/session/\(sid)/wda/pressButton", body: body)
    }

    func shake() async throws {
        let sid = try await session()
        _ = try await post("/session/\(sid)/wda/shake", body: EmptyBody())
    }

    func uiSource() async throws -> String {
        let sid = try await session()
        let data = try await get("/session/\(sid)/source")
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Describe the element at a point.
    ///
    /// WDA v12.2.2 has no `/wda/element/atCoordinate` endpoint, so we fetch the full
    /// accessibility tree via `/source` and hit-test it ourselves. We return the
    /// **smallest** bounding box that contains the point — that's the deepest (most
    /// specific) element under the cursor, which is what callers actually want.
    func describeElement(x: Double, y: Double) async throws -> String {
        let xml = try await uiSource()
        return Self.findElementAt(x: x, y: y, in: xml)
    }

    /// Walks the WDA source XML tree and returns a formatted description of the
    /// smallest element whose bounding rect contains (x, y). Pure function — testable
    /// without a live WDA. Made `nonisolated` so the recursive walk doesn't bounce
    /// in and out of the actor's executor for every node.
    nonisolated static func findElementAt(x: Double, y: Double, in xml: String) -> String {
        guard let data = xml.data(using: .utf8),
              let doc  = try? XMLDocument(data: data, options: []) else {
            return "Failed to parse UI source XML."
        }

        var best: XMLElement?
        var bestArea = Double.infinity

        func contains(_ el: XMLElement) -> (rect: (Double, Double, Double, Double), area: Double)? {
            guard
                let ex = el.attribute(forName: "x")?.stringValue.flatMap(Double.init),
                let ey = el.attribute(forName: "y")?.stringValue.flatMap(Double.init),
                let ew = el.attribute(forName: "width")?.stringValue.flatMap(Double.init),
                let eh = el.attribute(forName: "height")?.stringValue.flatMap(Double.init)
            else { return nil }
            guard x >= ex, x < ex + ew, y >= ey, y < ey + eh else { return nil }
            return ((ex, ey, ew, eh), ew * eh)
        }

        // Use <= so when a child has the same bounds as its parent (Window inside App
        // is the common case) we still descend to the deeper, more specific element.
        func walk(_ node: XMLNode) {
            if let el = node as? XMLElement, let hit = contains(el), hit.area <= bestArea {
                bestArea = hit.area
                best = el
            }
            for child in node.children ?? [] { walk(child) }
        }

        if let root = doc.rootElement() { walk(root) }

        guard let match = best else {
            return "No element found at (\(x), \(y))."
        }

        // Format the matched element's tag + attributes — skip empty values to keep
        // the output readable.
        var lines: [String] = ["Element: \(match.name ?? "unknown")"]
        for attr in match.attributes ?? [] {
            guard let n = attr.name, let v = attr.stringValue, !v.isEmpty else { continue }
            lines.append("  \(n): \(v)")
        }
        return lines.joined(separator: "\n")
    }

    func launchApp(bundleId: String) async throws {
        let sid = try await session()
        let body = WDAActivateAppRequest(bundleId: bundleId)
        _ = try await post("/session/\(sid)/wda/apps/activate", body: body)
    }

    func terminateApp(bundleId: String) async throws {
        let sid = try await session()
        let body = WDATerminateAppRequest(bundleId: bundleId)
        _ = try await post("/session/\(sid)/wda/apps/terminate", body: body)
    }

    // MARK: - HTTP helpers

    private func getStatus() async throws -> WDAStatus? {
        let data = try await get("/status")
        struct StatusResp: Decodable { let value: WDAStatus? }
        return try? JSONDecoder().decode(StatusResp.self, from: data).value
    }

    private func get(_ path: String) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "GET"
        return try await execute(req)
    }

    private func post<B: Encodable>(_ path: String, body: B) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        return try await execute(req)
    }

    private func delete(_ path: String) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "DELETE"
        return try await execute(req)
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WDAError.httpError(http.statusCode, body)
        }
        return data
    }
}

private struct EmptyBody: Encodable {}
