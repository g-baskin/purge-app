import AppKit
import Combine
import SwiftUI

@MainActor final class DockerModel: ObservableObject {
    @Published private(set) var snapshot: DockerSnapshot?
    @Published private(set) var busy = false
    @Published private(set) var status = "Review your local Docker Desktop storage."
    @Published var errorMessage: String?
    private let client: DockerClient
    init(client: DockerClient = DockerClient()) { self.client = client }

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { snapshot = try await client.load(); status = "Docker Desktop · local context" }
        catch { snapshot = nil; status = error.localizedDescription }
    }

    func remove(_ item: DockerResource) async {
        guard !busy, let snapshot else { return }
        busy = true
        defer { busy = false }
        do {
            let grant = try await ProtectionAuthentication.authorize(urls: [DockerClient.dataRoot],
                dockerKey: item.protectionKey(daemonID: snapshot.daemonID))
            try await client.remove(item, daemonID: snapshot.daemonID, grant: grant)
            self.snapshot = nil
            status = "Docker accepted the removal. Shared layers or virtual-disk space may remain."
            do { self.snapshot = try await client.load() }
            catch { errorMessage = "Docker accepted the removal, but usage could not be refreshed. Refresh before taking further action. " + error.localizedDescription }
        } catch let error as ProtectionError {
            errorMessage = error.localizedDescription
        } catch {
            self.snapshot = nil
            errorMessage = "Docker could not confirm the action. Refresh before trying again. " + error.localizedDescription
        }
    }
}

struct DockerView: View {
    @StateObject private var model: DockerModel
    @ObservedObject private var protections: ProtectionModel
    @MainActor init(model: DockerModel? = nil, protections: ProtectionModel? = nil) {
        _model = StateObject(wrappedValue: model ?? DockerModel())
        _protections = ObservedObject(wrappedValue: protections ?? .shared)
    }
    @State private var pendingRemoval: DockerResource?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
                HStack {
                    Text(model.status).font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                    Button("Refresh") { Task { await model.refresh() } }.disabled(model.busy)
                }
                Text("Review before removing. Sizes may overlap because images and cache share layers. Removing an item does not guarantee that Docker’s virtual disk immediately shrinks.")
                    .font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textSecondary)
                if let snapshot = model.snapshot {
                    ForEach(DockerKind.allCases, id: \.rawValue) { kind in
                        section(kind, snapshot: snapshot)
                    }
                } else if !model.busy {
                    VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                        Label("Docker Desktop is not connected", systemImage: "shippingbox")
                            .font(AppStyle.Typography.sectionTitle)
                        Text("Start Docker Desktop when you want to review images, containers, volumes and build cache. Purge will not start it or clean anything automatically.")
                            .foregroundStyle(AppColors.textSecondary)
                        Button("Open Docker Desktop") {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.docker.docker") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    .padding(AppStyle.Spacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.surfaceCard, in: RoundedRectangle(cornerRadius: AppStyle.Radius.lg))
                }
            }
            .padding(AppStyle.Spacing.large)
        }
        .background(AppColors.surfaceBase)
        .task { if !TestHost.isActive() { await model.refresh() } }
        .alert(model.errorMessage == nil && protections.errorMessage == nil ? "Permanently remove this Docker item?" : "Docker",
            isPresented: Binding(get: { pendingRemoval != nil || model.errorMessage != nil || protections.errorMessage != nil },
                set: { if !$0 { pendingRemoval = nil; model.errorMessage = nil; protections.errorMessage = nil } })) {
            if let item = pendingRemoval, model.errorMessage == nil && protections.errorMessage == nil {
                Button("Cancel", role: .cancel) { pendingRemoval = nil }
                Button("Remove permanently", role: .destructive) {
                    Task { await model.remove(item) }
                    pendingRemoval = nil
                }
            } else {
                Button("OK", role: .cancel) { model.errorMessage = nil; protections.errorMessage = nil }
            }
        } message: {
            if let error = model.errorMessage ?? protections.errorMessage { Text(error) }
            else { Text("\(pendingRemoval?.name ?? "This item") will not go to Trash. Volumes may hold the only copy of database or app data: back them up first. Running or referenced objects will not be force-removed.") }
        }
    }

    private func section(_ kind: DockerKind, snapshot: DockerSnapshot) -> some View {
        let resources = snapshot.resources.filter { $0.kind == kind }
        return VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            HStack {
                Text(kind.rawValue).font(AppStyle.Typography.sectionTitle)
                Spacer()
                Text("\(resources.count) items").foregroundStyle(AppColors.textSecondary)
            }
            if resources.isEmpty { Text("No items reported.").foregroundStyle(AppColors.textSecondary) }
            ForEach(resources) { item in
                Divider()
                HStack(spacing: AppStyle.Spacing.small) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                        Text(item.detail).font(AppStyle.Typography.metadata).foregroundStyle(AppColors.textSecondary)
                        Text(String(item.objectID.prefix(48))).font(AppStyle.Typography.metadata)
                            .foregroundStyle(AppColors.textTertiary).lineLimit(1)
                    }
                    Spacer(minLength: AppStyle.Spacing.small)
                    Text(item.sizeBytes.map(formatBytes) ?? "Unknown size").monospacedDigit()
                    protectionButton(item, snapshot: snapshot)
                    Button("Remove", role: .destructive) { pendingRemoval = item }
                        .disabled(!item.canRemove || model.busy || !protections.available)
                }
                .padding(.vertical, AppStyle.Spacing.xSmall)
            }
        }
        .padding(AppStyle.Spacing.medium)
        .background(AppColors.surfaceCard, in: RoundedRectangle(cornerRadius: AppStyle.Radius.lg))
    }

    private func protectionButton(_ item: DockerResource, snapshot: DockerSnapshot) -> some View {
        let key = item.protectionKey(daemonID: snapshot.daemonID)
        let record = protections.items.first { $0.dockerKey == key }
        return Button {
            if let record { Task { await protections.remove(record) } }
            else { protections.addDocker(key: key, name: item.name) }
        } label: { Image(systemName: record == nil ? "lock.open" : "lock.fill") }
        .help(record == nil ? "Protect from deletion" : "Remove protection using Touch ID or password")
        .accessibilityLabel(record == nil ? "Protect \(item.name)" : "Remove protection for \(item.name)")
        .disabled(model.busy || protections.busy || !protections.available)
    }
}
