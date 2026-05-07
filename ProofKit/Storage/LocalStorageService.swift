import CryptoKit
import Foundation
import UIKit
import UniformTypeIdentifiers

protocol LocalStorageServicing {
    func saveEvidenceFile(from sourceURL: URL, kind: AttachmentType, caseID: UUID) async throws -> LocalEvidenceFile
    func saveEvidenceImage(
        data: Data,
        originalFilename: String,
        contentType: UTType?,
        caseID: UUID
    ) async throws -> LocalEvidenceFile
    func saveVaultImage(
        data: Data,
        originalFilename: String,
        contentType: UTType?
    ) async throws -> LocalEvidenceFile
    func deleteEvidenceFile(_ localFile: LocalEvidenceFile) async throws
}

struct LocalStorageService: LocalStorageServicing {
    let baseDirectory: URL

    init(
        baseDirectory: URL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "ProofKit")
    ) {
        self.baseDirectory = baseDirectory
    }

    func saveEvidenceFile(from sourceURL: URL, kind: AttachmentType, caseID: UUID) async throws -> LocalEvidenceFile {
        guard FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) else {
            throw ProofKitError.missingLocalFile(sourceURL)
        }

        let data = try Data(contentsOf: sourceURL)
        let contentType = UTType(filenameExtension: sourceURL.pathExtension)
        return try await saveEvidenceData(
            data,
            originalFilename: sourceURL.lastPathComponent,
            contentType: contentType,
            kind: kind,
            caseID: caseID,
            shouldGenerateThumbnail: contentType?.conforms(to: .image) == true
        )
    }

    func saveEvidenceImage(
        data: Data,
        originalFilename: String,
        contentType: UTType?,
        caseID: UUID
    ) async throws -> LocalEvidenceFile {
        guard UIImage(data: data) != nil else {
            throw ProofKitError.unsupportedFileType(contentType?.identifier ?? "image")
        }

        return try await saveEvidenceData(
            data,
            originalFilename: originalFilename,
            contentType: contentType,
            kind: .photo,
            caseID: caseID,
            shouldGenerateThumbnail: true
        )
    }

    func saveVaultImage(
        data: Data,
        originalFilename: String,
        contentType: UTType?
    ) async throws -> LocalEvidenceFile {
        guard UIImage(data: data) != nil else {
            throw ProofKitError.unsupportedFileType(contentType?.identifier ?? "image")
        }

        let vaultDirectory = baseDirectory.appending(path: "Vault")
        return try await saveLocalData(
            data,
            originalFilename: originalFilename,
            contentType: contentType,
            kind: .photo,
            originalsDirectory: vaultDirectory.appending(path: "Originals"),
            thumbnailsDirectory: vaultDirectory.appending(path: "Thumbnails"),
            shouldGenerateThumbnail: true
        )
    }

    func deleteEvidenceFile(_ localFile: LocalEvidenceFile) async throws {
        try FileManager.default.removeItemIfPresent(at: localFile.url)

        if let thumbnailURL = localFile.thumbnailURL {
            try FileManager.default.removeItemIfPresent(at: thumbnailURL)
        }
    }

    private func saveEvidenceData(
        _ data: Data,
        originalFilename: String,
        contentType: UTType?,
        kind: AttachmentType,
        caseID: UUID,
        shouldGenerateThumbnail: Bool
    ) async throws -> LocalEvidenceFile {
        let caseDirectory = baseDirectory
            .appending(path: "Cases")
            .appending(path: caseID.uuidString)

        return try await saveLocalData(
            data,
            originalFilename: originalFilename,
            contentType: contentType,
            kind: kind,
            originalsDirectory: caseDirectory.appending(path: "Originals"),
            thumbnailsDirectory: caseDirectory.appending(path: "Thumbnails"),
            shouldGenerateThumbnail: shouldGenerateThumbnail
        )
    }

    private func saveLocalData(
        _ data: Data,
        originalFilename: String,
        contentType: UTType?,
        kind: AttachmentType,
        originalsDirectory: URL,
        thumbnailsDirectory: URL,
        shouldGenerateThumbnail: Bool
    ) async throws -> LocalEvidenceFile {
        let fileID = UUID()

        try FileManager.default.createDirectory(
            at: originalsDirectory,
            withIntermediateDirectories: true
        )

        if shouldGenerateThumbnail {
            try FileManager.default.createDirectory(
                at: thumbnailsDirectory,
                withIntermediateDirectories: true
            )
        }

        let safeOriginalFilename = Self.safeFilename(originalFilename)
        let fileExtension = Self.fileExtension(
            from: safeOriginalFilename,
            contentType: contentType,
            fallback: kind == .photo ? "jpg" : "dat"
        )
        let originalURL = originalsDirectory
            .appending(path: fileID.uuidString)
            .appendingPathExtension(fileExtension)

        try data.write(to: originalURL, options: [.atomic])

        let thumbnailURL: URL?
        if shouldGenerateThumbnail, let thumbnailData = Self.thumbnailData(from: data) {
            let destinationURL = thumbnailsDirectory
                .appending(path: fileID.uuidString)
                .appendingPathExtension("jpg")
            try thumbnailData.write(to: destinationURL, options: [.atomic])
            thumbnailURL = destinationURL
        } else {
            thumbnailURL = nil
        }

        return LocalEvidenceFile(
            id: fileID,
            url: originalURL,
            thumbnailURL: thumbnailURL,
            kind: kind,
            originalFilename: safeOriginalFilename,
            uniformTypeIdentifier: contentType?.identifier,
            fileSizeBytes: Int64(data.count),
            contentHash: Self.sha256HexDigest(for: data)
        )
    }

    private static func fileExtension(from filename: String, contentType: UTType?, fallback: String) -> String {
        let filenameExtension = URL(filePath: filename).pathExtension
        if !filenameExtension.isEmpty {
            return filenameExtension
        }

        return contentType?.preferredFilenameExtension ?? fallback
    }

    private static func safeFilename(_ filename: String) -> String {
        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "Imported Image"
        let candidate = trimmedFilename.isEmpty ? fallback : trimmedFilename
        let illegalCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")

        return candidate
            .components(separatedBy: illegalCharacters)
            .joined(separator: "-")
    }

    private static func thumbnailData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let maxPixelLength: CGFloat = 480
        let longestSide = max(image.size.width, image.size.height)
        let scale = longestSide > 0 ? min(maxPixelLength / longestSide, 1) : 1
        let targetSize = CGSize(
            width: max(image.size.width * scale, 1),
            height: max(image.size.height * scale, 1)
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return thumbnail.jpegData(compressionQuality: 0.78)
    }

    private static func sha256HexDigest(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension FileManager {
    func removeItemIfPresent(at url: URL) throws {
        guard fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try removeItem(at: url)
    }
}
