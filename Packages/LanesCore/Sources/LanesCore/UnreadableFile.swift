import Foundation

/// Moves a file Lanes could not read out of the way, so the next save never
/// replaces the only copy. The file is renamed to
/// `<name>-unreadable-<date>-<time>.json` in the same folder, with a counter
/// when that name is taken.
func setAsideUnreadableFile(at fileURL: URL, now: Date) throws -> URL {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let stem = fileURL.deletingPathExtension().lastPathComponent + "-unreadable-" + formatter.string(from: now)
    let directory = fileURL.deletingLastPathComponent()
    var destination = directory.appendingPathComponent(stem + ".json", isDirectory: false)
    var counter = 2
    while FileManager.default.fileExists(atPath: destination.path) {
        destination = directory.appendingPathComponent("\(stem)-\(counter).json", isDirectory: false)
        counter += 1
    }
    try FileManager.default.moveItem(at: fileURL, to: destination)
    return destination
}
