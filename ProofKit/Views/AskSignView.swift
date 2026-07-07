import CryptoKit
import SwiftUI
import UIKit

/// Ask Sign: creates a server-side signature request for a generated PDF and
/// returns a shareable web link the counterparty can sign from any channel
/// (WhatsApp, Instagram, email, …). The counterparty signs first; the owner
/// then adds their own signature and exports the final PDF.
struct AskSignView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.proofKitServices) private var services

    let caseFile: CaseFile
    let exportID: UUID?
    let pdfURL: URL
    let appVersion: String
    let onCreated: () -> Void

    @State private var requesterName = ""
    @State private var message = ""
    @State private var page = PDFSignaturePage.lastPage
    @State private var placement = PDFSignaturePlacement.lowerLeft
    @State private var expiresInDays = 7
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var createdRequest: SignatureRequestCreateResponse?
    @State private var didCopyLink = false

    private static let expiryOptions = [3, 7, 14, 30]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if let createdRequest {
                        shareSection(createdRequest)
                    } else {
                        formSection
                    }
                }
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Ask Sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(createdRequest == nil ? "Cancel" : "Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Request a signature")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Proofly creates a private link to this PDF. The other party opens it in any browser, reviews the document, and signs electronically. You add your own signature after they sign.")
                    .font(.subheadline)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                labeledField("Your name (shown to the signer)") {
                    TextField("Optional", text: $requesterName)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.words)
                }

                labeledField("Message to the signer") {
                    TextField("Optional note shown on the signing page", text: $message, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...4)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Their signature placement")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Picker("Page", selection: $page) {
                    ForEach(PDFSignaturePage.allCases) { page in
                        Text(page.displayName).tag(page)
                    }
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                    ForEach(PDFSignaturePlacement.presets) { option in
                        placementOption(option)
                    }
                }

                Text("Tip: keep one corner free for your own signature.")
                    .font(.caption)
                    .foregroundStyle(ProofKitVisual.subduedText)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Link valid for")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Picker("Link valid for", selection: $expiresInDays) {
                    ForEach(Self.expiryOptions, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                .pickerStyle(.segmented)
            }

            Button {
                Task { await createRequest() }
            } label: {
                HStack(spacing: 9) {
                    if isCreating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "link.badge.plus")
                    }

                    Text(isCreating ? "Creating secure link…" : "Create signing link")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(ProofKitVisual.accentSecondary)
            .disabled(isCreating)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("The PDF is uploaded privately so the signer can view it. The link stops working after signing, cancelling, or expiry.")
                .font(.caption)
                .foregroundStyle(ProofKitVisual.subduedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func placementOption(_ option: PDFSignaturePlacement) -> some View {
        let isSelected = placement == option
        let selectedColor = ProofKitVisual.accentSecondary
        return Button {
            withAnimation(ProofKitMotion.standard) {
                placement = option
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isSelected ? selectedColor : ProofKitVisual.helperText)

                Text(option.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? selectedColor.opacity(0.12) : ProofKitVisual.fieldBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? selectedColor.opacity(0.44) : ProofKitVisual.cardBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func shareSection(_ request: SignatureRequestCreateResponse) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Signing link ready", systemImage: "checkmark.seal.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ProofKitVisual.accentSecondary)

                Text("Share this link through WhatsApp, Instagram, email, or any other channel. Proofly shows their signature here once they sign.")
                    .font(.subheadline)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ProofKitQRCodeView(content: request.shareURL.absoluteString)

                Text("If they're next to you, they can scan this code with their phone camera and sign right away.")
                    .font(.caption)
                    .foregroundStyle(ProofKitVisual.subduedText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                Text(request.shareURL.absoluteString)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(ProofKitVisual.fieldBackground)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
                    }

                HStack(spacing: 10) {
                    ShareLink(item: request.shareURL) {
                        Label("Share link", systemImage: "square.and.arrow.up")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(ProofKitVisual.accentSecondary)

                    Button {
                        UIPasteboard.general.url = request.shareURL
                        withAnimation(ProofKitMotion.standard) {
                            didCopyLink = true
                        }
                    } label: {
                        Label(didCopyLink ? "Copied" : "Copy", systemImage: didCopyLink ? "checkmark" : "doc.on.doc")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            Label("Expires \(Self.expiryDateFormatter.string(from: request.expiresAt))", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(ProofKitVisual.subduedText)
        }
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ProofKitVisual.helperText)

            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(ProofKitVisual.fieldBackground)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
                }
        }
    }

    @MainActor
    private func createRequest() async {
        guard !isCreating else { return }
        withAnimation(ProofKitMotion.standard) {
            isCreating = true
            errorMessage = nil
        }

        do {
            let pdfData = try Data(contentsOf: pdfURL)
            let pdfSHA256 = SHA256.hash(data: pdfData)
                .map { String(format: "%02x", $0) }
                .joined()

            let cleanedRequesterName = requesterName.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let documentTitle = caseFile.userTitle.trimmingCharacters(in: .whitespacesAndNewlines)

            let response = try await services.signatureRequests.createSignatureRequest(
                SignatureRequestCreateRequest(
                    caseID: caseFile.id,
                    exportID: exportID,
                    pdfBase64: pdfData.base64EncodedString(),
                    pdfSHA256: pdfSHA256,
                    documentTitle: documentTitle.isEmpty ? "Proofly packet" : documentTitle,
                    requesterName: cleanedRequesterName.isEmpty ? nil : cleanedRequesterName,
                    message: cleanedMessage.isEmpty ? nil : cleanedMessage,
                    signaturePage: page.rawValue,
                    signaturePlacement: placement.rawValue,
                    appVersion: appVersion,
                    expiresInDays: expiresInDays
                )
            )

            withAnimation(ProofKitMotion.standard) {
                createdRequest = response
                isCreating = false
            }
            onCreated()
        } catch {
            withAnimation(ProofKitMotion.standard) {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }

    private static let expiryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
