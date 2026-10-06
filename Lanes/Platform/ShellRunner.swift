import Foundation

/// Runs a system tool such as `codesign` and collects its output.
enum ShellRunner {
    struct Output {
        var status: Int32
        var text: String
    }

    static func run(_ executable: String, _ arguments: [String]) async -> Output {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Output(status: -1, text: error.localizedDescription))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: Output(status: process.terminationStatus, text: text))
            }
        }
    }

    /// The command line and its output, ready to paste into a report.
    static func transcript(_ executable: String, _ arguments: [String]) async -> [String] {
        let output = await run(executable, arguments)
        let command = ([executable] + arguments).joined(separator: " ")
        return ["$ \(command)", output.text.isEmpty ? "(çıktı yok)" : output.text, "çıkış kodu: \(output.status)"]
    }
}
