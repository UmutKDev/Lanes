import os

/// Lanes's lines in the system log, under the subsystem com.umutkdev.Lanes.
/// Account names, paths and links never go in: a sign-in link can carry a
/// one-time code. Read with:
/// `log show --predicate 'subsystem == "com.umutkdev.Lanes"' --last 1h`
enum Log {
    static let app = Logger(subsystem: "com.umutkdev.Lanes", category: "app")
    static let instances = Logger(subsystem: "com.umutkdev.Lanes", category: "instances")
}
