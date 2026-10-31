import AppKit
import CoreSpotlight
import LanesCore
import UniformTypeIdentifiers

/// Puts the accounts in Spotlight, so typing an account's name opens it
/// through Lanes. Only the name, a short description and the letter icon
/// are indexed.
enum SpotlightIndex {
    static let domain = "accounts"
    private static let prefix = "lanes.account."

    static func update(_ profiles: [Profile]) {
        // Replace the whole domain, so removed and renamed accounts go away.
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            CSSearchableIndex.default().indexSearchableItems(items(for: profiles)) { error in
                if let error {
                    Log.app.error("Spotlight index failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private static func items(for profiles: [Profile]) -> [CSSearchableItem] {
        profiles.map { profile in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = profile.name
            attributes.displayName = profile.name
            attributes.contentDescription = profile.isDefault
                ? String(localized: "Claude uygulamasının hesabı · Lanes")
                : String(localized: "Claude hesabı · Lanes")
            attributes.keywords = ["Claude", "Lanes", profile.name]
            let icon = MonogramIcon.image(for: profile, size: 128)
            if let tiff = icon.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
                attributes.thumbnailData = bitmap.representation(using: .png, properties: [:])
            }
            return CSSearchableItem(uniqueIdentifier: prefix + profile.id.rawValue, domainIdentifier: domain, attributeSet: attributes)
        }
    }

    /// The account a Spotlight result stands for.
    static func profileID(from activity: NSUserActivity) -> ProfileID? {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              identifier.hasPrefix(prefix) else { return nil }
        return ProfileID(rawValue: String(identifier.dropFirst(prefix.count)))
    }
}
