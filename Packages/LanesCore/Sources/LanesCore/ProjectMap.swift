import Foundation

/// Whether Claude Code is busy in an account right now, guessed from when
/// its session files last changed. Only file dates are read, never their
/// contents, so the state is an estimate and the app labels it as one.
public enum ClaudeCodePulse: String, Equatable, Sendable {
    /// A session file changed in the last few seconds: Claude Code is
    /// writing, so it is most likely working.
    case working
    /// A session changed in the last minutes: Claude Code is probably open
    /// and waiting for the user.
    case recent
    case idle

    /// Seconds after the last write that still count as working.
    public static let workingWindow: TimeInterval = 20
    /// Seconds after the last write that still count as recent.
    public static let recentWindow: TimeInterval = 10 * 60

    public static func pulse(lastWrite: Date?, now: Date) -> ClaudeCodePulse {
        guard let lastWrite else { return .idle }
        let age = now.timeIntervalSince(lastWrite)
        // A date slightly in the future (clock skew, a file touched by
        // another Mac) still counts as just written.
        if age < workingWindow { return .working }
        if age < recentWindow { return .recent }
        return .idle
    }
}

/// Claude Code projects across every account: which accounts worked in each
/// project folder, how often and when. Built from session file names and
/// dates only.
public struct ProjectMap: Equatable, Sendable {
    /// One account's sessions in one project.
    public struct Use: Equatable, Sendable {
        public var profileID: ProfileID
        public var sessionCount: Int
        public var lastUsed: Date
        /// The newest session, for "Sürdür".
        public var newestSessionID: String
    }

    public struct Project: Equatable, Sendable, Identifiable {
        /// Claude Code's encoded folder name, the same in every account for
        /// the same project path.
        public var folderName: String
        /// Newest first.
        public var uses: [Use]

        public var id: String { folderName }
        public var lastUsed: Date { uses.map(\.lastUsed).max() ?? .distantPast }
        public var sessionCount: Int { uses.reduce(0) { $0 + $1.sessionCount } }
        /// More than one account worked in this folder.
        public var isShared: Bool { uses.count > 1 }

        /// Accounts of different kinds (say an employer and a personal
        /// account) worked in this folder, which may mix their data.
        public func mixesClasses(_ classOf: (ProfileID) -> AccountClass?) -> Bool {
            Set(uses.compactMap { classOf($0.profileID) }).count > 1
        }
    }

    /// Newest first.
    public var projects: [Project]

    public init(projects: [Project]) {
        self.projects = projects.sorted { lhs, rhs in
            lhs.lastUsed != rhs.lastUsed ? lhs.lastUsed > rhs.lastUsed : lhs.folderName < rhs.folderName
        }
    }

    /// Groups each account's sessions by project folder. An account listed
    /// twice (two profiles on the same Claude Code folder) counts once.
    public init(lists: [(profileID: ProfileID, sessions: ClaudeCodeSessionList)]) {
        var byFolder: [String: [ProfileID: Use]] = [:]
        for (profileID, list) in lists {
            for session in list.sessions {
                var uses = byFolder[session.projectFolderName] ?? [:]
                if var use = uses[profileID] {
                    use.sessionCount += 1
                    if session.modifiedAt > use.lastUsed {
                        use.lastUsed = session.modifiedAt
                        use.newestSessionID = session.id
                    }
                    uses[profileID] = use
                } else {
                    uses[profileID] = Use(profileID: profileID, sessionCount: 1, lastUsed: session.modifiedAt, newestSessionID: session.id)
                }
                byFolder[session.projectFolderName] = uses
            }
        }
        let projects = byFolder.map { folderName, uses in
            Project(
                folderName: folderName,
                uses: uses.values.sorted { lhs, rhs in
                    lhs.lastUsed != rhs.lastUsed ? lhs.lastUsed > rhs.lastUsed : lhs.profileID.rawValue < rhs.profileID.rawValue
                }
            )
        }
        self.init(projects: projects)
    }
}
