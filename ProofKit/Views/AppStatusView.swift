import SwiftData
import SwiftUI
import UIKit

struct AppStatusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.proofKitServices) private var services

    @ObservedObject var healthMonitor: ServiceHealthMonitor
    @ObservedObject var queue: AIRequestQueueService
    @Query(sort: \AIRequestQueueItem.createdAt, order: .forward) private var queuedAIRequests: [AIRequestQueueItem]

    @State private var secondsUntilRecheck = 10
    @State private var isRechecking = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    statusSection
                    detailsGrid
                    queuedRequestsSection
                    worksSection
                    limitedSection
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 36)
            }
            .background(StatusPalette.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            queue.refreshSummary(in: modelContext)
            await recheck()
            await countdownLoop()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                Text("App Status")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                Text("Local-first reliability")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StatusPalette.secondaryText)
            }

            Spacer(minLength: 12)

            if healthMonitor.snapshot.state != .healthy {
                Text("Rechecking in \(secondsUntilRecheck)s")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(StatusPalette.secondaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background {
                        Capsule().fill(StatusPalette.card)
                    }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(StatusPalette.secondaryText)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle().fill(StatusPalette.card)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close App Status")
        }
    }

    private var statusIcon: some View {
        Image(systemName: iconName(for: healthMonitor.snapshot.state))
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(statusColor(for: healthMonitor.snapshot.state))
            .frame(width: 38, height: 38)
            .background {
                Circle().fill(statusColor(for: healthMonitor.snapshot.state).opacity(0.14))
            }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("What's happening")

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: iconName(for: healthMonitor.snapshot.state))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(statusColor(for: healthMonitor.snapshot.state))
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(primaryStatusTitle)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)

                        Text(healthMonitor.snapshot.message)
                            .font(.subheadline)
                            .foregroundStyle(StatusPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await recheckAndProcess() }
                    } label: {
                        HStack(spacing: 7) {
                            if isRechecking {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption.weight(.bold))
                            }
                            Text(isRechecking ? "Checking..." : "Check now")
                                .font(.footnote.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background {
                            Capsule().fill(StatusPalette.action)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isRechecking)

                    if queue.summary.hasPendingWork {
                        Text(queueStatusText)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(StatusPalette.secondaryText)
                    }
                }
            }
            .statusCard()
        }
    }

    private var detailsGrid: some View {
        VStack(spacing: 10) {
            StatusDetailCard(
                icon: "lock.shield.fill",
                tint: StatusPalette.safe,
                title: "Your proof is safe",
                copy: "Your cases, proof files, OCR, and timeline stay stored locally on this device."
            )

            StatusDetailCard(
                icon: "arrow.triangle.2.circlepath",
                tint: StatusPalette.retry,
                title: "Automatic retry",
                copy: "Proofly will retry queued sync and AI requests automatically when services return."
            )

            StatusDetailCard(
                icon: "tray.full.fill",
                tint: StatusPalette.pending,
                title: "Pending changes",
                copy: "\(queue.summary.pendingCount) item\(queue.summary.pendingCount == 1 ? "" : "s") waiting to sync."
            )
        }
    }

    private var queuedRequestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Pending AI requests")

            if activeQueueItems.isEmpty {
                Text("No AI requests are waiting. AI output remains separate from your original evidence and notes.")
                    .font(.subheadline)
                    .foregroundStyle(StatusPalette.secondaryText)
                    .statusCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(activeQueueItems) { item in
                        QueuedAIRequestRow(item: item) {
                            queue.cancel(item, in: modelContext)
                        }

                        if item.id != activeQueueItems.last?.id {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .statusCard(padding: 0)

                Text("AI will run when connection returns and credits are available.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(StatusPalette.secondaryText)
                    .padding(.horizontal, 2)
            }
        }
    }

    private var worksSection: some View {
        StatusChecklistSection(
            title: "What still works",
            icon: "checkmark.circle.fill",
            tint: StatusPalette.safe,
            items: [
                "Viewing cases",
                "Viewing proof/timeline",
                "Importing and local OCR when available offline",
                "Editing timeline/details",
                "Local exports when supported"
            ]
        )
    }

    private var limitedSection: some View {
        StatusChecklistSection(
            title: "Temporarily limited",
            icon: "clock.badge.exclamationmark.fill",
            tint: StatusPalette.warning,
            items: [
                "AI timeline summary",
                "Packet polish / Deep review",
                "Subscription/credit refresh",
                "Cross-device/server sync if available"
            ]
        )
    }

    private var activeQueueItems: [AIRequestQueueItem] {
        queuedAIRequests.filter { item in
            item.status == .queued ||
                item.status == .running ||
                item.status == .waitingForCredits ||
                item.status == .failed
        }
    }

    private var primaryStatusTitle: String {
        if queue.summary.waitingForCreditsCount > 0 {
            return "AI queue waiting for credits"
        }

        if queue.summary.runningCount > 0 {
            return "Syncing \(queue.summary.runningCount) AI request\(queue.summary.runningCount == 1 ? "" : "s")"
        }

        if queue.summary.queuedCount > 0, healthMonitor.snapshot.state == .healthy {
            return "Syncing \(queue.summary.queuedCount) AI request\(queue.summary.queuedCount == 1 ? "" : "s")"
        }

        return healthMonitor.snapshot.state.statusTitle
    }

    private var queueStatusText: String {
        if queue.summary.waitingForCreditsCount > 0 {
            return "\(queue.summary.waitingForCreditsCount) waiting for credits"
        }

        if queue.isProcessing {
            return "Processing one at a time"
        }

        return "\(queue.summary.pendingCount) queued"
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(StatusPalette.secondaryText)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 2)
    }

    private func recheck() async {
        guard !isRechecking else { return }
        isRechecking = true
        await services.serviceHealth.recheck()
        queue.refreshSummary(in: modelContext)
        isRechecking = false
        secondsUntilRecheck = 10
    }

    private func recheckAndProcess() async {
        await recheck()
        await queue.processPendingItems(in: modelContext)
    }

    private func countdownLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if secondsUntilRecheck > 0 {
                secondsUntilRecheck -= 1
            } else {
                await recheckAndProcess()
            }
        }
    }

    private func statusColor(for state: ServiceHealthState) -> Color {
        switch state {
        case .healthy:
            StatusPalette.safe
        case .offline:
            StatusPalette.offline
        case .supabaseDown, .degraded:
            StatusPalette.warning
        case .aiProviderDown:
            StatusPalette.aiDelayed
        case .checking:
            StatusPalette.pending
        }
    }

    private func iconName(for state: ServiceHealthState) -> String {
        switch state {
        case .healthy:
            "checkmark.seal.fill"
        case .offline:
            "wifi.slash"
        case .supabaseDown:
            "server.rack"
        case .aiProviderDown:
            "sparkles"
        case .degraded:
            "exclamationmark.triangle.fill"
        case .checking:
            "arrow.clockwise"
        }
    }
}

struct HomeStatusPillHost: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var healthMonitor: ServiceHealthMonitor
    @ObservedObject var queue: AIRequestQueueService
    let onTap: () -> Void

    var body: some View {
        Group {
            if let title {
                Button(action: onTap) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(tint)
                            .frame(width: 7, height: 7)

                        Text(title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background {
                        Capsule()
                            .fill(tint.opacity(0.12))
                    }
                    .overlay {
                        Capsule()
                            .stroke(tint.opacity(0.22), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open App Status")
                .task {
                    queue.refreshSummary(in: modelContext)
                }
            }
        }
    }

    private var title: String? {
        if queue.isProcessing || (healthMonitor.snapshot.state == .healthy && queue.summary.queuedCount > 0) {
            return "Syncing \(queue.summary.queuedCount + queue.summary.runningCount) AI request\(queue.summary.queuedCount + queue.summary.runningCount == 1 ? "" : "s")"
        }

        if queue.summary.waitingForCreditsCount > 0 {
            return "AI delayed"
        }

        return healthMonitor.snapshot.state.shortPillTitle
    }

    private var tint: Color {
        if queue.isProcessing {
            return StatusPalette.pending
        }

        if queue.summary.waitingForCreditsCount > 0 {
            return StatusPalette.aiDelayed
        }

        switch healthMonitor.snapshot.state {
        case .offline:
            return StatusPalette.offline
        case .supabaseDown, .degraded:
            return StatusPalette.warning
        case .aiProviderDown:
            return StatusPalette.aiDelayed
        case .healthy, .checking:
            return StatusPalette.pending
        }
    }
}

private struct StatusDetailCard: View {
    let icon: String
    let tint: Color
    let title: String
    let copy: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.12))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                Text(copy)
                    .font(.footnote)
                    .foregroundStyle(StatusPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .statusCard()
    }
}

private struct QueuedAIRequestRow: View {
    let item: AIRequestQueueItem
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background {
                    Circle().fill(tint.opacity(0.12))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(StatusPalette.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if item.status == .queued || item.status == .waitingForCredits || item.status == .failed {
                Button("Cancel", action: onCancel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(StatusPalette.secondaryText)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var icon: String {
        switch item.status {
        case .queued:
            "clock.fill"
        case .running:
            "arrow.triangle.2.circlepath"
        case .waitingForCredits:
            "creditcard.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .completed:
            "checkmark.circle.fill"
        case .cancelled:
            "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch item.status {
        case .queued:
            StatusPalette.pending
        case .running:
            StatusPalette.pending
        case .waitingForCredits:
            StatusPalette.aiDelayed
        case .failed:
            StatusPalette.warning
        case .completed:
            StatusPalette.safe
        case .cancelled:
            StatusPalette.secondaryText
        }
    }

    private var subtitle: String {
        if let lastErrorMessage = item.lastErrorMessage, !lastErrorMessage.isEmpty {
            return lastErrorMessage
        }

        let cost = item.creditCostQuote ?? item.actionKind.defaultCreditCost
        switch item.status {
        case .queued:
            return "Queued • \(cost) AI credit\(cost == 1 ? "" : "s")"
        case .running:
            return "Running now • credits checked server-side"
        case .waitingForCredits:
            return "Waiting for credits • \(cost) needed"
        case .failed:
            return "Needs attention before retrying"
        case .completed:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        }
    }
}

private struct StatusChecklistSection: View {
    let title: String
    let icon: String
    let tint: Color
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(StatusPalette.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 11) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)
                            .frame(width: 18)

                        Text(item)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)
                    }
                }
            }
            .statusCard()
        }
    }
}

private enum StatusPalette {
    static let background = dynamicColor(
        light: UIColor(red: 0.975, green: 0.969, blue: 0.952, alpha: 1),
        dark: UIColor(red: 0.047, green: 0.059, blue: 0.078, alpha: 1)
    )
    static let card = dynamicColor(
        light: UIColor(white: 1, alpha: 0.92),
        dark: UIColor(red: 0.082, green: 0.102, blue: 0.133, alpha: 1)
    )
    static let hairline = dynamicColor(
        light: UIColor(white: 0, alpha: 0.08),
        dark: UIColor(white: 1, alpha: 0.10)
    )
    static let secondaryText = dynamicColor(
        light: UIColor(red: 0.37, green: 0.35, blue: 0.31, alpha: 1),
        dark: UIColor(red: 0.69, green: 0.74, blue: 0.80, alpha: 1)
    )
    static let action = dynamicColor(
        light: UIColor(red: 0.08, green: 0.43, blue: 0.84, alpha: 1),
        dark: UIColor(red: 0.26, green: 0.65, blue: 1.00, alpha: 1)
    )
    static let safe = dynamicColor(
        light: UIColor(red: 0.12, green: 0.55, blue: 0.35, alpha: 1),
        dark: UIColor(red: 0.23, green: 0.78, blue: 0.54, alpha: 1)
    )
    static let retry = dynamicColor(
        light: UIColor(red: 0.08, green: 0.43, blue: 0.84, alpha: 1),
        dark: UIColor(red: 0.26, green: 0.65, blue: 1.00, alpha: 1)
    )
    static let pending = dynamicColor(
        light: UIColor(red: 0.12, green: 0.45, blue: 0.82, alpha: 1),
        dark: UIColor(red: 0.33, green: 0.68, blue: 1.00, alpha: 1)
    )
    static let warning = dynamicColor(
        light: UIColor(red: 0.74, green: 0.48, blue: 0.10, alpha: 1),
        dark: UIColor(red: 1.00, green: 0.70, blue: 0.28, alpha: 1)
    )
    static let offline = dynamicColor(
        light: UIColor(red: 0.86, green: 0.36, blue: 0.13, alpha: 1),
        dark: UIColor(red: 1.00, green: 0.52, blue: 0.30, alpha: 1)
    )
    static let aiDelayed = dynamicColor(
        light: UIColor(red: 0.50, green: 0.30, blue: 0.76, alpha: 1),
        dark: UIColor(red: 0.78, green: 0.58, blue: 1.00, alpha: 1)
    )

    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(
            UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
}

private extension View {
    func statusCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(StatusPalette.card)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(StatusPalette.hairline, lineWidth: 1)
            }
    }
}
