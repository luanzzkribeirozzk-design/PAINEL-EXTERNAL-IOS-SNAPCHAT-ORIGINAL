import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum PatchPackagePickerPolicy {
    static let packageType = UTType(filenameExtension: "3105") ?? .data
    static let allowedContentTypes: [UTType] = [packageType, .data]
    static let copiesSelectedDocument = true
}

private enum WallpaperPackagePickerPolicy {
    static let packageType = UTType(filenameExtension: "tendies") ?? .data
    static let allowedContentTypes: [UTType] = [packageType, .data]
}

struct PatchProjectsView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var draftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var store: PatchProjectStore
    @AppStorage(FeatureVisibility.cleanerStorageKey) private var cleanerEnabled = true
    @State private var showCreate = false
    @State private var showImporter = false
    @State private var showWallpaperImporter = false
    @State private var showCleaner = false
    @State private var searchText = ""
    @State private var wallpaperPackages: [WallpaperStagedPackage] = []
    @State private var wallpaperImportFeedback: WallpaperImportFeedback?
    @State private var wallpaperPendingDeletion: WallpaperStagedPackage?
    @State private var isImportingWallpapers = false
    @State private var showSimulatedWallpaperDetail = false
    @State private var simulatedWallpaperDetailGate = OneShotPresentationGate()
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    private var filteredItems: [PatchLibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.items }
        return store.items.filter { item in
            if item.packageURL.lastPathComponent.localizedCaseInsensitiveContains(query) {
                return true
            }
            guard let project = item.project else { return false }
            if project.name.localizedCaseInsensitiveContains(query)
                || project.author.localizedCaseInsensitiveContains(query) {
                return true
            }
            guard item.canInspectContents else { return false }
            return project.allBundleIdentifiers.contains {
                    $0.localizedCaseInsensitiveContains(query)
                }
                || project.directories.contains {
                    $0.relativePath.localizedCaseInsensitiveContains(query)
                }
                || project.rules.contains {
                    $0.relativePath.localizedCaseInsensitiveContains(query)
                        || $0.replacementFilename.localizedCaseInsensitiveContains(query)
                }
        }
    }

    private var filteredWallpaperPackages: [WallpaperStagedPackage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return wallpaperPackages }
        return wallpaperPackages.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    private var hasLocalContent: Bool {
        !store.items.isEmpty || !wallpaperPackages.isEmpty
    }

    private var hasSearchResults: Bool {
        !filteredItems.isEmpty || !filteredWallpaperPackages.isEmpty
    }

    init(
        onOpenSettings: @escaping () -> Void = {},
        onOpenLogs: @escaping () -> Void = {}
    ) {
        self.onOpenSettings = onOpenSettings
        self.onOpenLogs = onOpenLogs
#if targetEnvironment(simulator)
        _showCreate = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("--simulate-patch-editor")
        )
#endif
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    if !hasLocalContent && (store.isBusy || isImportingWallpapers) {
                        loadingState
                            .listRowSeparator(.hidden)
                    } else if !hasLocalContent {
                        emptyState
                            .listRowSeparator(.hidden)
                    } else if !hasSearchResults && !store.isBusy {
                        searchEmptyState
                            .listRowSeparator(.hidden)
                    } else {
                        if !filteredItems.isEmpty {
                            ForEach(filteredItems) { item in
                                itemRow(item)
                            }
                            .onDelete { offsets in
                                offsets.map { filteredItems[$0] }.forEach(store.delete)
                            }
                        }
                        if !filteredWallpaperPackages.isEmpty {
                            Section(language.text("tab.wallpapers")) {
                                ForEach(filteredWallpaperPackages) { package in
                                    NavigationLink {
                                        InstalledWallpaperPackageDetailView(
                                            package: package,
                                            onApplied: reloadWallpaperPackages
                                        )
                                    } label: {
                                        wallpaperRow(package)
                                    }
                                    .swipeActions(
                                        edge: .trailing,
                                        allowsFullSwipe: false
                                    ) {
                                        Button(role: .destructive) {
                                            wallpaperPendingDeletion = package
                                        } label: {
                                            Label(
                                                language.text("common.delete"),
                                                systemImage: "trash"
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showImporter) {
                FileDocumentPicker(
                    allowedContentTypes: PatchPackagePickerPolicy.allowedContentTypes,
                    copiesSelectedDocument: PatchPackagePickerPolicy.copiesSelectedDocument,
                    allowsMultipleSelection: false,
                    onSelection: { result in
                        showImporter = false
                        if case .success(let urls) = result, let url = urls.first {
                            store.importPackage(at: url)
                        }
                    },
                    onCancel: {
                        showImporter = false
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showCreate) {
                PatchProjectEditorView(
                    existingProject: nil,
                    passwordIsProtected: false
                ) { project, password in
                    store.create(project: project, password: password)
                }
            }
            .sheet(isPresented: $showCleaner) {
                CleanerView()
            }
            .sheet(item: $draftCoordinator.request) { request in
                PatchProjectEditorView(
                    existingProject: nil,
                    passwordIsProtected: false,
                    initialDraft: request.draft
                ) { project, password in
                    store.create(project: project, password: password)
                    draftCoordinator.clear()
                }
            }
            .sheet(isPresented: $showWallpaperImporter) {
                FileDocumentPicker(
                    allowedContentTypes: WallpaperPackagePickerPolicy.allowedContentTypes,
                    copiesSelectedDocument: true,
                    allowsMultipleSelection: true,
                    onSelection: { result in
                        showWallpaperImporter = false
                        if case .success(let urls) = result, !urls.isEmpty {
                            importWallpaperPackages(urls)
                        }
                    },
                    onCancel: {
                        showWallpaperImporter = false
                    }
                )
                .ignoresSafeArea()
            }
            .alert(item: $wallpaperImportFeedback) { feedback in
                Alert(
                    title: Text(language.text(feedback.titleKey)),
                    message: Text(feedback.message),
                    dismissButton: .default(Text(language.text("common.ok")))
                )
            }
            .alert(item: $wallpaperPendingDeletion) { package in
                Alert(
                    title: Text(language.text("wallpaper.delete_title")),
                    message: Text(language.text(
                        "wallpaper.delete_message",
                        package.displayName
                    )),
                    primaryButton: .destructive(
                        Text(language.text("common.delete"))
                    ) {
                        deleteWallpaperPackage(package)
                    },
                    secondaryButton: .cancel(Text(language.text("common.cancel")))
                )
            }
            .onAppear {
                reloadWallpaperPackages()
                consumeExternalImport()
#if targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains(
                    "--simulate-wallpaper-detail"
                ), !wallpaperPackages.isEmpty,
                   simulatedWallpaperDetailGate.claim() {
                    DispatchQueue.main.async {
                        showSimulatedWallpaperDetail = true
                    }
                }
#endif
            }
            .navigationDestination(isPresented: $showSimulatedWallpaperDetail) {
                if let package = wallpaperPackages.first {
                    InstalledWallpaperPackageDetailView(
                        package: package,
                        onApplied: reloadWallpaperPackages
                    )
                }
            }
            .onChange(of: draftCoordinator.importRequest?.id) { _ in
                consumeExternalImport()
            }
        }
    }

    private func consumeExternalImport() {
        guard let request = draftCoordinator.importRequest else { return }
        draftCoordinator.clearImport()
        store.importPackage(from: request.source)
    }

    private func wallpaperRow(_ package: WallpaperStagedPackage) -> some View {
        HStack(spacing: 12) {
            AppRowIcon(systemName: wallpaperSymbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(package.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                InstalledContentKindBadge(kind: .wallpaper, language: language)
                Text(language.text(
                    "wallpaper.package_summary",
                    Int64(package.payload.descriptors.count),
                    ByteCountFormatter.string(
                        fromByteCount: package.payload.totalBytes,
                        countStyle: .file
                    )
                ))
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private var cleanerRow: some View {
        Button {
            showCleaner = true
        } label: {
            HStack(spacing: 12) {
                AppRowIcon(systemName: "sparkles")
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text("tab.cleaner"))
                        .font(.body.weight(.semibold))
                    Text(language.text("repository.cleaner_subtitle"))
                        .font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var wallpaperSymbol: String {
        if #available(iOS 18.0, *) {
            return "photo.on.rectangle.angled.fill"
        }
        return "photo.fill.on.rectangle.fill"
    }

    private func reloadWallpaperPackages() {
        wallpaperPackages = WallpaperPackageStore.packages()
    }

    private func deleteWallpaperPackage(_ package: WallpaperStagedPackage) {
        do {
            try WallpaperPackageStore.delete(package)
            reloadWallpaperPackages()
        } catch {
            wallpaperImportFeedback = WallpaperImportFeedback(
                titleKey: "wallpaper.operation_failed",
                message: wallpaperErrorMessage(error)
            )
        }
    }

    private func importWallpaperPackages(_ urls: [URL]) {
        guard !isImportingWallpapers else { return }
        isImportingWallpapers = true
        DispatchQueue.global(qos: .userInitiated).async {
            var imported = 0
            var failures: [String] = []
            for url in urls {
                do {
                    _ = try WallpaperPackageStore.importPackage(from: url)
                    imported += 1
                    log("wallpaper: staged \(url.lastPathComponent)")
                } catch {
                    failures.append(
                        "\(url.lastPathComponent): \(wallpaperErrorMessage(error))"
                    )
                    log("wallpaper: import rejected \(url.lastPathComponent)")
                }
            }
            DispatchQueue.main.async {
                isImportingWallpapers = false
                reloadWallpaperPackages()
                wallpaperImportFeedback = WallpaperImportFeedback(
                    titleKey: failures.isEmpty
                        ? "wallpaper.import_done_title"
                        : "wallpaper.import_result_title",
                    message: failures.isEmpty
                        ? language.text(
                            "wallpaper.import_done_message",
                            Int64(imported)
                        )
                        : failures.joined(separator: "\n")
                )
            }
        }
    }

    private func wallpaperErrorMessage(_ error: Error) -> String {
        if let wallpaperError = error as? WallpaperLabError {
            return language.text(wallpaperError.localizationKey)
        }
        return language.text("wallpaper.error.unknown")
    }

    @ViewBuilder
    private func itemRow(_ item: PatchLibraryItem) -> some View {
        if item.isLocked {
            Button { store.requestUnlock(for: item) } label: {
                PatchProjectRow(item: item, language: language)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            NavigationLink {
                PatchProjectDetailView(store: store, projectID: item.id)
            } label: {
                PatchProjectRow(item: item, language: language)
            }
            .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
            Text(language.text("installed.empty_title"))
                .font(.headline)
            Text(language.text("installed.empty_message"))
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button(language.text("patch.new")) { showCreate = true }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(language.text("installed.loading"))
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
            Text(language.text("patch.search_empty"))
                .font(.headline)
            Text(language.text("patch.search_empty_message"))
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }
}

private struct WallpaperImportFeedback: Identifiable {
    let id = UUID()
    let titleKey: String
    let message: String
}

private struct PatchProjectRow: View {
    let item: PatchLibraryItem
    let language: AppLanguage

    private var patchFilename: String {
        item.packageURL.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        HStack(spacing: 12) {
            SnapchatPatchIcon(item: item)
            VStack(alignment: .leading, spacing: 3) {
                Text(patchFilename.isEmpty ? language.text("patch.locked_project") : patchFilename)
                    .font(.body.weight(.semibold))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                if let author = item.project?.author, !author.isEmpty {
                    Text(language.text("patch.by_author", author))
                        .font(.caption)
                }
            }
            Spacer()
            if item.summary.isPasswordProtected,
               item.project?.name.localizedCaseInsensitiveCompare("PAINEL EXTERNAL") != .orderedSame {
                Image(systemName: "key.fill")
                    .font(.caption)
                    .accessibilityLabel(language.text("patch.password_protected"))
            }
            if item.project?.isPrivate == true {
                Image(systemName: "eye.slash.fill")
                    .font(.caption)
                    .accessibilityLabel(language.text("patch.private"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            AppTheme.animatedTextColor(at: Date()),
                            AppTheme.animatedTextColor(at: Date().addingTimeInterval(4))
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: AppTheme.accent.opacity(0.14), radius: 12, y: 6)
    }
}

private enum InstalledContentKind {
    case patch
    case wallpaper

    var localizationKey: String {
        switch self {
        case .patch: return "installed.kind.patch"
        case .wallpaper: return "installed.kind.wallpaper"
        }
    }

    var systemImage: String {
        switch self {
        case .patch: return "shippingbox.fill"
        case .wallpaper: return "photo.fill"
        }
    }
}

private struct InstalledContentKindBadge: View {
    let kind: InstalledContentKind
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.systemImage)
                .accessibilityHidden(true)
            Text(language.text(kind.localizationKey))
        }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(AppTheme.accent.opacity(0.12), in: Capsule())
            .fixedSize()
            .accessibilityElement(children: .combine)
    }
}

struct PatchUnlockView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PatchProjectStore
    let request: PatchPasswordRequest
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(language.text("patch.password"), text: $password)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit(unlock)
                        .onChange(of: password) { _ in
                            store.clearUnlockError()
                        }
                    if let errorKey = store.unlockErrorKey {
                        Text(language.text(errorKey))
                            .font(.footnote)
                    }
                } footer: {
                    if let origin = request.origin {
                        Text(language.text(
                            "patch.password_repo_contact",
                            origin.repositoryName
                        ))
                    } else {
                        Text(language.text("patch.password_once_message"))
                    }
                }
            }
            .navigationTitle(language.text("patch.unlock"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("patch.unlock"), action: unlock)
                        .disabled(password.isEmpty || store.isBusy)
                }
            }
        }
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        store.unlock(password: password)
    }
}

private struct PatchStorePresentationModifier: ViewModifier {
    @ObservedObject var store: PatchProjectStore

    func body(content: Content) -> some View {
        content
            .sheet(item: $store.passwordRequest, onDismiss: store.cancelUnlock) { request in
                PatchUnlockView(store: store, request: request)
            }
    }
}

extension View {
    func patchStorePresentation(_ store: PatchProjectStore) -> some View {
        modifier(PatchStorePresentationModifier(store: store))
    }
}

private struct PatchProjectDetailView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var store: PatchProjectStore
    let projectID: UUID
    @State private var showEditor = false
    @State private var editingRule: PatchRule?
    @State private var showApplyConfirmation = false
    @State private var showRestoreConfirmation = false
    @State private var showChangedRestoreConfirmation = false
    @State private var showResetConfirmation = false
    @State private var restoreChangedPaths: [String] = []
    @State private var isWorking = false
    @State private var isApplied = false
    @State private var actionAlert: PatchStoreAlert?
    @State private var shareRequest: PatchShareRequest?

    private var item: PatchLibraryItem? {
        store.items.first(where: { $0.id == projectID })
    }

    private var receipt: PatchTransactionReceipt? {
        DevicePatchService.latestReceipt(projectID: projectID)
    }

    private var isWorkspaceProject: Bool {
        (item?.summary.schemaVersion ?? 1) >= 2
    }

    private var patchFilename: String {
        guard let item else { return language.text("patch.title") }
        let name = item.packageURL.deletingPathExtension().lastPathComponent
        return name.isEmpty ? language.text("patch.title") : name
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            if !isApplied {
                Button {
                    apply()
                } label: {
                    Label("ATIVAR", systemImage: "checkmark.shield.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SnapchatActionButtonStyle())
                .disabled(isWorking)
            } else {
                Button(role: .destructive) {
                    restore(allowChangedTargets: true)
                } label: {
                    Label("DESATIVAR", systemImage: "arrow.uturn.backward.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SnapchatActionButtonStyle(isDestructive: true))
                .disabled(isWorking)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .navigationTitle(patchFilename)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isApplied = receipt != nil
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isWorking {
                    ProgressView()
                }
            }
        }
        .alert(item: $actionAlert) { alert in
            Alert(
                title: Text(language.text(alert.titleKey)),
                message: Text(alert.message(language: language)),
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
    }

    private func actionLabel(_ key: String, systemImage: String) -> some View {
        Label(language.text(key), systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func patchInfoRow(
        label: String,
        value: String
    ) -> some View {
        patchInfoRow(label: label) {
            Text(value)
        }
    }

    private func patchInfoRow<Content: View>(
        label: String,
        @ViewBuilder value: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
            Spacer(minLength: 16)
            value()
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .padding(.vertical, 5)
    }

    private func ruleSummary(_ rule: PatchRule) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(rule.bundleID)
                .font(.subheadline.weight(.semibold))
            Text(rule.relativePath)
                .font(.caption.monospaced())
                .lineLimit(2)
            Label(rule.replacementFilename, systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
        }
        .padding(.vertical, 3)
    }

    private func updateRule(_ updatedRule: PatchRule) {
        guard var project = item?.project,
              let index = project.rules.firstIndex(where: { $0.id == updatedRule.id }) else {
            return
        }
        project.rules[index] = updatedRule
        project.updatedAt = Date()
        do {
            try PatchPackageCodec.validate(project)
            store.update(project: project)
        } catch let error as PatchPackageError {
            actionAlert = PatchStoreAlert(
                titleKey: "common.failed",
                messageKey: error.localizationKey,
                messageArgument: error.localizationArgument
            )
        } catch {
            actionAlert = PatchStoreAlert(
                titleKey: "common.failed",
                messageKey: "patch.error.invalid_project"
            )
        }
    }

    private func apply() {
        guard let item, let baseProject = item.project else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                let project = item.summary.schemaVersion >= 2 && item.canInspectContents
                    ? try PatchProjectLibrary.synchronizeWorkspace(item: item)
                    : baseProject
                _ = try DevicePatchService.apply(project: project)
                await MainActor.run {
                    store.reload()
                    isApplied = true
                    isWorking = false
                    actionAlert = nil
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: privateErrorKey(for: error),
                        messageArgument: privateErrorArgument(for: error)
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: "patch.error.apply")
                }
            }
        }
    }

    private func prepareExport() {
        guard let item else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                if item.summary.schemaVersion >= 2, item.canInspectContents {
                    _ = try PatchProjectLibrary.synchronizeWorkspace(item: item)
                }
                await MainActor.run {
                    store.reload()
                    isWorking = false
                    shareRequest = PatchShareRequest(url: item.packageURL)
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: privateErrorKey(for: error),
                        messageArgument: privateErrorArgument(for: error)
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: "patch.error.invalid_project"
                    )
                }
            }
        }
    }

    private var changedRestoreMessage: String {
        guard item?.project?.isPrivate != true || item?.isAuthorCopy == true else {
            return language.text(
                "patch.restore_changed_private_message",
                Int64(restoreChangedPaths.count)
            )
        }
        var visiblePaths = restoreChangedPaths.prefix(5).joined(separator: "\n")
        if restoreChangedPaths.count > 5 {
            visiblePaths += "\n…"
        }
        return language.text(
            "patch.restore_changed_message",
            Int64(restoreChangedPaths.count),
            visiblePaths
        )
    }

    private func prepareRestore() {
        guard let receipt else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                let inspection = try DevicePatchService.inspectRestore(receipt: receipt)
                if inspection.changedTargets.isEmpty {
                    try DevicePatchService.restore(receipt: receipt)
                    await MainActor.run {
                        isApplied = false
                        isWorking = false
                        actionAlert = nil
                    }
                } else {
                    await MainActor.run {
                        isWorking = false
                        restoreChangedPaths = inspection.changedTargets.map(\.displayPath)
                        showChangedRestoreConfirmation = true
                    }
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: privateErrorKey(for: error),
                        messageArgument: privateErrorArgument(for: error)
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: "patch.error.restore"
                    )
                }
            }
        }
    }

    private func restore(allowChangedTargets: Bool) {
        guard let receipt else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                try DevicePatchService.restore(
                    receipt: receipt,
                    allowChangedTargets: allowChangedTargets
                )
                await MainActor.run {
                    isApplied = false
                    isWorking = false
                    actionAlert = nil
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: privateErrorKey(for: error),
                        messageArgument: privateErrorArgument(for: error)
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: "patch.error.restore")
                }
            }
        }
    }

    private func resetToAppliedState() {
        guard let receipt, let project = item?.project else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                try DevicePatchService.resetToAppliedState(
                    receipt: receipt,
                    project: project
                )
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.done",
                        messageKey: "patch.reset_message"
                    )
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: privateErrorKey(for: error),
                        messageArgument: privateErrorArgument(for: error)
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: "patch.error.reset"
                    )
                }
            }
        }
    }

    private func privateErrorKey(for error: PatchPackageError) -> String {
        guard item?.project?.isPrivate == true,
              item?.isAuthorCopy == false else {
            return error.localizationKey
        }
        return "patch.error.private_operation"
    }

    private func privateErrorArgument(for error: PatchPackageError) -> String? {
        guard item?.project?.isPrivate == true,
              item?.isAuthorCopy == false else {
            return error.localizationArgument
        }
        return nil
    }
}

private struct PatchShareRequest: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PatchActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
