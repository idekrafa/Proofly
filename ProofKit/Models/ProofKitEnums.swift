import Foundation

enum CaseType: String, CaseIterable, Codable, Identifiable {
    case general
    case apartmentIssue
    case unpaidFreelanceWork
    case refundWarrantyIssue
    case workplaceIssue
    case schoolCollegeIssue
    case workFreelanceIssue
    case insuranceIssue
    case smallClaims
    case tenantLandlord
    case employment
    case consumer
    case insurance
    case family
    case immigration
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general:
            String(localized: "General")
        case .apartmentIssue:
            String(localized: "Housing Lease")
        case .unpaidFreelanceWork:
            String(localized: "Work or Freelance Issue")
        case .refundWarrantyIssue:
            String(localized: "Refund or Warranty Issue")
        case .workplaceIssue:
            String(localized: "Work or Freelance Issue")
        case .schoolCollegeIssue:
            String(localized: "School or College Issue")
        case .workFreelanceIssue:
            String(localized: "Work or Freelance Issue")
        case .insuranceIssue:
            String(localized: "Insurance Issue")
        case .smallClaims:
            String(localized: "Small Claims")
        case .tenantLandlord:
            String(localized: "Housing Lease")
        case .employment:
            String(localized: "Employment")
        case .consumer:
            String(localized: "Consumer")
        case .insurance:
            String(localized: "Insurance")
        case .family:
            String(localized: "Family")
        case .immigration:
            String(localized: "Immigration")
        case .other:
            String(localized: "Something Else")
        }
    }
}

enum CaseStatus: String, CaseIterable, Codable, Identifiable {
    case draft
    case active
    case readyForExport
    case exported
    case archived

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .draft:
            String(localized: "Draft")
        case .active:
            String(localized: "Active")
        case .readyForExport:
            String(localized: "Ready for Export")
        case .exported:
            String(localized: "Exported")
        case .archived:
            String(localized: "Archived")
        }
    }
}

enum EvidenceCategory: String, CaseIterable, Codable, Identifiable {
    case uncategorized
    case screenshot
    case photo
    case message
    case email
    case document
    case receipt
    case contract
    case note
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .uncategorized:
            String(localized: "Uncategorized")
        case .screenshot:
            String(localized: "Screenshot")
        case .photo:
            String(localized: "Photo")
        case .message:
            String(localized: "Message")
        case .email:
            String(localized: "Email")
        case .document:
            String(localized: "Document")
        case .receipt:
            String(localized: "Receipt")
        case .contract:
            String(localized: "Contract")
        case .note:
            String(localized: "Note")
        case .other:
            String(localized: "Something Else")
        }
    }

    var requiresEventDateForCompletion: Bool {
        switch self {
        case .document, .contract, .other:
            false
        case .uncategorized, .screenshot, .photo, .message, .email, .receipt, .note:
            true
        }
    }
}

enum AttachmentType: String, CaseIterable, Codable, Identifiable {
    case screenshot
    case photo
    case pdf
    case document
    case textNote
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .screenshot:
            String(localized: "Screenshot")
        case .photo:
            String(localized: "Photo")
        case .pdf:
            String(localized: "PDF")
        case .document:
            String(localized: "Document")
        case .textNote:
            String(localized: "Text Note")
        case .other:
            String(localized: "Something Else")
        }
    }
}

enum AITaskType: String, CaseIterable, Codable, Identifiable {
    case rewriteNote
    case suggestTitle
    case classifyEvidence
    case summarizeItem
    case summarizeTimeline
    case finalCaseNarrative

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rewriteNote:
            String(localized: "Rewrite Note")
        case .suggestTitle:
            String(localized: "Suggest Title")
        case .classifyEvidence:
            String(localized: "Classify Evidence")
        case .summarizeItem:
            String(localized: "Summarize Item")
        case .summarizeTimeline:
            String(localized: "Summarize Timeline")
        case .finalCaseNarrative:
            String(localized: "Final Case Narrative")
        }
    }

    var isCaseLevelTask: Bool {
        switch self {
        case .summarizeTimeline, .finalCaseNarrative:
            true
        case .rewriteNote, .suggestTitle, .classifyEvidence, .summarizeItem:
            false
        }
    }
}

enum DateSource: String, CaseIterable, Codable, Identifiable {
    case notSpecified
    case userEntered
    case fileMetadata
    case filename
    case visionOCR
    case importedMetadata
    case aiSuggested

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notSpecified:
            String(localized: "Not Specified")
        case .userEntered:
            String(localized: "User Entered")
        case .fileMetadata:
            String(localized: "File Metadata")
        case .filename:
            String(localized: "Filename")
        case .visionOCR:
            String(localized: "Vision OCR")
        case .importedMetadata:
            String(localized: "Imported Metadata")
        case .aiSuggested:
            String(localized: "AI Suggested")
        }
    }
}
