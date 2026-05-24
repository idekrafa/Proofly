import Foundation
import SwiftData

/// Centralizes ProofKit's account-bound local data locations.
///
/// ProofKit is local-first, but every local database and file directory is scoped
/// by the signed-in account ID. Logging out removes access to that account's
/// local workspace without deleting it; logging back in reopens the same local
/// workspace on this device.
enum AccountScopedLocalData {
    static let schema = Schema([
        CaseFile.self,
        EvidenceItem.self,
        Attachment.self,
        ExportPacket.self,
        AIResultCache.self,
        AIRequestQueueItem.self,
    ])

    static func modelContainer(for session: ProofKitAccountSession) throws -> ModelContainer {
        let storeURL = try swiftDataStoreURL(for: session)
        let configuration = ModelConfiguration(
            "ProofKit-\(accountSlug(for: session))",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func localFilesDirectory(for session: ProofKitAccountSession) throws -> URL {
        let directory = accountDirectory(for: session)
            .appending(path: "Files", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return directory
    }

    private static func swiftDataStoreURL(for session: ProofKitAccountSession) throws -> URL {
        let directory = accountDirectory(for: session)
            .appending(path: "SwiftData", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return directory.appending(path: "ProofKit.store")
    }

    private static func accountDirectory(for session: ProofKitAccountSession) -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "ProofKit", directoryHint: .isDirectory)
            .appending(path: "Accounts", directoryHint: .isDirectory)
            .appending(path: accountSlug(for: session), directoryHint: .isDirectory)
    }

    private static func accountSlug(for session: ProofKitAccountSession) -> String {
        session.userID.uuidString.lowercased()
    }
}
