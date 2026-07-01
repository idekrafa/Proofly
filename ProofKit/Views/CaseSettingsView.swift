import SwiftData
import SwiftUI

struct CaseSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var caseFile: CaseFile
    var onRequestExportPDF: () -> Void = {}
    var onRequestDeleteCase: () -> Void = {}

    @State private var activeSheet: CaseManageSheet?
    @State private var notice: CaseManageNotice?
    @State private var isDeleteGeneratedFilesConfirmationPresented = false
    @State private var isPreparingCaseDataExport = false

    private var displayCaseName: String {
        let trimmed = caseFile.userTitle.manageTrimmedText
        return trimmed.isEmpty ? String(localized: "Untitled case") : trimmed
    }

    private var displayCaseNotes: String {
        let trimmed = caseFile.userSummary.manageTrimmedText
        return trimmed.isEmpty ? String(localized: "Add optional context") : trimmed
    }

    private var generatedLocalCaseFileCount: Int {
        let fileManager = FileManager.default
        return Set(
            caseFile.sortedExportPackets.compactMap { packet in
                packet.localPDFFilePath?.manageTrimmedText
            }
            .filter { path in
                !path.isEmpty && fileManager.fileExists(atPath: path)
            }
        ).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ProofKitVisual.sectionSpacing) {
            pageHeader
            caseDetailsSection
            exportAndDataSection
            dangerZoneSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editName:
                CaseNameEditSheet(initialName: caseFile.userTitle) { newName in
                    saveCaseName(newName)
                }
                .presentationDetents([.medium])
            case .editCategory:
                CaseTypeEditSheet(selectedOption: CaseManageCategoryOption.option(for: caseFile.caseType)) { newCaseType in
                    saveCaseType(newCaseType)
                }
                .presentationDetents([.medium, .large])
            case .editNotes:
                CaseNotesEditSheet(initialNotes: caseFile.userSummary) { newNotes in
                    saveCaseNotes(newNotes)
                }
                .presentationDetents([.medium, .large])
            case .caseDataExport(let exportFile):
                CaseDataExportReadySheet(exportFile: exportFile)
                    .presentationDetents([.medium])
            }
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            "Delete local case files?",
            isPresented: $isDeleteGeneratedFilesConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete generated files", role: .destructive) {
                deleteGeneratedLocalCaseFiles()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes generated PDF packet files for this case from this device. It does not delete original imported proof files in Vault.")
        }
        .proofKitAppear()
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ProofKitVisual.accentSecondary)
                    .frame(width: 34, height: 34)
                    .background {
                        Circle()
                            .fill(ProofKitVisual.accentSecondary.opacity(0.14))
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage case")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("Update case details and local case data.")
                        .font(.subheadline)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .caseManageCard()
    }

    private var caseDetailsSection: some View {
        CaseManageSection(title: String(localized: "Case details")) {
            VStack(spacing: 0) {
                CaseManageActionRow(
                    icon: "textformat",
                    iconColor: ProofKitVisual.accentSecondary,
                    title: String(localized: "Case name"),
                    value: displayCaseName
                ) {
                    activeSheet = .editName
                }

                CaseManageDivider()

                CaseManageActionRow(
                    icon: "folder.badge.gearshape",
                    iconColor: ProofKitVisual.accent,
                    title: String(localized: "Category/type"),
                    value: caseFile.caseType.manageCaseTypeDisplayName
                ) {
                    activeSheet = .editCategory
                }

                CaseManageDivider()

                CaseManageActionRow(
                    icon: "note.text",
                    iconColor: Color.yellow,
                    title: String(localized: "Description/context"),
                    value: displayCaseNotes,
                    isPlaceholderValue: caseFile.userSummary.manageTrimmedText.isEmpty
                ) {
                    activeSheet = .editNotes
                }

                CaseManageDivider()

                CaseManageReadOnlyRow(
                    icon: "calendar",
                    iconColor: ProofKitVisual.subduedText,
                    title: String(localized: "Created date"),
                    value: ProofKitDateFormatting.shortDateTime(caseFile.createdAt)
                )

                CaseManageDivider()

                CaseManageReadOnlyRow(
                    icon: "clock.arrow.circlepath",
                    iconColor: ProofKitVisual.subduedText,
                    title: String(localized: "Last updated date"),
                    value: ProofKitDateFormatting.shortDateTime(caseFile.updatedAt)
                )
            }
        }
    }

    private var exportAndDataSection: some View {
        CaseManageSection(
            title: String(localized: "Export & data"),
            footer: String(localized: "Your proof stays on this device unless you choose to export or share it. Original imported proof files stay in Vault; this screen only manages this case’s links and generated files.")
        ) {
            VStack(spacing: 0) {
                CaseManageActionRow(
                    icon: "doc.richtext",
                    iconColor: ProofKitVisual.accentSecondary,
                    title: String(localized: "Export PDF packet"),
                    value: String(localized: "Open the packet builder for this case")
                ) {
                    onRequestExportPDF()
                }

                CaseManageDivider()

                CaseManageActionRow(
                    icon: "square.and.arrow.up",
                    iconColor: ProofKitVisual.accent,
                    title: isPreparingCaseDataExport ? String(localized: "Preparing case data…") : String(localized: "Export case data"),
                    value: String(localized: "Share a JSON copy of this case only")
                ) {
                    prepareCaseDataExport()
                }
                .disabled(isPreparingCaseDataExport)

                CaseManageDivider()

                CaseManageActionRow(
                    icon: "externaldrive.badge.xmark",
                    iconColor: Color.orange,
                    title: String(localized: "Delete local case files"),
                    value: generatedLocalCaseFileCount == 1 ? String(localized: "Delete 1 generated PDF file") : String(localized: "Delete generated PDF files for this case")
                ) {
                    requestGeneratedFileDeletion()
                }
            }
        }
    }

    private var dangerZoneSection: some View {
        CaseManageSection(title: String(localized: "Danger zone")) {
            VStack(spacing: 0) {
                CaseManageActionRow(
                    icon: "trash",
                    iconColor: Color.red,
                    title: String(localized: "Delete case"),
                    value: String(localized: "Remove this case timeline and local case data"),
                    isDestructive: true
                ) {
                    onRequestDeleteCase()
                }
            }
        }
    }

    @discardableResult
    private func saveCaseName(_ newName: String) -> Bool {
        let trimmedName = newName.manageTrimmedText
        guard !trimmedName.isEmpty else { return false }

        caseFile.userTitle = trimmedName
        return saveCaseChanges(failureTitle: String(localized: "Case name not saved"))
    }

    @discardableResult
    private func saveCaseType(_ newCaseType: CaseType) -> Bool {
        let newOption = CaseManageCategoryOption.option(for: newCaseType)
        caseFile.caseType = newCaseType
        caseFile.userNotes = caseFile.userNotes.updatingManageSelectedCategoryLine(to: newOption.title)
        return saveCaseChanges(failureTitle: String(localized: "Case type not saved"))
    }

    @discardableResult
    private func saveCaseNotes(_ newNotes: String) -> Bool {
        caseFile.userSummary = newNotes.manageTrimmedText
        return saveCaseChanges(failureTitle: String(localized: "Case notes not saved"))
    }

    @discardableResult
    private func saveCaseChanges(failureTitle: String) -> Bool {
        caseFile.updatedAt = .now

        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            notice = CaseManageNotice(
                title: failureTitle,
                message: String(localized: "Proofly could not save this change. Please try again.")
            )
            return false
        }
    }

    private func prepareCaseDataExport() {
        guard !isPreparingCaseDataExport else { return }
        isPreparingCaseDataExport = true

        do {
            let exportFile = try Self.writeCaseDataExport(for: caseFile)
            activeSheet = .caseDataExport(exportFile)
        } catch {
            notice = CaseManageNotice(
                title: String(localized: "Couldn’t export case data"),
                message: String(localized: "Proofly could not prepare this case export. Please try again.")
            )
        }

        isPreparingCaseDataExport = false
    }

    private func requestGeneratedFileDeletion() {
        guard generatedLocalCaseFileCount > 0 else {
            notice = CaseManageNotice(
                title: String(localized: "No generated files to delete"),
                message: String(localized: "This case does not have any generated PDF packet files stored on this device. Original proof files were not touched.")
            )
            return
        }

        isDeleteGeneratedFilesConfirmationPresented = true
    }

    private func deleteGeneratedLocalCaseFiles() {
        let fileManager = FileManager.default
        let paths = Set(
            caseFile.sortedExportPackets.compactMap { packet in
                packet.localPDFFilePath?.manageTrimmedText
            }
            .filter { !$0.isEmpty }
        )

        guard !paths.isEmpty else {
            notice = CaseManageNotice(
                title: String(localized: "No generated files to delete"),
                message: String(localized: "This case does not have any generated PDF packet files stored on this device. Original proof files were not touched.")
            )
            return
        }

        do {
            var deletedCount = 0
            for path in paths where fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(at: URL(filePath: path))
                deletedCount += 1
            }

            for packet in caseFile.sortedExportPackets where packet.localPDFFilePath?.manageTrimmedText.isEmpty == false {
                packet.localPDFFilePath = nil
                packet.fileSizeBytes = nil
                packet.pageCount = nil
            }

            caseFile.updatedAt = .now
            try modelContext.save()

            notice = CaseManageNotice(
                title: String(localized: "Local case files deleted"),
                message: deletedCount == 1
                ? String(localized: "Deleted 1 generated PDF packet file for this case. Original imported proof files remain in Vault.")
                : String(localized: "Deleted \(deletedCount) generated PDF packet files for this case. Original imported proof files remain in Vault.")
            )
        } catch {
            modelContext.rollback()
            notice = CaseManageNotice(
                title: String(localized: "Files not deleted"),
                message: String(localized: "Proofly could not delete the generated case files. Original imported proof files were not touched.")
            )
        }
    }

    @MainActor
    private static func writeCaseDataExport(for caseFile: CaseFile) throws -> CaseDataExportFile {
        let snapshot = CaseDataExportSnapshot(
            exportedAt: .now,
            caseFile: CaseDataExportCase(caseFile: caseFile)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(snapshot)
        let exportDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ProoflyCaseExports")
            .appending(path: caseFile.id.uuidString)
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )

        let timestamp = Self.exportFilenameDateFormatter.string(from: .now)
        let safeTitle = caseFile.userTitle.manageFilenameSlug(fallback: "case")
        let url = exportDirectory.appending(path: "proofly-\(safeTitle)-\(timestamp).json")
        try data.write(to: url, options: [.atomic])

        return CaseDataExportFile(url: url, caseTitle: caseFile.userTitle.manageTrimmedText)
    }

    private static let exportFilenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private enum CaseManageSheet: Identifiable {
    case editName
    case editCategory
    case editNotes
    case caseDataExport(CaseDataExportFile)

    var id: String {
        switch self {
        case .editName:
            "editName"
        case .editCategory:
            "editCategory"
        case .editNotes:
            "editNotes"
        case .caseDataExport(let exportFile):
            "caseDataExport-\(exportFile.id.uuidString)"
        }
    }
}

private struct CaseManageNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum CaseManageCategoryOption: String, CaseIterable, Identifiable {
    case apartmentDrama
    case refundFight
    case schoolCollegeIssue
    case workFreelanceProblem
    case somethingElse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apartmentDrama:
            String(localized: "Housing lease")
        case .refundFight:
            String(localized: "Refund fight")
        case .schoolCollegeIssue:
            String(localized: "School or college issue")
        case .workFreelanceProblem:
            String(localized: "Work or freelance problem")
        case .somethingElse:
            String(localized: "Something else")
        }
    }

    var caseType: CaseType {
        switch self {
        case .apartmentDrama:
            .apartmentIssue
        case .refundFight:
            .refundWarrantyIssue
        case .schoolCollegeIssue:
            .schoolCollegeIssue
        case .workFreelanceProblem:
            .workFreelanceIssue
        case .somethingElse:
            .other
        }
    }

    var iconName: String {
        switch self {
        case .apartmentDrama:
            "house.fill"
        case .refundFight:
            "cart.fill"
        case .schoolCollegeIssue:
            "graduationcap.fill"
        case .workFreelanceProblem:
            "briefcase.fill"
        case .somethingElse:
            "folder.fill"
        }
    }

    static func option(for caseType: CaseType) -> CaseManageCategoryOption {
        switch caseType {
        case .apartmentIssue, .tenantLandlord:
            .apartmentDrama
        case .refundWarrantyIssue, .consumer:
            .refundFight
        case .schoolCollegeIssue:
            .schoolCollegeIssue
        case .unpaidFreelanceWork, .workplaceIssue, .workFreelanceIssue, .employment:
            .workFreelanceProblem
        case .general, .insuranceIssue, .smallClaims, .insurance, .family, .immigration, .other:
            .somethingElse
        }
    }
}

private struct CaseManageSection<Content: View>: View {
    let title: String
    let footer: String?
    private let content: Content

    init(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 2)

            content
                .caseManageCard()

            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CaseManageActionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    var isPlaceholderValue = false
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                CaseManageIcon(systemName: icon, color: iconColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isDestructive ? Color.red : .primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(value)
                        .font(.footnote)
                        .foregroundStyle(isPlaceholderValue ? ProofKitVisual.subduedText : ProofKitVisual.helperText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isDestructive ? Color.red.opacity(0.72) : ProofKitVisual.subduedText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProofKitCardButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

private struct CaseManageReadOnlyRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CaseManageIcon(systemName: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(value)
                    .font(.footnote)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

private struct CaseManageIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background {
                Circle()
                    .fill(color.opacity(0.14))
            }
            .accessibilityHidden(true)
    }
}

private struct CaseManageDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 62)
            .background(ProofKitVisual.divider)
    }
}

private struct CaseNameEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameIsFocused: Bool

    let onSave: (String) -> Bool
    @State private var name: String

    init(initialName: String, onSave: @escaping (String) -> Bool) {
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    private var trimmedName: String {
        name.manageTrimmedText
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Case name")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ProofKitVisual.helperText)

                TextField("Case name", text: $name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($nameIsFocused)
                    .onSubmit(save)
                    .padding(14)
                    .proofKitFieldBackground(cornerRadius: 14)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
                    }

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProofKitVisual.screenBackground.ignoresSafeArea())
            .navigationTitle("Edit case name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear {
                nameIsFocused = true
            }
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if onSave(trimmedName) {
            dismiss()
        }
    }
}

private struct CaseTypeEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selectedOption: CaseManageCategoryOption
    let onSelect: (CaseType) -> Bool

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(CaseManageCategoryOption.allCases) { option in
                        Button {
                            if onSelect(option.caseType) {
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                CaseManageIcon(
                                    systemName: option.iconName,
                                    color: option == selectedOption ? ProofKitVisual.accentSecondary : ProofKitVisual.helperText
                                )

                                Text(option.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if option == selectedOption {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(ProofKitVisual.accentSecondary)
                                        .accessibilityLabel("Selected")
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: ProofKitVisual.panelCornerRadius, style: .continuous)
                                    .fill(option == selectedOption ? ProofKitVisual.accentSecondary.opacity(0.12) : ProofKitVisual.cardBackground)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: ProofKitVisual.panelCornerRadius, style: .continuous)
                                    .stroke(option == selectedOption ? ProofKitVisual.accentSecondary.opacity(0.38) : ProofKitVisual.cardBorder, lineWidth: 1)
                            }
                        }
                        .buttonStyle(ProofKitCardButtonStyle())
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .background(ProofKitVisual.screenBackground.ignoresSafeArea())
            .navigationTitle("Change case type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct CaseNotesEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var notesAreFocused: Bool

    let onSave: (String) -> Bool
    @State private var notes: String

    init(initialNotes: String, onSave: @escaping (String) -> Bool) {
        self.onSave = onSave
        _notes = State(initialValue: initialNotes)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Optional description/context")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ProofKitVisual.helperText)

                ZStack(alignment: .topLeading) {
                    if notes.manageTrimmedText.isEmpty {
                        Text("Add context that helps you understand this case later.")
                            .font(.body)
                            .foregroundStyle(ProofKitVisual.subduedText)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $notes)
                        .focused($notesAreFocused)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 170)
                }
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ProofKitVisual.fieldBackground)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProofKitVisual.screenBackground.ignoresSafeArea())
            .navigationTitle("Edit case notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear {
                notesAreFocused = true
            }
        }
    }

    private func save() {
        if onSave(notes) {
            dismiss()
        }
    }
}

private struct CaseDataExportReadySheet: View {
    @Environment(\.dismiss) private var dismiss
    let exportFile: CaseDataExportFile

    private var caseTitle: String {
        exportFile.caseTitle.manageTrimmedText.isEmpty ? String(localized: "this case") : "“\(exportFile.caseTitle.manageTrimmedText)”"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(ProofKitVisual.accentSecondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Case data ready")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("Share a JSON copy of \(caseTitle). This does not move, upload, or delete your local proof files.")
                        .font(.subheadline)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ShareLink(item: exportFile.url) {
                    Label("Share case data", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(ProofKitVisual.accent)

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProofKitVisual.screenBackground.ignoresSafeArea())
            .navigationTitle("Export case data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct CaseDataExportFile: Identifiable {
    let id = UUID()
    let url: URL
    let caseTitle: String
}

private struct CaseDataExportSnapshot: Encodable {
    let exportedAt: Date
    let caseFile: CaseDataExportCase
}

private struct CaseDataExportCase: Encodable {
    let id: UUID
    let caseType: String
    let status: String
    let title: String
    let summary: String
    let notes: String
    let createdAt: Date
    let updatedAt: Date
    let archivedAt: Date?
    let evidenceCount: Int
    let exportCount: Int
    let evidenceItems: [CaseDataExportEvidence]
    let exports: [CaseDataExportPDF]

    @MainActor
    init(caseFile: CaseFile) {
        id = caseFile.id
        caseType = caseFile.caseType.manageCaseTypeDisplayName
        status = caseFile.status.displayName
        title = caseFile.userTitle
        summary = caseFile.userSummary
        notes = caseFile.userNotes
        createdAt = caseFile.createdAt
        updatedAt = caseFile.updatedAt
        archivedAt = caseFile.archivedAt
        evidenceCount = caseFile.evidenceItems.count
        exportCount = caseFile.exportPackets.count
        evidenceItems = caseFile.sortedEvidenceItems.map(CaseDataExportEvidence.init(evidenceItem:))
        exports = caseFile.sortedExportPackets.map(CaseDataExportPDF.init(exportPacket:))
    }
}

private struct CaseDataExportEvidence: Encodable {
    let id: UUID
    let title: String
    let category: String
    let userNotes: String
    let userCleanedNote: String
    let whyThisMatters: String
    let userProvidedEventDate: Date?
    let detectedEventDate: Date?
    let eventDate: Date?
    let eventDateSource: String
    let isImportant: Bool
    let isReviewed: Bool
    let reviewedAt: Date?
    let originalOCRText: String
    let originalOCRConfidence: Double?
    let originalOCRCompletedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let attachments: [CaseDataExportAttachment]

    @MainActor
    init(evidenceItem: EvidenceItem) {
        id = evidenceItem.id
        title = evidenceItem.userTitle
        category = evidenceItem.category.displayName
        userNotes = evidenceItem.userNotes
        userCleanedNote = evidenceItem.userCleanedNote
        whyThisMatters = evidenceItem.userWhyThisMatters
        userProvidedEventDate = evidenceItem.userProvidedEventDate
        detectedEventDate = evidenceItem.detectedEventDate
        eventDate = evidenceItem.eventDate
        eventDateSource = evidenceItem.eventDateSource.displayName
        isImportant = evidenceItem.userMarkedImportant
        isReviewed = evidenceItem.isReviewed
        reviewedAt = evidenceItem.reviewedAt
        originalOCRText = evidenceItem.originalOCRText
        originalOCRConfidence = evidenceItem.originalOCRConfidence
        originalOCRCompletedAt = evidenceItem.originalOCRCompletedAt
        createdAt = evidenceItem.createdAt
        updatedAt = evidenceItem.updatedAt
        attachments = evidenceItem.sortedAttachments.map(CaseDataExportAttachment.init(attachment:))
    }
}

private struct CaseDataExportAttachment: Encodable {
    let id: UUID
    let type: String
    let originalFilename: String
    let uniformTypeIdentifier: String?
    let fileSizeBytes: Int64?
    let contentHash: String?
    let fileCreatedAt: Date?
    let fileModifiedAt: Date?
    let originalOCRText: String
    let originalOCRConfidence: Double?
    let originalOCRCompletedAt: Date?
    let importedMetadataJSON: String
    let createdAt: Date
    let updatedAt: Date

    @MainActor
    init(attachment: Attachment) {
        id = attachment.id
        type = attachment.attachmentType.displayName
        originalFilename = attachment.originalFilename
        uniformTypeIdentifier = attachment.uniformTypeIdentifier
        fileSizeBytes = attachment.fileSizeBytes
        contentHash = attachment.contentHash
        fileCreatedAt = attachment.fileCreatedAt
        fileModifiedAt = attachment.fileModifiedAt
        originalOCRText = attachment.originalOCRText
        originalOCRConfidence = attachment.originalOCRConfidence
        originalOCRCompletedAt = attachment.originalOCRCompletedAt
        importedMetadataJSON = attachment.importedMetadataJSON
        createdAt = attachment.createdAt
        updatedAt = attachment.updatedAt
    }
}

private struct CaseDataExportPDF: Encodable {
    let id: UUID
    let title: String
    let notes: String
    let fileSizeBytes: Int64?
    let pageCount: Int?
    let hasLocalPDFFile: Bool
    let includedEvidenceItemIDsJSON: String
    let exportOptionsJSON: String
    let createdAt: Date
    let exportedAt: Date?

    @MainActor
    init(exportPacket: ExportPacket) {
        id = exportPacket.id
        title = exportPacket.userPacketTitle
        notes = exportPacket.userPacketNotes
        fileSizeBytes = exportPacket.fileSizeBytes
        pageCount = exportPacket.pageCount
        hasLocalPDFFile = exportPacket.localPDFFilePath?.manageTrimmedText.isEmpty == false
        includedEvidenceItemIDsJSON = exportPacket.includedEvidenceItemIDsJSON
        exportOptionsJSON = exportPacket.exportOptionsJSON
        createdAt = exportPacket.createdAt
        exportedAt = exportPacket.exportedAt
    }
}

private extension CaseType {
    var manageCaseTypeDisplayName: String {
        CaseManageCategoryOption.option(for: self).title
    }
}

private extension String {
    var manageTrimmedText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func manageFilenameSlug(fallback: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let slug = lowercased()
            .components(separatedBy: allowedCharacters.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        return slug.isEmpty ? fallback : String(slug.prefix(48))
    }

    func updatingManageSelectedCategoryLine(to title: String) -> String {
        let prefixes = ["Selected category:", "Selected onboarding category:"]
        var lines = components(separatedBy: .newlines)

        for index in lines.indices {
            let trimmedLine = lines[index].manageTrimmedText
            guard prefixes.contains(where: { prefix in
                trimmedLine.localizedCaseInsensitiveContains(prefix)
            }) else {
                continue
            }

            lines[index] = "Selected category: \(title)"
            return lines.joined(separator: "\n")
        }

        return self
    }
}

private extension View {
    func caseManageCard() -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: ProofKitVisual.panelCornerRadius, style: .continuous)
                    .fill(ProofKitVisual.cardBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: ProofKitVisual.panelCornerRadius, style: .continuous)
                    .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
            }
    }
}

#Preview {
    CaseSettingsView(caseFile: CaseFile(caseType: .workplaceIssue, userTitle: "Sample Case"))
        .padding()
        .background(ProofKitVisual.screenBackground)
}
