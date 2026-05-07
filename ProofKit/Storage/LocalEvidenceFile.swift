import Foundation

struct LocalEvidenceFile: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let thumbnailURL: URL?
    let kind: AttachmentType
    let originalFilename: String
    let uniformTypeIdentifier: String?
    let fileSizeBytes: Int64
    let contentHash: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        url: URL,
        thumbnailURL: URL? = nil,
        kind: AttachmentType,
        originalFilename: String,
        uniformTypeIdentifier: String? = nil,
        fileSizeBytes: Int64,
        contentHash: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.kind = kind
        self.originalFilename = originalFilename
        self.uniformTypeIdentifier = uniformTypeIdentifier
        self.fileSizeBytes = fileSizeBytes
        self.contentHash = contentHash
        self.createdAt = createdAt
    }
}
