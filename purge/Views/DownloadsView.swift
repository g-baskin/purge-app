import AppKit
import SwiftUI

struct DownloadsView: View {
    @StateObject private var model: DownloadsModel
    @ObservedObject private var protections: ProtectionModel
    @MainActor init(model: DownloadsModel? = nil, protections: ProtectionModel? = nil) {
        _model = StateObject(wrappedValue: model ?? DownloadsModel())
        _protections = ObservedObject(wrappedValue: protections ?? .shared)
    }
    @State private var query = ""
    @State private var newestFirst = false
    @State private var confirmTrash = false

    private var displayed: [DownloadEntry] {
        model.items.filter { query.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) }.sorted {
            newestFirst ? ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) : ($0.sizeBytes ?? -1) > ($1.sizeBytes ?? -1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
            HStack {
                TextField("Search Downloads", text: $query).textFieldStyle(.roundedBorder)
                Picker("Sort", selection: $newestFirst) {
                    Text("Largest first").tag(false)
                    Text("Newest first").tag(true)
                }.frame(width: 170)
                Button("Refresh") { Task { await model.refresh() } }.disabled(model.busy)
                Button("Move selected to Trash", role: .destructive) { confirmTrash = true }
                    .disabled(model.selection.isEmpty || model.busy || !protections.available)
            }
            Text("Nothing is selected automatically. Folders stay unmeasured until you choose Measure or delete them. Protected items require Touch ID or your Mac login password.")
                .font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textSecondary)
            if model.busy { ProgressView().controlSize(.small) }
            if let message = model.message {
                Text(message).font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textSecondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if displayed.isEmpty && !model.busy {
                        Text(query.isEmpty ? "No downloads to review." : "No matching downloads.")
                            .foregroundStyle(AppColors.textSecondary).padding(AppStyle.Spacing.medium)
                    }
                    ForEach(displayed) { item in
                        row(item)
                        Divider()
                    }
                }
                .padding(AppStyle.Spacing.small)
                .background(AppColors.surfaceCard, in: RoundedRectangle(cornerRadius: AppStyle.Radius.lg))
            }
        }
        .padding(AppStyle.Spacing.large)
        .background(AppColors.surfaceBase)
        .task { if !TestHost.isActive() { await model.refresh() } }
        .alert(confirmTrash && model.errorMessage == nil && protections.errorMessage == nil ? "Move selected downloads to Trash?" : "Downloads",
            isPresented: Binding(get: { confirmTrash || model.errorMessage != nil || protections.errorMessage != nil },
                set: { if !$0 { confirmTrash = false; model.errorMessage = nil; protections.errorMessage = nil } })) {
            if confirmTrash && model.errorMessage == nil && protections.errorMessage == nil {
                Button("Cancel", role: .cancel) { confirmTrash = false }
                Button("Move to Trash", role: .destructive) {
                    let confirmedIDs = model.selection
                    Task { await model.trashSelection(confirmedIDs) }
                    confirmTrash = false
                }
            } else {
                Button("OK", role: .cancel) { model.errorMessage = nil; protections.errorMessage = nil }
            }
        } message: {
            if let error = model.errorMessage ?? protections.errorMessage { Text(error) }
            else { Text("Only the selected items will move. You can restore them from Trash until it is emptied. Protection stays enabled after an authenticated deletion.") }
        }
    }

    private func row(_ item: DownloadEntry) -> some View {
        let locked = protections.contains(item.url)
        return HStack(spacing: AppStyle.Spacing.small) {
            Toggle(isOn: Binding(get: { model.selection.contains(item.id) }, set: {
                if $0 { model.selection.insert(item.id) } else { model.selection.remove(item.id) }
            })) { EmptyView() }.toggleStyle(.checkbox).labelsHidden()
                .accessibilityLabel("Select \(item.url.lastPathComponent)")
            Image(systemName: item.isFolder ? "folder" : "doc").foregroundStyle(AppColors.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                if let date = item.modified {
                    Text(date, style: .date).font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer()
            if let size = item.sizeBytes { Text(formatBytes(size)).monospacedDigit() }
            else { Button("Measure folder") { Task { await model.measure(item) } }.disabled(model.busy) }
            Button { protections.add([item.url]) } label: { Image(systemName: locked ? "lock.fill" : "lock.open") }
                .disabled(locked || model.busy || !protections.available)
                .help(locked ? "Protected. Manage protection in Settings." : "Protect from deletion")
                .accessibilityLabel(locked ? "Protected: \(item.url.lastPathComponent)" : "Protect \(item.url.lastPathComponent)")
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "folder") }
                .help("Show in Finder").accessibilityLabel("Show \(item.url.lastPathComponent) in Finder")
        }
        .padding(AppStyle.Spacing.small)
        .disabled(model.busy)
    }
}
