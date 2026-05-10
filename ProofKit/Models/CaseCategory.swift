import Foundation

enum CaseCategory: String, CaseIterable, Identifiable, Hashable {
    case apartmentIssue = "apartment_issue"
    case refundWarrantyIssue = "refund_warranty_issue"
    case schoolCollegeIssue = "school_college_issue"
//    case workFreelanceIssue = "work_freelance_issue"
    case other = "other"

    var id: String { rawValue }

    static var sharedOptions: [CaseCategory] { allCases }

    static func category(forID id: String) -> CaseCategory? {
        let normalizedID = id
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if let category = allCases.first(where: { $0.rawValue == normalizedID }) {
            return category
        }

        switch normalizedID {
        case "rental", "rent", "lease", "housinglease", "housing_lease", "tenantlandlord", "tenant_landlord", "apartment", "apartmentissue", "apartment_issue":
            return .apartmentIssue
        case "refund", "warranty", "refundwarranty", "refund_warranty", "refundwarrantyissue", "refund_warranty_issue":
            return .refundWarrantyIssue
        case "college", "school", "university", "schoolcollege", "school_college", "schoolcollegeissue", "school_college_issue":
            return .schoolCollegeIssue
//        case "work", "freelance", "employment", "workplace", "workplaceissue", "workplace_issue", "unpaidfreelancework", "unpaid_freelance_work", "workfreelance", "work_freelance", "workfreelanceissue", "work_freelance_issue":
//            return .workFreelanceIssue
        case "general", "something_else", "not_sure_yet", "other":
            return .other
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .apartmentIssue:
            "Housing lease"
        case .refundWarrantyIssue:
            "Refund or warranty issue"
        case .schoolCollegeIssue:
            "School or college issue"
//        case .workFreelanceIssue:
//            "Work or freelance issue"
        case .other:
            "Something else"
        }
    }

    var description: String {
        switch self {
        case .apartmentIssue:
            "Lease documents, applications, messages, rent records, photos, or move-in details."
        case .refundWarrantyIssue:
            "Receipts, product photos, support messages, and warranty records."
        case .schoolCollegeIssue:
            "Emails, assignments, forms, notes, and school records."
//        case .workFreelanceIssue:
//            "Contracts, invoices, schedules, messages, and payment records."
        case .other:
            "Use Proofly for any situation where you need a clean proof timeline."
        }
    }

    var onboardingPurposeTitle: String {
        switch self {
        case .apartmentIssue:
            "Housing lease"
        case .refundWarrantyIssue:
            "Get a refund"
        case .schoolCollegeIssue:
            "Apply to college"
//        case .workFreelanceIssue:
//            "Get paid for work"
        case .other:
            "Not sure yet?"
        }
    }

    var onboardingPurposeOutcome: String {
        switch self {
        case .apartmentIssue:
            "Create a clean rental-ready document packet."
        case .refundWarrantyIssue:
            "Organize receipts, screenshots, and messages."
        case .schoolCollegeIssue:
            "Keep essays, transcripts, and deadlines together."
//        case .workFreelanceIssue:
//            "Organize contracts, invoices, and messages."
        case .other:
            "Proofly has your back —\norganize proof for whatever\nlife throws at you."
        }
    }

    var iconName: String {
        switch self {
        case .apartmentIssue:
            "house.fill"
        case .refundWarrantyIssue:
            "cart.fill"
        case .schoolCollegeIssue:
            "graduationcap.fill"
//        case .workFreelanceIssue:
//            "briefcase.fill"
        case .other:
            "folder.fill"
        }
    }

    var rookAssetName: String? {
        switch self {
        case .apartmentIssue:
            "RookPurposeRental"
        case .refundWarrantyIssue:
            "RookPurposeRefund"
        case .schoolCollegeIssue:
            "RookPurposeCollege"
//        case .workFreelanceIssue:
//            nil
        case .other:
            "RookPurposeOther"
        }
    }

    var starterTitle: String {
        switch self {
        case .apartmentIssue:
            "Housing lease timeline"
        case .refundWarrantyIssue:
            "Refund or warranty timeline"
        case .schoolCollegeIssue:
            "School issue timeline"
//        case .workFreelanceIssue:
//            "Work issue timeline"
        case .other:
            "Proof timeline"
        }
    }

    var starterDescription: String {
        switch self {
        case .apartmentIssue:
            "Track lease details, applications, messages, rent records, photos, and move-in or move-out details."
        case .refundWarrantyIssue:
            "Track receipts, product photos, support messages, and warranty records."
        case .schoolCollegeIssue:
            "Track emails, assignments, forms, notes, and school records."
//        case .workFreelanceIssue:
//            "Track contracts, invoices, schedules, messages, and payment records."
        case .other:
            "Track screenshots, notes, documents, and important records."
        }
    }

    var caseType: CaseType {
        switch self {
        case .apartmentIssue:
            .apartmentIssue
        case .refundWarrantyIssue:
            .refundWarrantyIssue
        case .schoolCollegeIssue:
            .schoolCollegeIssue
//        case .workFreelanceIssue:
//            .workFreelanceIssue
        case .other:
            .other
        }
    }

    var selectedCategoryNotesLine: String {
        "Selected category: \(title)"
    }

    var suggestedEvidence: [String] {
        switch self {
        case .apartmentIssue:
            [
                "Lease or application documents",
                "Messages with your landlord or property manager",
                "Rent records",
                "Photos or videos",
                "Move-in or move-out details"
            ]
        case .refundWarrantyIssue:
            [
                "Receipts",
                "Product photos",
                "Support messages",
                "Warranty records"
            ]
        case .schoolCollegeIssue:
            [
                "Emails",
                "Assignments",
                "Forms",
                "Notes",
                "School records"
            ]
//        case .workFreelanceIssue:
//            [
//                "Contracts",
//                "Invoices",
//                "Schedules",
//                "Messages",
//                "Payment records"
//            ]
        case .other:
            [
                "Screenshots",
                "Notes",
                "Documents",
                "Important records"
            ]
        }
    }

    var firstCaseSeed: ProofKitOnboardingFirstCaseSeed {
        ProofKitOnboardingFirstCaseSeed(
            id: id,
            title: starterTitle,
            caseType: caseType,
            caseTypeLabel: title,
            summary: starterDescription,
            suggestedEvidence: suggestedEvidence,
            prompt: self == .other ? "Start by answering: What happened?" : nil
        )
    }

    static func firstCaseSeed(for id: String) -> ProofKitOnboardingFirstCaseSeed? {
        category(forID: id)?.firstCaseSeed
    }
}

struct ProofKitOnboardingFirstCaseSeed: Hashable, Identifiable {
    let id: String
    let title: String
    let caseType: CaseType
    let caseTypeLabel: String
    let summary: String
    let suggestedEvidence: [String]
    let prompt: String?

    var notesText: String {
        notesText(details: "")
    }

    func notesText(details: String) -> String {
        var sections: [String] = []
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)

        sections.append("Selected category: \(caseTypeLabel)")

        if !trimmedDetails.isEmpty {
            sections.append("What happened:\n\(trimmedDetails)")
        }

        if let prompt {
            sections.append(prompt)
        }

        if !suggestedEvidence.isEmpty {
            let bullets = suggestedEvidence
                .map { "• \($0)" }
                .joined(separator: "\n")
            sections.append("Suggested evidence:\n\(bullets)")
        }

        return sections.joined(separator: "\n\n")
    }
}
