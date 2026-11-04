import Foundation

/// Limit Nöbeti: an account the user marked as limited rests until the time
/// they gave, and links meant for it go to the next account of the same
/// kind that is not resting. Nothing is read from Claude; the times are the
/// user's own.
public enum LimitWatch {
    /// Ready-made rest lengths, in hours, for the menus.
    public static let presetHours = [1, 3, 5, 24]

    /// The account that stands in for `profile` while it rests: the next
    /// active account after it in the list, of the same kind, that is not
    /// resting itself. Claude.app's own account is never picked, since
    /// Lanes does not manage it. nil when the account is not resting or no
    /// account can stand in.
    public static func standIn(for profile: Profile, in library: ProfileLibrary, now: Date) -> Profile? {
        guard profile.isResting(at: now) else { return nil }
        return next(after: profile, in: library, now: now) { $0.accountClass == profile.accountClass }
    }

    /// How long an account rests when its session moves to another account
    /// after hitting the limit: Claude's usage window.
    public static let handoffRestHours = 5

    /// The account that continues `profile`'s Claude Code session after it
    /// hit its limit: the next one of the same kind that is not resting,
    /// otherwise the next of any kind (Lanes asks before a session crosses
    /// kinds). Only accounts for which `usable` holds count, such as those
    /// with a Claude Code folder Lanes may copy into. The account need not
    /// be resting yet.
    public static func handoffTarget(for profile: Profile, in library: ProfileLibrary, now: Date, usable: (Profile) -> Bool = { _ in true }) -> Profile? {
        next(after: profile, in: library, now: now) { $0.accountClass == profile.accountClass && usable($0) }
            ?? next(after: profile, in: library, now: now, where: usable)
    }

    /// The next active Lanes account after `profile` in the list, wrapping,
    /// that is not resting and matches. Claude.app's own account is never
    /// picked, since Lanes does not manage it.
    static func next(after profile: Profile, in library: ProfileLibrary, now: Date, where matches: (Profile) -> Bool) -> Profile? {
        let candidates = library.profiles
        guard let start = candidates.firstIndex(where: { $0.id == profile.id }) else { return nil }
        for offset in 1..<max(candidates.count, 1) {
            let candidate = candidates[(start + offset) % candidates.count]
            if candidate.id != profile.id,
               !candidate.isArchived,
               !candidate.isDefault,
               !candidate.isResting(at: now),
               matches(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// The account to use for `profile` now: itself, or its stand-in while
    /// it rests. A resting account with no stand-in is still used, so a
    /// link is never dropped.
    public static func effective(_ profile: Profile, in library: ProfileLibrary, now: Date) -> Profile {
        standIn(for: profile, in: library, now: now) ?? profile
    }

    /// The rest end for a preset, rounded up to the next whole minute.
    public static func until(hours: Int, from now: Date) -> Date {
        let end = now.addingTimeInterval(TimeInterval(hours) * 3600)
        return Date(timeIntervalSinceReferenceDate: (end.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
    }
}
