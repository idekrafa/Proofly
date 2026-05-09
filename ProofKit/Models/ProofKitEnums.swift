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
            "General"
        case .apartmentIssue:
            "Housing Lease"
        case .unpaidFreelanceWork:
            "Work or Freelance Issue"
        case .refundWarrantyIssue:
            "Refund or Warranty Issue"
        case .workplaceIssue:
            "Work or Freelance Issue"
        case .schoolCollegeIssue:
            "School or College Issue"
        case .workFreelanceIssue:
            "Work or Freelance Issue"
        case .insuranceIssue:
            "Insurance Issue"
        case .smallClaims:
            "Small Claims"
        case .tenantLandlord:
            "Housing Lease"
        case .employment:
            "Employment"
        case .consumer:
            "Consumer"
        case .insurance:
            "Insurance"
        case .family:
            "Family"
        case .immigration:
            "Immigration"
        case .other:
            "Something Else"
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
            "Draft"
        case .active:
            "Active"
        case .readyForExport:
            "Ready for Export"
        case .exported:
            "Exported"
        case .archived:
            "Archived"
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
            "Uncategorized"
        case .screenshot:
            "Screenshot"
        case .photo:
            "Photo"
        case .message:
            "Message"
        case .email:
            "Email"
        case .document:
            "Document"
        case .receipt:
            "Receipt"
        case .contract:
            "Contract"
        case .note:
            "Note"
        case .other:
            "Something Else"
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
            "Screenshot"
        case .photo:
            "Photo"
        case .pdf:
            "PDF"
        case .document:
            "Document"
        case .textNote:
            "Text Note"
        case .other:
            "Something Else"
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
            "Rewrite Note"
        case .suggestTitle:
            "Suggest Title"
        case .classifyEvidence:
            "Classify Evidence"
        case .summarizeItem:
            "Summarize Item"
        case .summarizeTimeline:
            "Summarize Timeline"
        case .finalCaseNarrative:
            "Final Case Narrative"
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
            "Not Specified"
        case .userEntered:
            "User Entered"
        case .fileMetadata:
            "File Metadata"
        case .filename:
            "Filename"
        case .visionOCR:
            "Vision OCR"
        case .importedMetadata:
            "Imported Metadata"
        case .aiSuggested:
            "AI Suggested"
        }
    }
}
