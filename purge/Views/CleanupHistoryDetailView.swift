import SwiftUI

struct CleanupHistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let entry: CleanupHistoryEntry

    private let restoreService = RestoreService()
    @State private var availability: [String: RestoreAvailability] = [:]
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    private var restorableItems: [CleanupHistoryDeletedItemDTO] {
        entry.deletedItems.filter { availability[$0.id] == .restorable }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summarySection
                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(AppStyle.Typography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    movedToTrashSection
                    if !entry.skippedItems.isEmpty {
                        skippedSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppDetailPageLayout.horizontalInset)
                .padding(.top, 16)
                .padding(.bottom, AppDetailPageLayout.verticalPadding)
            }
            .scrollContentBackground(.hidden)
        }
        .background(AppColors.surfaceBase)
        .frame(minWidth: 480, minHeight: 320, maxHeight: 560)
        .task { refreshAvailability() }
    }

    private func refreshAvailability() {
        var result: [String: RestoreAvailability] = [:]
        for item in entry.deletedItems {
            result[item.id] = restoreService.availability(of: item)
        }
        availability = result
    }

    private func putBack(_ items: [CleanupHistoryDeletedItemDTO]) {
        guard !items.isEmpty, !isRestoring else { return }
        isRestoring = true
        let service = restoreService
        Task {
            // File moves can be slow for big folders; keep them off the main thread.
            let report = await Task.detached { service.restore(items) }.value
            restoreMessage = report.summary
            isRestoring = false
            refreshAvailability()
        }
    }

    private var sheetHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(entry.trigger == .scheduled ? "Automatic clean" : "Manual clean")
                .font(AppStyle.Typography.headline)

            Spacer(minLength: 12)

            if isRestoring {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Putting items back")
            }

            Button("Put Back All") {
                putBack(restorableItems)
            }
            .disabled(restorableItems.isEmpty || isRestoring)
            .help("Move everything from this clean that is still in the Trash back where it was")

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, AppDetailPageLayout.horizontalInset)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var summarySection: some View {
        historySectionCard {
            CleanupHistorySummaryRow(entry: entry)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    private var movedToTrashSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Moved to Trash")

            historySectionCard {
                ForEach(Array(entry.deletedItems.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        InsetCardDivider()
                    }
                    deletedItemRow(item)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private var skippedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Skipped")

            historySectionCard {
                ForEach(Array(entry.skippedItems.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        InsetCardDivider()
                    }
                    skippedItemRow(item)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(AppStyle.Typography.metadata.weight(.semibold))
            .foregroundStyle(AppColors.textSecondary)
            .textCase(.uppercase)
    }

    private func deletedItemRow(_ item: CleanupHistoryDeletedItemDTO) -> some View {
        let fileURL = URL(fileURLWithPath: item.path).standardizedFileURL

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(fileURL.lastPathComponent)
                    .font(AppStyle.Typography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Text(displayDirectoryPath(for: fileURL.deletingLastPathComponent()))
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if item.sizeBytes > 0 {
                Text(formatBytes(item.sizeBytes))
                    .font(AppStyle.Typography.rowTitle)
                    .foregroundStyle(AppColors.textSecondary)
            }

            restoreControl(for: item)
        }
    }

    @ViewBuilder
    private func restoreControl(for item: CleanupHistoryDeletedItemDTO) -> some View {
        switch availability[item.id] {
        case .restorable:
            Button("Put Back") { putBack([item]) }
                .controlSize(.small)
                .disabled(isRestoring)
                .accessibilityLabel("Put back \(URL(fileURLWithPath: item.path).lastPathComponent)")
        case .conflict:
            restoreNote("Already replaced", help: "Something new is at the original location, so Purge won't overwrite it")
        case .noLongerInTrash:
            restoreNote("Not in Trash", help: "Already put back, or the Trash was emptied")
        case .notRestorable, .none:
            EmptyView()
        }
    }

    private func restoreNote(_ text: String, help: String) -> some View {
        Text(text)
            .font(AppStyle.Typography.metadata)
            .foregroundStyle(AppColors.textTertiary)
            .help(help)
    }

    private func skippedItemRow(_ item: CleanupHistorySkippedItemDTO) -> some View {
        let fileURL = URL(fileURLWithPath: item.path).standardizedFileURL

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(fileURL.lastPathComponent)
                    .font(AppStyle.Typography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Text(item.reason)
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(displayDirectoryPath(for: fileURL.deletingLastPathComponent()))
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private func historySectionCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppColors.fillSecondary,
                in: RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
                    .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }
    }
}
