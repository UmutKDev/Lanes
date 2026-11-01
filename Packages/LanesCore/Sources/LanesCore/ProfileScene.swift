import Foundation

public struct SceneID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func make() -> SceneID {
        SceneID(rawValue: UUID().uuidString.lowercased())
    }

    public var description: String { rawValue }
}

/// A saved group of accounts that open together, such as "İş" with the work
/// and client accounts. Called a scene in the app.
public struct ProfileScene: Identifiable, Hashable, Codable, Sendable {
    public var id: SceneID
    public var name: String
    /// In the order they open.
    public var profileIDs: [ProfileID]
    /// Opens the scene each time Lanes starts, which with "Oturum açıldığında
    /// Lanes'i başlat" means at login.
    public var opensWhenLanesStarts: Bool
    /// Where each account's Claude window goes when the scene opens, keyed
    /// by profile ID. Empty means windows stay where Claude puts them.
    public var windowFrames: [String: SceneWindowFrame]
    /// Opens the scene at a time of day on chosen weekdays.
    public var schedule: SceneSchedule?
    /// Opens the scene when this display is connected.
    public var display: SceneDisplay?

    public init(id: SceneID = .make(), name: String, profileIDs: [ProfileID], opensWhenLanesStarts: Bool = false, windowFrames: [String: SceneWindowFrame] = [:], schedule: SceneSchedule? = nil, display: SceneDisplay? = nil) {
        self.id = id
        self.name = name
        self.profileIDs = profileIDs
        self.opensWhenLanesStarts = opensWhenLanesStarts
        self.windowFrames = windowFrames
        self.schedule = schedule
        self.display = display
    }

    enum CodingKeys: String, CodingKey {
        case id, name, profileIDs, opensWhenLanesStarts, windowFrames, schedule, display
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(profileIDs, forKey: .profileIDs)
        try container.encode(opensWhenLanesStarts, forKey: .opensWhenLanesStarts)
        // Written only when saved, so a scene without it looks as before.
        if !windowFrames.isEmpty {
            try container.encode(windowFrames, forKey: .windowFrames)
        }
        try container.encodeIfPresent(schedule, forKey: .schedule)
        try container.encodeIfPresent(display, forKey: .display)
    }

    public func windowFrame(for id: ProfileID) -> SceneWindowFrame? {
        windowFrames[id.rawValue]
    }

    /// Keeps saved frames only for accounts still in the scene.
    public mutating func pruneWindowFrames() {
        let kept = Set(profileIDs.map(\.rawValue))
        windowFrames = windowFrames.filter { kept.contains($0.key) }
    }

    /// Only the ID is required, like a profile.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SceneID.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? L("Adsız sahne", "Untitled Scene")
        profileIDs = (try? container.decode([ProfileID].self, forKey: .profileIDs)) ?? []
        opensWhenLanesStarts = (try? container.decode(Bool.self, forKey: .opensWhenLanesStarts)) ?? false
        windowFrames = (try? container.decode([String: SceneWindowFrame].self, forKey: .windowFrames)) ?? [:]
        schedule = try? container.decodeIfPresent(SceneSchedule.self, forKey: .schedule)
        display = try? container.decodeIfPresent(SceneDisplay.self, forKey: .display)
    }

    /// The scene's accounts that still exist, in the scene's order.
    public func profiles(in library: ProfileLibrary) -> [Profile] {
        profileIDs.compactMap(library.profile(withID:))
    }
}

extension ProfileLibrary {
    public func scene(withID id: SceneID) -> ProfileScene? {
        scenes.first { $0.id == id }
    }

    public mutating func addScene(_ scene: ProfileScene) throws {
        guard self.scene(withID: scene.id) == nil else {
            throw ProfileStoreError.duplicateSceneID(scene.id)
        }
        scenes.append(scene)
    }

    public mutating func updateScene(_ scene: ProfileScene) throws {
        guard let index = scenes.firstIndex(where: { $0.id == scene.id }) else {
            throw ProfileStoreError.unknownScene(scene.id)
        }
        scenes[index] = scene
    }

    public mutating func removeScene(_ id: SceneID) {
        scenes.removeAll { $0.id == id }
    }
}

/// A window's place on screen, in screen points with the origin at the top
/// left of the main display, as the Accessibility API uses them.
public struct SceneWindowFrame: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// A time of day and the weekdays a scene opens on by itself.
public struct SceneSchedule: Hashable, Codable, Sendable {
    /// Minutes after midnight, 0..<1440.
    public var minuteOfDay: Int
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday. Empty means every day.
    public var weekdays: Set<Int>

    /// A scene the Mac slept through opens on waking only within this
    /// many seconds of its time; later it waits for the next day.
    public static let lateWindow: TimeInterval = 2 * 3600

    public init(minuteOfDay: Int, weekdays: Set<Int> = []) {
        self.minuteOfDay = min(max(minuteOfDay, 0), 1439)
        self.weekdays = weekdays.filter { (1...7).contains($0) }
    }

    /// This day's opening time, or nil on a day the scene skips.
    public func occurrence(on day: Date, calendar: Calendar = .current) -> Date? {
        let weekday = calendar.component(.weekday, from: day)
        guard weekdays.isEmpty || weekdays.contains(weekday) else { return nil }
        // By wall clock, so a daylight saving day still opens at 09:00.
        return calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day)
    }

    /// Whether the scene should open now: today's time has come, at most
    /// `lateWindow` ago, and the scene has not opened since.
    /// Yesterday's time counts too, so 23:30 still opens on a wake at 00:30.
    public func isDue(now: Date, lastOpened: Date?, calendar: Calendar = .current) -> Bool {
        let days = [now, calendar.date(byAdding: .day, value: -1, to: now)].compactMap { $0 }
        return days.contains { day in
            guard let time = occurrence(on: day, calendar: calendar), now >= time,
                  now.timeIntervalSince(time) <= SceneSchedule.lateWindow else { return false }
            return (lastOpened ?? .distantPast) < time
        }
    }

    enum CodingKeys: String, CodingKey {
        case minuteOfDay, weekdays
    }

    /// Read through the clamping initializer, so a hand-edited file cannot
    /// move the time to another day.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            minuteOfDay: try container.decode(Int.self, forKey: .minuteOfDay),
            weekdays: (try? container.decode(Set<Int>.self, forKey: .weekdays)) ?? []
        )
    }
}

/// A display that opens a scene when it is connected, by the identifier
/// macOS keeps for it, with its name for the settings.
public struct SceneDisplay: Hashable, Codable, Sendable {
    public var identifier: String
    public var name: String

    public init(identifier: String, name: String) {
        self.identifier = identifier
        self.name = name
    }
}
