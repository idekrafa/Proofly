import Foundation

enum UserDisplayName {
    static func welcomeBackGreeting(
        firstName explicitFirstName: String?,
        displayName: String?
    ) -> String {
        if let firstName = firstName(
            explicitFirstName: explicitFirstName,
            displayName: displayName
        ) {
            return "Welcome back, \(firstName)"
        }

        return "Welcome back"
    }

    static func firstName(
        explicitFirstName: String?,
        displayName: String?
    ) -> String? {
        if let explicitFirstName = sanitizedName(explicitFirstName) {
            return explicitFirstName
        }

        guard let displayName = sanitizedName(displayName) else { return nil }
        return displayName
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)
    }

    static func displayName(_ value: String?) -> String? {
        sanitizedName(value)
    }

    private static func sanitizedName(_ value: String?) -> String? {
        guard let value else { return nil }

        let collapsed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        guard !collapsed.isEmpty else { return nil }
        guard !collapsed.contains("@") else { return nil }
        guard collapsed.rangeOfCharacter(from: .letters) != nil else { return nil }

        return collapsed
    }
}

extension ProofKitAccountSession {
    var welcomeBackGreeting: String {
        UserDisplayName.welcomeBackGreeting(
            firstName: profileFirstName,
            displayName: profileDisplayName
        )
    }
}
