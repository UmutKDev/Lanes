import Foundation
import Observation

/// Claude Code's official installer script on claude.ai. Not tied to the
/// main actor: downloading and checking it happens in the background.
enum ClaudeCodeInstallScript {
    static let url = URL(string: "https://claude.ai/install.sh")!
    /// What Kurulum offers to run in Terminal and to copy when the in-app
    /// install fails. Exactly the command Anthropic documents.
    static let terminalCommand = "curl -fsSL https://claude.ai/install.sh | bash"
    /// The script is a few kilobytes; anything far larger is not it.
    private static let maxBytes = 1_000_000

    enum Failure: LocalizedError {
        case untrustedSource
        case badStatus(Int)
        case notAScript

        var errorDescription: String? {
            switch self {
            case .untrustedSource:
                return String(localized: "Kurulum dosyası claude.ai dışında bir adresten geldi, çalıştırılmadı.")
            case let .badStatus(code):
                return String(localized: "Kurulum dosyası indirilemedi (HTTP \(code)).")
            case .notAScript:
                return String(localized: "İndirilen dosya bir kurulum betiğine benzemiyor, çalıştırılmadı.")
            }
        }
    }

    /// Only Anthropic's own hosts may serve the script, after any redirect.
    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "claude.ai" || host.hasSuffix(".claude.ai")
    }

    /// Downloads the script into a new folder only this user can read, and
    /// returns the file. Nothing but the request itself is sent: an
    /// ephemeral session carries no cookies and no stored credentials.
    static func download() async throws -> URL {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, let finalURL = http.url, isTrusted(finalURL) else {
            throw Failure.untrustedSource
        }
        guard http.statusCode == 200 else { throw Failure.badStatus(http.statusCode) }
        // An HTML error page from a proxy or captive portal must never reach bash.
        guard !data.isEmpty, data.count <= maxBytes, data.starts(with: "#!".utf8) else { throw Failure.notAScript }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lanes-ClaudeCode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent("install.sh", isDirectory: false)
        try data.write(to: file, options: .withoutOverwriting)
        // bash reads it; it never needs to be executable.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return file
    }
}

/// Installs Claude Code with its official script, only when the user presses
/// "Kur" on Kurulum. The script's output streams into `log` line by line.
/// It runs as the user, with the user's environment: Lanes passes nothing
/// of its own and never touches Claude's sign-in or the Keychain.
@MainActor
@Observable
final class ClaudeCodeInstaller {
    enum Phase: Equatable {
        case idle
        case downloading
        case running
        /// The script ended; Lanes is looking for the command it installed.
        case verifying
        case succeeded
        case failed(String)
    }

    struct LogLine: Identifiable, Equatable {
        let id: Int
        let text: String
    }

    private enum Outcome {
        case exited(Int32)
        case stopped
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var log: [LogLine] = []

    var isWorking: Bool {
        switch phase {
        case .downloading, .running, .verifying: return true
        case .idle, .succeeded, .failed: return false
        }
    }

    /// A running script is terminated; a download finishes on its own
    /// within its timeout and is then not run.
    var canStop: Bool {
        phase == .downloading || phase == .running
    }

    /// Enough to scroll back through a whole install without growing forever.
    private static let maxLogLines = 500

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var nextLineID = 0
    /// Bumped for every run, so output or a timer left from an earlier run
    /// never lands in the current one.
    @ObservationIgnored private var runID = 0
    @ObservationIgnored private var buffers: [Int: Data] = [:]
    @ObservationIgnored private var handles: [FileHandle] = []
    /// Standard output's end, standard error's end and the exit: the run
    /// finishes when all three arrived, so the last lines are not lost.
    @ObservationIgnored private var pendingEnds = 0
    @ObservationIgnored private var exitOutcome: Outcome?
    @ObservationIgnored private var continuation: CheckedContinuation<Outcome, Never>?

    /// Downloads and runs the installer, then asks `verify` whether the
    /// command is now there. `verify` decides success: a script that exits 0
    /// without a usable command is still a failure the user should see.
    func install(verify: @MainActor () async -> Bool) async {
        guard !isWorking else { return }
        log = []
        stopRequested = false
        phase = .downloading
        appendLine(String(localized: "İndiriliyor: \(ClaudeCodeInstallScript.url.absoluteString)"))

        let script: URL
        do {
            script = try await ClaudeCodeInstallScript.download()
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        guard !stopRequested else {
            phase = .failed(String(localized: "Kurulum durduruldu."))
            return
        }

        phase = .running
        let outcome = await execute(script)
        switch outcome {
        case .stopped:
            phase = .failed(String(localized: "Kurulum durduruldu."))
        case let .failed(message):
            phase = .failed(message)
        case let .exited(status):
            phase = .verifying
            if await verify() {
                phase = .succeeded
            } else if status == 0 {
                phase = .failed(String(localized: "Kurulum bitti ama claude komutu bulunamadı."))
            } else {
                phase = .failed(String(localized: "Kurulum hata verdi (çıkış kodu \(status))."))
            }
        }
    }

    func stop() {
        guard canStop else { return }
        stopRequested = true
        process?.terminate()
    }

    // MARK: Running the script

    private func execute(_ script: URL) async -> Outcome {
        runID += 1
        let run = runID
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        let home = FileManager.default.homeDirectoryForCurrentUser
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        process.environment = environment
        process.currentDirectoryURL = home
        // Nothing to answer: a question from the script reads end of input
        // instead of waiting forever.
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.pendingEnds = 3
            self.exitOutcome = nil
            self.buffers = [0: Data(), 1: Data()]
            self.handles = [output.fileHandleForReading, errors.fileHandleForReading]
            watch(output.fileHandleForReading, stream: 0, run: run)
            watch(errors.fileHandleForReading, stream: 1, run: run)
            process.terminationHandler = { [weak self] finished in
                let status = finished.terminationStatus
                let signalled = finished.terminationReason == .uncaughtSignal
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.processExited(status: status, signalled: signalled, run: run)
                    }
                }
            }
            do {
                try process.run()
                self.process = process
            } catch {
                finish(with: .failed(error.localizedDescription))
            }
        }
    }

    /// Reads on the pipe's own thread and hands each chunk to the main
    /// queue, which keeps the chunks in order.
    private func watch(_ handle: FileHandle, stream: Int, run: Int) {
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.received(data, stream: stream, run: run)
                }
            }
        }
    }

    private func received(_ data: Data, stream: Int, run: Int) {
        guard run == runID, continuation != nil else { return }
        guard !data.isEmpty else {
            flush(stream)
            endReached()
            return
        }
        var buffer = buffers[stream, default: Data()]
        buffer.append(data)
        // Carriage returns too: progress bars redraw one line with them.
        while let index = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            appendLine(String(decoding: buffer[buffer.startIndex..<index], as: UTF8.self))
            buffer = Data(buffer[buffer.index(after: index)...])
        }
        buffers[stream] = buffer
    }

    private func processExited(status: Int32, signalled: Bool, run: Int) {
        guard run == runID, continuation != nil else { return }
        exitOutcome = stopRequested && (signalled || status != 0) ? .stopped : .exited(status)
        endReached()
        // A child the script left running may keep the pipes open; the run
        // still ends shortly after the script itself did.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, run == self.runID, let outcome = self.exitOutcome else { return }
                self.finish(with: outcome)
            }
        }
    }

    private func endReached() {
        pendingEnds -= 1
        if pendingEnds <= 0, let exitOutcome {
            finish(with: exitOutcome)
        }
    }

    private func finish(with outcome: Outcome) {
        guard let continuation else { return }
        self.continuation = nil
        flush(0)
        flush(1)
        for handle in handles {
            handle.readabilityHandler = nil
        }
        handles = []
        process = nil
        continuation.resume(returning: outcome)
    }

    private func flush(_ stream: Int) {
        guard let buffer = buffers[stream], !buffer.isEmpty else { return }
        appendLine(String(decoding: buffer, as: UTF8.self))
        buffers[stream] = Data()
    }

    /// Drops terminal colour codes and blank lines, and keeps the log short.
    private func appendLine(_ raw: String) {
        let text = raw
            .replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        log.append(LogLine(id: nextLineID, text: text))
        nextLineID += 1
        if log.count > Self.maxLogLines {
            log.removeFirst(log.count - Self.maxLogLines)
        }
    }
}
