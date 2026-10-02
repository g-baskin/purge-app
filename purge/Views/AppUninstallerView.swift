import AppKit
import SwiftUI

/// Uninstaller tab: the third-party apps in the Applications folders. Choosing one
/// opens a review of everything that would move to the Trash; nothing moves here.
struct AppUninstallerView: View {
    @EnvironmentObject private var store: PurgeStore
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleApps: [InstalledApp] {
        guard !trimmedQuery.isEmpty else { return store.installedApps }
        return store.installedApps.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.bundleID.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppColors.bgBase)
    }

    private var controls: some View {
        HStack(spacing: AppStyle.Spacing.small) {
            LargeFileSearchField(query: $query, accessibilityText: "Search apps by name")
            Text("Choose an app to see what it leaves behind.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppDetailPageLayout.horizontalInset)
        .padding(.top, 4)
        .padding(.bottom, AppStyle.Spacing.xSmall)
    }

    @ViewBuilder
    private var content: some View {
        if store.installedApps.isEmpty {
            if store.isScanningApps || !store.hasScannedApps {
                ProgressView("Looking for apps…")
                    .controlSize(.small)
            } else {
                placeholder(
                    symbol: "checkmark.circle",
                    title: "No Apps to Uninstall",
                    detail: "Apps that come with macOS aren't listed, and neither is Purge."
                )
            }
        } else if visibleApps.isEmpty {
            VStack(spacing: 4) {
                Text("Nothing here.")
                    .font(.headline)
                Text("No apps match \"\(trimmedQuery)\".")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Button("Clear Search") { query = "" }
                    .buttonStyle(.link)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 24)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(visibleApps) { app in
                        AppUninstallerRow(
                            app: app,
                            isFindingFiles: store.appBeingReviewedID == app.id,
                            isBusy: store.appBeingReviewedID != nil || store.isDeleting
                        ) {
                            Task { await store.reviewUninstall(of: app) }
                        }
                    }
                }
                .padding(.horizontal, AppDetailPageLayout.horizontalInset - ScanListRowInsets.standard.leading)
                .padding(.vertical, AppStyle.Spacing.xSmall)
                ScanListBottomSpacer()
            }
        }
    }

    private func placeholder(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3)
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }
}

struct AppUninstallerHeaderActions: View {
    @EnvironmentObject private var store: PurgeStore

    var body: some View {
        Button {
            Task { await store.scanInstalledApps() }
        } label: {
            CleaningButtonLabel(
                title: store.isScanningApps ? "Scanning..." : "Scan",
                systemImage: store.isScanningApps ? nil : "arrow.clockwise",
                isCleaning: store.isScanningApps
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
        }
        .buttonStyle(AppButtonStyle(variant: .bordered, isCapsule: true))
        .disabled(store.isScanningApps || store.isDeleting)
        .fixedSize()
    }
}

private struct AppUninstallerRow: View {
    let app: InstalledApp
    let isFindingFiles: Bool
    let isBusy: Bool
    let onReview: () -> Void

    private var details: String {
        var parts: [String] = []
        if let version = app.version, !version.isEmpty { parts.append("Version \(version)") }
        if app.isAppStoreApp { parts.append("App Store") }
        parts.append(appLocationLabel(app.bundleURL))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onReview) {
            HStack(spacing: 12) {
                AppBundleIcon(url: app.bundleURL, size: AppStyle.Row.listIconFrameSize)

                VStack(alignment: .leading, spacing: 4) {
                    Text(app.displayName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let size = app.sizeBytes {
                    Text(formatBytes(size))
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                } else {
                    Text("Measuring…")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                Group {
                    if isFindingFiles {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 16)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, AppStyle.Row.scanCardHorizontalPadding)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .modifier(ScanRowCardChrome())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(app.displayName), \(app.sizeBytes.map(formatBytes) ?? "size not measured yet")")
        .accessibilityHint("Shows what moves to the Trash if you uninstall it")
    }
}

/// The folder the app sits in, written like Purge's other paths:
/// "/Applications", "/Applications/Vendor" or "~/Applications".
private func appLocationLabel(_ bundleURL: URL) -> String {
    (bundleURL.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
}

/// The app's own Finder icon, loaded once per row.
private struct AppBundleIcon: View {
    let url: URL
    let size: CGFloat
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: url) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }
    }
}

// MARK: - Review sheet

/// Everything that would move to the Trash, chosen item by item. Files that only
/// share the app's name start unticked; nothing is removed until the user confirms.
struct AppUninstallSheet: View {
    let review: AppUninstallReview
    let onCancel: () -> Void
    let onConfirm: (_ includeApp: Bool, _ selectedItemIDs: Set<String>) -> Void

    @EnvironmentObject private var store: PurgeStore
    @State private var includeApp: Bool
    @State private var selectedIDs: Set<String>
    @State private var isRunning = false

    init(
        review: AppUninstallReview,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (_ includeApp: Bool, _ selectedItemIDs: Set<String>) -> Void
    ) {
        self.review = review
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        let canMove = review.app.canMoveBundle
        _includeApp = State(initialValue: canMove)
        // When the app itself can't be removed, nothing starts ticked: removing an
        // installed app's data resets it, so that has to be a deliberate choice.
        let defaults = canMove ? review.relatedItems.filter(\.isSelectedByDefault).map(\.id) : []
        _selectedIDs = State(initialValue: Set(defaults))
    }

    private var app: InstalledApp { review.app }
    private var removesApp: Bool { includeApp && app.canMoveBundle }
    private var ownedItems: [AppRelatedItem] { review.relatedItems.filter { $0.match == .bundleID } }
    private var possibleItems: [AppRelatedItem] { review.relatedItems.filter { $0.match == .name } }

    private var selectedBytes: Int64 {
        let files = review.relatedItems
            .filter { selectedIDs.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.sizeBytes }
        return files + (removesApp ? app.sizeBytes ?? 0 : 0)
    }

    private var selectedCount: Int {
        selectedIDs.count + (removesApp ? 1 : 0)
    }

    /// An open app can recreate or overwrite its files, so it has to be quit first,
    /// whether the app itself goes or only its files do.
    private var canConfirm: Bool {
        selectedCount > 0 && !isRunning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
                    appSection
                    if !ownedItems.isEmpty {
                        itemSection(
                            title: "Files that belong to \(app.displayName)",
                            detail: nil,
                            items: ownedItems
                        )
                    }
                    if !possibleItems.isEmpty {
                        itemSection(
                            title: "Might belong to \(app.displayName)",
                            detail: "These share the app's name but could belong to something else. Check them before ticking.",
                            items: possibleItems
                        )
                    }
                    if review.relatedItems.isEmpty {
                        Text("Purge found no other files for this app in your Library folder.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 200, maxHeight: 380)

            notices

            footer
        }
        .padding(20)
        .frame(width: 580)
        .task {
            while !Task.isCancelled {
                isRunning = store.isAppRunning(app)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            AppBundleIcon(url: app.bundleURL, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Uninstall \(app.displayName)?")
                    .font(.title3.weight(.semibold))
                Text("Everything ticked moves to the Trash. You can put it back from Cleanup History in Settings until you empty the Trash.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("The app")
            Toggle(isOn: $includeApp) {
                AppUninstallItemLabel(
                    symbol: "app",
                    appIconURL: app.bundleURL,
                    title: app.displayName + ".app",
                    subtitle: appLocationLabel(app.bundleURL),
                    sizeBytes: app.sizeBytes,
                    revealURL: app.bundleURL
                )
            }
            .toggleStyle(.checkbox)
            .disabled(!app.canMoveBundle)

            if !app.canMoveBundle {
                Text(AppUninstallPolicy.AppBundleRefusal.needsAdminPassword.explanation)
                    .font(.caption)
                    .foregroundStyle(AppColors.tagCheckText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func itemSection(title: String, detail: String?, items: [AppRelatedItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(title)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(items) { item in
                Toggle(isOn: selectionBinding(for: item.id)) {
                    AppUninstallItemLabel(
                        symbol: item.kind.symbolName,
                        title: item.url.lastPathComponent,
                        subtitle: item.kind.label + " · "
                            + (item.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath,
                        sizeBytes: item.sizeBytes,
                        revealURL: item.url
                    )
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    @ViewBuilder
    private var notices: some View {
        if isRunning && selectedCount > 0 {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.tagCheckText)
                    .accessibilityHidden(true)
                Text("\(app.displayName) is open. Quit it first.")
                    .font(.subheadline)
                Spacer(minLength: 8)
                Button("Quit \(app.displayName)") {
                    NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
                        .filter { $0.bundleURL?.standardizedFileURL.path == app.bundleURL.path }
                        .forEach { $0.terminate() }
                }
            }
        } else if !removesApp && selectedCount > 0 {
            Text("\(app.displayName) stays installed. Removing its files resets it, and it may make some of them again next time it opens.")
                .font(.caption)
                .foregroundStyle(AppColors.tagCheckText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Text(selectedCount == 0
                 ? "Nothing selected"
                 : "\(selectedCount) item\(selectedCount == 1 ? "" : "s") · \(formatBytes(selectedBytes))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Move to Trash", role: .destructive) {
                onConfirm(removesApp, selectedIDs)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .keyboardShortcut(.defaultAction)
            .disabled(!canConfirm)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppColors.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    private func selectionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { isOn in
                if isOn { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
            }
        )
    }
}

private struct AppUninstallItemLabel: View {
    let symbol: String
    /// Shows the app's own icon instead of `symbol`. The plain "app" symbol is a
    /// rounded square that reads as a second, empty checkbox next to the real one.
    var appIconURL: URL? = nil
    let title: String
    let subtitle: String
    let sizeBytes: Int64?
    let revealURL: URL

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let appIconURL {
                    AppBundleIcon(url: appIconURL, size: 18)
                } else {
                    Image(systemName: symbol)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 18)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let sizeBytes {
                Text(formatBytes(sizeBytes))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([revealURL])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            .accessibilityLabel("Show \(title) in Finder")
        }
    }
}
