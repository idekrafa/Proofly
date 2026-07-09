import Foundation
import SwiftData

@Model
final class EvidenceItem {
    @Attribute(.unique) var id: UUID

    var categoryRawValue: String
    var userDateSourceRawValue: String

    // User-authored source-of-truth fields.
    var userTitle: String
    var userNotes: String
    var userCleanedNote: String = ""
    var userWhyThisMatters: String = ""
    var userProvidedEventDate: Date?
    var userMarkedImportant: Bool = false
    var isReviewed: Bool = false
    var reviewedAt: Date?

    // Local, non-AI date detections. These are suggestions only and never
    // overwrite the user-provided event date.
    var detectedEventDate: Date?
    var detectedDateSourceRawValue: String?
    var dateCandidatesJSON: String = "[]"

    // OCR source-of-truth fields from local Apple Vision OCR.
    // These preserve the original OCR output separately from any AI interpretation.
    var originalOCRText: String
    var originalOCRTextBlocksJSON: String = "[]"
    var originalOCRLanguageCode: String?
    var originalOCRConfidence: Double?
    var originalOCRCompletedAt: Date?

    // AI-generated fields must never replace userTitle/userNotes/originalOCRText.
    var aiSuggestedTitle: String?
    var aiGeneratedSummary: String?
    var aiSuggestedCategoryRawValue: String?
    var aiSuggestedEventDate: Date?
    var aiSuggestedDateSourceRawValue: String?
    var aiExtractedMetadataJSON: String?

    var createdAt: Date
    var updatedAt: Date
    var sortIndex: Int

    var caseFile: CaseFile?

    @Relationship(deleteRule: .cascade, inverse: \Attachment.evidenceItem)
    var attachments: [Attachment]

    init(
        id: UUID = UUID(),
        category: EvidenceCategory = .uncategorized,
        userDateSource: DateSource = .notSpecified,
        userTitle: String,
        userNotes: String = "",
        userCleanedNote: String = "",
        userWhyThisMatters: String = "",
        userProvidedEventDate: Date? = nil,
        userMarkedImportant: Bool = false,
        isReviewed: Bool = false,
        reviewedAt: Date? = nil,
        detectedEventDate: Date? = nil,
        detectedDateSource: DateSource? = nil,
        dateCandidatesJSON: String = "[]",
        originalOCRText: String = "",
        originalOCRTextBlocksJSON: String = "[]",
        originalOCRLanguageCode: String? = nil,
        originalOCRConfidence: Double? = nil,
        originalOCRCompletedAt: Date? = nil,
        aiSuggestedTitle: String? = nil,
        aiGeneratedSummary: String? = nil,
        aiSuggestedCategory: EvidenceCategory? = nil,
        aiSuggestedEventDate: Date? = nil,
        aiSuggestedDateSource: DateSource? = nil,
        aiExtractedMetadataJSON: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sortIndex: Int = 0,
        caseFile: CaseFile? = nil,
        attachments: [Attachment] = []
    ) {
        self.id = id
        self.categoryRawValue = category.rawValue
        self.userDateSourceRawValue = userDateSource.rawValue
        self.userTitle = userTitle
        self.userNotes = userNotes
        self.userCleanedNote = userCleanedNote
        self.userWhyThisMatters = userWhyThisMatters
        self.userProvidedEventDate = userProvidedEventDate
        self.userMarkedImportant = userMarkedImportant
        self.isReviewed = isReviewed
        self.reviewedAt = reviewedAt
        self.detectedEventDate = detectedEventDate
        self.detectedDateSourceRawValue = detectedDateSource?.rawValue
        self.dateCandidatesJSON = dateCandidatesJSON
        self.originalOCRText = originalOCRText
        self.originalOCRTextBlocksJSON = originalOCRTextBlocksJSON
        self.originalOCRLanguageCode = originalOCRLanguageCode
        self.originalOCRConfidence = originalOCRConfidence
        self.originalOCRCompletedAt = originalOCRCompletedAt
        self.aiSuggestedTitle = aiSuggestedTitle
        self.aiGeneratedSummary = aiGeneratedSummary
        self.aiSuggestedCategoryRawValue = aiSuggestedCategory?.rawValue
        self.aiSuggestedEventDate = aiSuggestedEventDate
        self.aiSuggestedDateSourceRawValue = aiSuggestedDateSource?.rawValue
        self.aiExtractedMetadataJSON = aiExtractedMetadataJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortIndex = sortIndex
        self.caseFile = caseFile
        self.attachments = attachments
    }

    var category: EvidenceCategory {
        get { EvidenceCategory(rawValue: categoryRawValue) ?? .uncategorized }
        set { categoryRawValue = newValue.rawValue }
    }

    var userDateSource: DateSource {
        get { DateSource(rawValue: userDateSourceRawValue) ?? .notSpecified }
        set { userDateSourceRawValue = newValue.rawValue }
    }

    var detectedDateSource: DateSource? {
        get {
            guard let detectedDateSourceRawValue else { return nil }
            return DateSource(rawValue: detectedDateSourceRawValue)
        }
        set {
            detectedDateSourceRawValue = newValue?.rawValue
        }
    }

    var dateCandidates: [DateCandidate] {
        get {
            DateCandidate.decodeArray(from: dateCandidatesJSON)
        }
        set {
            dateCandidatesJSON = DateCandidate.encodeArray(newValue)
        }
    }

    var eventDate: Date? {
        userProvidedEventDate ?? detectedEventDate ?? aiSuggestedEventDate
    }

    var eventDateSource: DateSource {
        if userProvidedEventDate != nil {
            return userDateSource
        }

        if let detectedDateSource {
            return detectedDateSource
        }

        if aiSuggestedEventDate != nil {
            return aiSuggestedDateSource ?? .aiSuggested
        }

        return .notSpecified
    }

    var requiresEventDateForCompletion: Bool {
        category.requiresEventDateForCompletion
    }

    // Convenience alias requested by the UI/import flow. The persisted source of
    // truth remains originalOCRText so local OCR never overwrites user-authored notes.
    var ocrText: String {
        get { originalOCRText }
        set { originalOCRText = newValue }
    }

    var aiSuggestedCategory: EvidenceCategory? {
        get {
            guard let aiSuggestedCategoryRawValue else { return nil }
            return EvidenceCategory(rawValue: aiSuggestedCategoryRawValue)
        }
        set {
            aiSuggestedCategoryRawValue = newValue?.rawValue
        }
    }

    var aiSuggestedDateSource: DateSource? {
        get {
            guard let aiSuggestedDateSourceRawValue else { return nil }
            return DateSource(rawValue: aiSuggestedDateSourceRawValue)
        }
        set {
            aiSuggestedDateSourceRawValue = newValue?.rawValue
        }
    }

    var sortedAttachments: [Attachment] {
        attachments.sorted { lhs, rhs in
            lhs.createdAt < rhs.createdAt
        }
    }

    var isIncompleteForReview: Bool {
        userTitle.reviewTrimmedText.isEmpty ||
            category == .uncategorized ||
            (requiresEventDateForCompletion && eventDate == nil)
    }

    var needsReview: Bool {
        !isReviewed || isIncompleteForReview
    }

    var searchableSourceText: String {
        [userNotes, userCleanedNote, userWhyThisMatters, originalOCRText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

private extension String {
    var reviewTrimmedText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
