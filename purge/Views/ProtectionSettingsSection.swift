import AppKit
import Combine
import SwiftUI

@MainActor final class ProtectionModel: ObservableObject {
    static let shared = ProtectionModel()
    @Published private(set) var items: [ProtectedItem] = []
    @Published private(set) var available = true
    @Published private(set) var busy = false
    @Published var errorMessage: String?
    let store: DeletionProtection

    init(store: DeletionProtection = .shared) {
        self.store = store
        refresh()
    }
    func refresh() {
        do { items = try store.snapshot(); available = true }
        catch { available = false; errorMessage = error.localizedDescription }
    }
    func contains(_ url: URL) -> Bool {
        // Rendering must not resolve hundreds of bookmarks or touch network disks per row.
        // The backend always performs the authoritative identity/bookmark check before deletion.
        let path = url.standardizedFileURL.path
        return items.contains { item in item.path.map { DeletionProtection.overlaps($0, path) } ?? false }
    }
    func containsDocker(_ key: String) -> Bool { items.contains { $0.dockerKey == key } }
    func add(_ urls: [URL]) {
        do { for url in urls { try store.protect(url: url) }; refresh() }
        catch { errorMessage = error.localizedDescription; refresh() }
    }
    func addDocker(key: String, name: String) {
        do { try store.protectDocker(key: key, name: name); refresh() }
        catch { errorMessage = error.localizedDescription; refresh() }
    }
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Protect files, folders or apps"
        panel.prompt = "Protect"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK { add(panel.urls) }
    }
    func remove(_ item: ProtectedItem) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            guard let grant = try await ProtectionAuthentication.authorize(store: store, items: [item]) else {
                throw ProtectionError.authentication
            }
            try store.remove(item, grant: grant)
            refresh()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct ProtectionSettingsSection: View {
    @ObservedObject private var model: ProtectionModel
    @MainActor init(model: ProtectionModel? = nil) { _model = ObservedObject(wrappedValue: model ?? .shared) }
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            HStack {
                Label("Protected items", systemImage: "lock.shield")
                    .font(AppStyle.Typography.sectionTitle)
                Spacer()
                Button("Protect file, folder or app…") { model.chooseFiles() }
                    .disabled(model.busy || !model.available)
            }
            Text("Protected deletions require Touch ID or your Mac login password. Locks stay on after each approval. Scheduled cleaning skips them.")
                .font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textSecondary)
            Text("Folders protect their contents. Protect separate app support folders too if needed. These locks apply inside Purge, not in Finder or other apps.")
                .font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textSecondary)
            if !model.available {
                Label("Protection records need attention. Deletion is blocked.", systemImage: "exclamationmark.triangle")
            } else if model.items.isEmpty {
                Text("No protected items yet.").foregroundStyle(AppColors.textSecondary)
            }
            ForEach(model.items) { item in
                HStack(spacing: AppStyle.Spacing.small) {
                    Image(systemName: "lock.fill").foregroundStyle(AppColors.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).lineLimit(1)
                        Text(item.path ?? "Docker resource").font(AppStyle.Typography.metadata)
                            .foregroundStyle(AppColors.textSecondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button("Remove protection") { Task { await model.remove(item) } }
                        .disabled(model.busy)
                }
                .padding(.vertical, AppStyle.Spacing.xSmall)
            }
        }
        .padding(AppStyle.Spacing.medium)
        .background(AppColors.surfaceCard, in: RoundedRectangle(cornerRadius: AppStyle.Radius.lg))
        .onAppear { model.refresh() }
        .alert("Protection", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}
