import Foundation

struct ManagedProject: Identifiable, Codable {
    let id: UUID
    var name: String
    var projectPath: URL
    var lastBuiltAt: Date?
    var lastError: String?
    var profileExpiresAt: Date?
    var isBuilding: Bool = false
    var buildPhase: String?
    /// Set when the most recent rebuild succeeded but Apple returned the same
    /// provisioning profile (expiry didn't advance). The build itself is fine;
    /// this surfaces "Apple said meh, rerun in Xcode or try again later."
    var stuckOnOldProfile: Bool = false
    /// Ignored by the user: skipped by automatic rebuilds, still buildable on
    /// demand via Rebuild. Defaults false so existing projects.json decodes.
    var isHidden: Bool = false

    var nextDueAt: Date? {
        if let profileExpiresAt {
            // Rebuild a minute after the profile expires, not before. Xcode
            // signs with its cached profile until that one expires, so any
            // earlier rebuild gets the same profile back and only reinstalls
            // the app. (Timekeep rebuilt for days on one profile; Ansa got a
            // fresh one from the build that ran the minute its old one ran out.)
            return profileExpiresAt.addingTimeInterval(60)
        }
        guard let last = lastBuiltAt else { return .now }
        return Calendar.current.date(byAdding: .day, value: 6, to: last)
    }

    var isDue: Bool {
        guard let next = nextDueAt else { return true }
        return next <= .now
    }

    /// The app on the device no longer launches. Without a known expiry, assume
    /// the free-tier 7 days. Never built means nothing on the device to expire.
    var isExpired: Bool {
        if let profileExpiresAt { return profileExpiresAt <= .now }
        guard let last = lastBuiltAt else { return false }
        return Calendar.current.date(byAdding: .day, value: 7, to: last).map { $0 <= .now } ?? false
    }

    var daysUntilExpiry: Int {
        guard let profileExpiresAt else {
            guard let last = lastBuiltAt else { return 0 }
            return DateHelpers.daysUntilExpiry(from: last)
        }
        return max(0, Calendar.current.dateComponents([.day], from: .now, to: profileExpiresAt).day ?? 0)
    }

    var expiryLabel: String? {
        guard let profileExpiresAt else {
            guard let last = lastBuiltAt else { return nil }
            let days = DateHelpers.daysUntilExpiry(from: last)
            return "exp ~\(DateHelpers.expiryDate(from: last)) (~\(days)d left)"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let dateStr = formatter.string(from: profileExpiresAt)
        return "exp \(dateStr) (\(daysUntilExpiry)d left)"
    }

    // Persisted fields. isBuilding and buildPhase are deliberately absent:
    // they're transient and must not survive a restart. isHidden must.
    enum CodingKeys: String, CodingKey {
        case id, name, projectPath, lastBuiltAt, lastError, profileExpiresAt, stuckOnOldProfile
        case isHidden
    }
}
