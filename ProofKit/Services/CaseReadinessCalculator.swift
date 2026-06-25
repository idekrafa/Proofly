import Foundation

struct CaseReadinessResult: Equatable {
    let score: Int
    let nextStepLabel: String
    let readinessBucket: String
    let blockers: [String]
    let counts: CaseReadinessCounts
    let signals: CaseReadinessSignals
    let category: CaseReadinessCategory

    var progress: Double {
        Double(score) / 100
    }

    var analyticsSignature: String {
        [
            "\(score)",
            nextStepLabel,
            readinessBucket,
            category.analyticsValue,
            "\(counts.proofItemCount)",
            "\(counts.reviewedItemCount)",
            "\(counts.skippedItemCount)",
            "\(counts.unreviewedItemCount)",
            "\(counts.timelineItemCount)",
            "\(counts.datedTimelineItemCount)",
            "\(counts.generatedExportCount)",
            "\(signals.hasTitle)",
            "\(signals.hasSelectedCategory)",
            "\(signals.hasDescription)",
            "\(signals.hasTimelineDate)",
            "\(signals.hasTimelineDepthOrStrongItem)",
            "\(signals.hasExportablePDF)",
            "\(signals.hasGeneratedExport)"
        ].joined(separator: "|")
    }

}

struct CaseReadinessCounts: Equatable {
    let proofItemCount: Int
    let reviewedItemCount: Int
    let skippedItemCount: Int
    let unreviewedItemCount: Int
    let timelineItemCount: Int
    let datedTimelineItemCount: Int
    let generatedExportCount: Int
}

struct CaseReadinessSignals: Equatable {
    let hasTitle: Bool
    let hasSelectedCategory: Bool
    let hasDescription: Bool
    let hasAtLeastOneProofItem: Bool
    let hasAtLeastTwoProofItems: Bool
    let hasProofTextOrManualNote: Bool
    let hasNoUnreviewedImportedItems: Bool
    let allProofItemsHandled: Bool
    let hasTimelineDate: Bool
    let hasTimelineDepthOrStrongItem: Bool
    let importantItemsHaveLabels: Bool
    let hasExportablePDF: Bool
    let packetIncludesIndexTimeline: Bool
    let statementSettingChosenOrDefaulted: Bool
    let hasGeneratedExport: Bool
}

struct CaseReadinessCategory: Equatable {
    let displayName: String
    let analyticsValue: String
    let isSelected: Bool
    let isSchool: Bool
}

enum CaseReadinessCalculator {
    static func calculate(
        for caseFile: CaseFile,
        skippedEvidenceIDs: Set<UUID> = []
    ) -> CaseReadinessResult {
        let category = caseFile.caseReadinessCategory
        let evidenceItems = caseFile.evidenceItems
        let activeSkippedIDs = Set(evidenceItems.map(\.id)).intersection(skippedEvidenceIDs)
        let proofItemCount = evidenceItems.count
        let reviewedItemCount = evidenceItems.filter(\.isReviewed).count
        let dateRequiredTimelineItemCount = evidenceItems.filter(\.requiresEventDateForCompletion).count
        let unreviewedItems = evidenceItems.filter { evidenceItem in
            evidenceItem.needsReview && !activeSkippedIDs.contains(evidenceItem.id)
        }
        let datedTimelineItemCount = evidenceItems.filter { $0.eventDate != nil }.count
        let generatedExportCount = caseFile.exportPackets.filter { exportPacket in
            exportPacket.exportedAt != nil && exportPacket.localPDFFilePath != nil
        }.count

        let hasTitle = !caseFile.userTitle.readinessTrimmedText.isEmpty
        let hasDescription = !caseFile.userSummary.readinessTrimmedText.isEmpty ||
            !caseFile.userNotes.readinessTrimmedText.isEmpty
        let hasAtLeastOneProofItem = proofItemCount >= 1
        let hasAtLeastTwoProofItems = proofItemCount >= 2
        let hasProofTextOrManualNote = evidenceItems.contains(where: \.hasReadinessTextOrManualNote)
        let hasNoUnreviewedImportedItems = unreviewedItems.isEmpty
        let allProofItemsHandled = proofItemCount > 0 && unreviewedItems.isEmpty
        let hasDateRequiredTimelineItems = dateRequiredTimelineItemCount > 0
        let hasTimelineDate = !hasDateRequiredTimelineItems || datedTimelineItemCount > 0
        let hasTimelineDepthOrStrongItem = !hasDateRequiredTimelineItems ||
            datedTimelineItemCount >= 2 ||
            evidenceItems.contains(where: \.isStrongReadinessTimelineItem)
        let importantItemsHaveLabels = evidenceItems.importantReadinessItemsHaveLabels
        let hasExportablePDF = hasTitle && proofItemCount > 0 && unreviewedItems.isEmpty
        let packetIncludesIndexTimeline = proofItemCount > 0
        let statementSettingChosenOrDefaulted = true
        let hasGeneratedExport = generatedExportCount > 0

        let signals = CaseReadinessSignals(
            hasTitle: hasTitle,
            hasSelectedCategory: category.isSelected,
            hasDescription: hasDescription,
            hasAtLeastOneProofItem: hasAtLeastOneProofItem,
            hasAtLeastTwoProofItems: hasAtLeastTwoProofItems,
            hasProofTextOrManualNote: hasProofTextOrManualNote,
            hasNoUnreviewedImportedItems: hasNoUnreviewedImportedItems,
            allProofItemsHandled: allProofItemsHandled,
            hasTimelineDate: hasTimelineDate,
            hasTimelineDepthOrStrongItem: hasTimelineDepthOrStrongItem,
            importantItemsHaveLabels: importantItemsHaveLabels,
            hasExportablePDF: hasExportablePDF,
            packetIncludesIndexTimeline: packetIncludesIndexTimeline,
            statementSettingChosenOrDefaulted: statementSettingChosenOrDefaulted,
            hasGeneratedExport: hasGeneratedExport
        )

        var score = 0
        score += hasTitle ? 8 : 0
        score += category.isSelected ? 6 : 0
        score += hasDescription ? 6 : 0

        score += hasAtLeastOneProofItem ? 10 : 0
        score += hasAtLeastTwoProofItems ? 8 : 0
        score += hasProofTextOrManualNote ? 7 : 0

        score += hasNoUnreviewedImportedItems ? 12 : 0
        score += allProofItemsHandled ? 8 : 0

        score += hasTimelineDate ? 7 : 0
        score += hasTimelineDepthOrStrongItem ? 7 : 0
        score += importantItemsHaveLabels ? 6 : 0

        score += hasExportablePDF ? 8 : 0
        score += packetIncludesIndexTimeline ? 4 : 0
        score += statementSettingChosenOrDefaulted ? 3 : 0

        score = min(max(score, 0), 100)

        let blockers = blockers(for: signals, proofItemCount: proofItemCount)
        let nextStepLabel = nextStepLabel(
            score: score,
            signals: signals,
            proofItemCount: proofItemCount,
            unreviewedItemCount: unreviewedItems.count
        )

        return CaseReadinessResult(
            score: score,
            nextStepLabel: nextStepLabel,
            readinessBucket: readinessBucket(for: score),
            blockers: blockers,
            counts: CaseReadinessCounts(
                proofItemCount: proofItemCount,
                reviewedItemCount: reviewedItemCount,
                skippedItemCount: activeSkippedIDs.count,
                unreviewedItemCount: unreviewedItems.count,
                timelineItemCount: proofItemCount,
                datedTimelineItemCount: datedTimelineItemCount,
                generatedExportCount: generatedExportCount
            ),
            signals: signals,
            category: category
        )
    }

    private static func readinessBucket(for score: Int) -> String {
        switch score {
        case 0...24:
            "0–24% ready"
        case 25...49:
            "25–49% ready"
        case 50...74:
            "50–74% ready"
        case 75...99:
            "75–99% ready"
        default:
            "100% ready"
        }
    }

    private static func nextStepLabel(
        score: Int,
        signals: CaseReadinessSignals,
        proofItemCount: Int,
        unreviewedItemCount: Int
    ) -> String {
        if !signals.hasTitle || !signals.hasSelectedCategory {
            return String(localized: "Next: Finish case details")
        }

        if proofItemCount == 0 {
            return String(localized: "Next: Add proof")
        }

        if unreviewedItemCount > 0 {
            return String(localized: "Next: Review inbox")
        }

        if !signals.hasTimelineDate || !signals.hasTimelineDepthOrStrongItem {
            return String(localized: "Next: Check timeline")
        }

        if signals.hasGeneratedExport && score == 100 {
            return String(localized: "Packet generated")
        }

        return String(localized: "Next: Export packet")
    }

    private static func blockers(
        for signals: CaseReadinessSignals,
        proofItemCount: Int
    ) -> [String] {
        var items: [String] = []

        if !signals.hasTitle {
            items.append(String(localized: "case title"))
        }

        if !signals.hasSelectedCategory {
            items.append(String(localized: "case category"))
        }

        if !signals.hasDescription {
            items.append(String(localized: "short context"))
        }

        if proofItemCount == 0 {
            items.append(String(localized: "proof items"))
        }

        if !signals.hasNoUnreviewedImportedItems {
            items.append(String(localized: "review inbox"))
        }

        if proofItemCount > 0, !signals.hasTimelineDate {
            items.append(String(localized: "timeline dates"))
        }

        if proofItemCount > 0, !signals.hasTimelineDepthOrStrongItem {
            items.append(String(localized: "timeline detail"))
        }

        if proofItemCount > 0, !signals.importantItemsHaveLabels {
            items.append(String(localized: "item labels"))
        }

        return Array(items.prefix(3))
    }
}

extension CaseFile {
    var caseReadinessCategory: CaseReadinessCategory {
        let onboardingCategory = readinessOnboardingCategory

        if let normalized = onboardingCategory?.readinessNormalizedCategory {
            return normalized
        }

        switch caseType {
        case .apartmentIssue, .tenantLandlord:
            return CaseReadinessCategory(
                displayName: String(localized: "Housing lease"),
                analyticsValue: "apartment",
                isSelected: true,
                isSchool: false
            )
        case .refundWarrantyIssue, .consumer:
            return CaseReadinessCategory(
                displayName: String(localized: "Refund"),
                analyticsValue: "refund",
                isSelected: true,
                isSchool: false
            )
        case .schoolCollegeIssue:
            return CaseReadinessCategory(
                displayName: String(localized: "School"),
                analyticsValue: "school",
                isSelected: true,
                isSchool: true
            )
        case .unpaidFreelanceWork, .workplaceIssue, .workFreelanceIssue, .employment:
            return CaseReadinessCategory(
                displayName: String(localized: "Work"),
                analyticsValue: "work",
                isSelected: true,
                isSchool: false
            )
        case .insuranceIssue, .insurance:
            return CaseReadinessCategory(
                displayName: String(localized: "Insurance"),
                analyticsValue: "insurance",
                isSelected: true,
                isSchool: false
            )
        case .smallClaims:
            return CaseReadinessCategory(
                displayName: String(localized: "Small Claims"),
                analyticsValue: "small_claims",
                isSelected: true,
                isSchool: false
            )
        case .family:
            return CaseReadinessCategory(
                displayName: String(localized: "Family"),
                analyticsValue: "family",
                isSelected: true,
                isSchool: false
            )
        case .immigration:
            return CaseReadinessCategory(
                displayName: String(localized: "Immigration"),
                analyticsValue: "immigration",
                isSelected: true,
                isSchool: false
            )
        case .other:
            return CaseReadinessCategory(
                displayName: String(localized: "Something else"),
                analyticsValue: "other",
                isSelected: true,
                isSchool: false
            )
        case .general:
            return CaseReadinessCategory(
                displayName: String(localized: "Other"),
                analyticsValue: "other",
                isSelected: onboardingCategory != nil,
                isSchool: false
            )
        }
    }

    private var readinessOnboardingCategory: String? {
        userNotes
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let trimmedLine = line.readinessTrimmedText

                for prefix in ["Selected category:", "Selected onboarding category:"] {
                    guard trimmedLine.localizedCaseInsensitiveContains(prefix) else {
                        continue
                    }

                    let value = trimmedLine
                        .replacingOccurrences(of: prefix, with: "", options: [.caseInsensitive])
                        .readinessTrimmedText
                    return value.isEmpty ? nil : value
                }

                return nil
            }
            .first
    }
}

private extension Array where Element == EvidenceItem {
    var importantReadinessItemsHaveLabels: Bool {
        guard !isEmpty else { return false }

        let importantItems = filter(\.userMarkedImportant)
        let labelingCandidates = importantItems.isEmpty ? self : importantItems

        return labelingCandidates.allSatisfy { evidenceItem in
            !evidenceItem.userTitle.readinessTrimmedText.isEmpty &&
                evidenceItem.category != .uncategorized
        }
    }
}

private extension EvidenceItem {
    var hasReadinessTextOrManualNote: Bool {
        !userNotes.readinessTrimmedText.isEmpty ||
            !userCleanedNote.readinessTrimmedText.isEmpty ||
            !userWhyThisMatters.readinessTrimmedText.isEmpty ||
            !originalOCRText.readinessTrimmedText.isEmpty
    }

    var isStrongReadinessTimelineItem: Bool {
        let detailText = [
            userNotes,
            userCleanedNote,
            userWhyThisMatters,
            originalOCRText
        ]
        .joined(separator: " ")
        .readinessTrimmedText

        return eventDate != nil &&
            (!userTitle.readinessTrimmedText.isEmpty || category != .uncategorized) &&
            (detailText.count >= 120 || userMarkedImportant)
    }
}

private extension String {
    var readinessTrimmedText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var readinessNormalizedCategory: CaseReadinessCategory? {
        let normalized = lowercased()

        if normalized.contains("school") || normalized.contains("college") || normalized.contains("university") {
            return CaseReadinessCategory(
                displayName: String(localized: "School"),
                analyticsValue: "school",
                isSelected: true,
                isSchool: true
            )
        }

        if normalized.contains("rent") || normalized.contains("lease") || normalized.contains("apartment") {
            return CaseReadinessCategory(
                displayName: String(localized: "Housing lease"),
                analyticsValue: "apartment",
                isSelected: true,
                isSchool: false
            )
        }

        if normalized.contains("refund") || normalized.contains("warranty") {
            return CaseReadinessCategory(
                displayName: String(localized: "Refund"),
                analyticsValue: "refund",
                isSelected: true,
                isSchool: false
            )
        }

        if normalized.contains("work") || normalized.contains("freelance") || normalized.contains("employment") {
            return CaseReadinessCategory(
                displayName: String(localized: "Work"),
                analyticsValue: "work",
                isSelected: true,
                isSchool: false
            )
        }

        if normalized.contains("something else") {
            return CaseReadinessCategory(
                displayName: String(localized: "Something else"),
                analyticsValue: "other",
                isSelected: true,
                isSchool: false
            )
        }

        return nil
    }
}
