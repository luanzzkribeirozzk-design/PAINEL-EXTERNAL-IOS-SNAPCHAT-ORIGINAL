import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var patchStore: PatchProjectStore
    @EnvironmentObject private var repositoryStore: PackageRepositoryStore
    @AppStorage(FeatureVisibility.developerModeStorageKey)
    private var developerModeEnabled = false
    @AppStorage(VisualPreferences.appearanceKey)
    private var appearanceRawValue = VisualAppearance.system.rawValue
    @State private var tabNavigation: AppTabNavigationState
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var showLaunchScreen = true

    init() {
#if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        let initialTab: Int
        if arguments.contains("--simulate-new-tab") {
            initialTab = 1
        } else if arguments.contains("--simulate-sources-tab") {
            initialTab = 2
        } else if arguments.contains("--simulate-installed-tab")
                    || arguments.contains("--simulate-patch-tab")
                    || arguments.contains("--simulate-wallpaper-tab") {
            initialTab = 3
        } else if arguments.contains("--simulate-files-tab") {
            initialTab = 4
        } else if arguments.contains("--simulate-search-tab") {
            initialTab = 5
        } else {
            initialTab = AppSection.installed.rawValue
        }
        _tabNavigation = State(initialValue: AppTabNavigationState(selectedTab: initialTab))
        _showSettings = State(
            initialValue: arguments.contains("--simulate-settings")
        )
#else
        _tabNavigation = State(initialValue: AppTabNavigationState())
#endif
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .tint(AppTheme.accent)
        .imageScale(.small)
        .animatedTextAppearance()
        .background(SnapchatAnimatedBackground())
        .preferredColorScheme(VisualAppearance(rawValue: appearanceRawValue)?.colorScheme)
        .onChange(of: patchDraftCoordinator.request?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.installed.rawValue) }
        }
        .onChange(of: patchDraftCoordinator.importRequest?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.installed.rawValue) }
        }
        .onChange(of: developerModeEnabled) { _ in
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .onAppear {
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLogs) { LogView() }
        .patchStorePresentation(patchStore)
        .repositoryStorePresentation(repositoryStore, patchStore: patchStore)
        .overlay {
            if showLaunchScreen {
                SnapchatLaunchView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showLaunchScreen = false
                    }
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
    }

    private var compactLayout: some View {
        TabView(selection: tabSelection) {
            ForEach(featureVisibility.visibleSections) { section in
                sectionContent(section)
                    .tabItem {
                        CompactTabLabel(
                            title: language.text(section.titleKey),
                            systemImage: section.systemImage
                        )
                    }
                    .tag(section.rawValue)
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List {
                ForEach(featureVisibility.visibleSections) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            tabNavigation.select(section.rawValue)
                        }
                    } label: {
                        Label(language.text(section.titleKey), systemImage: section.systemImage)
                            .fontWeight(section.rawValue == tabNavigation.selectedTab ? .semibold : .regular)
                            .animatedTextAppearance()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        section.rawValue == tabNavigation.selectedTab
                            ? AppTheme.accent.opacity(0.14)
                            : Color.clear
                    )
                    .accessibilityAddTraits(
                        section.rawValue == tabNavigation.selectedTab ? .isSelected : []
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("EXTERNAL IOS")
                        .font(.headline.weight(.bold))
                        .animatedTextAppearance()
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            sectionContent(selectedVisibleSection)
                .id(selectedVisibleSection.rawValue)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .home:
            RepositoryHomeView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .new:
            RepositoryNewView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .sources:
            RepositorySourcesView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .installed:
            PatchProjectsView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .files:
            AppDataBrowserView(
                tabSession: filesTabSession,
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .search:
            RepositorySearchView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { tabNavigation.selectedTab },
            set: { tabNavigation.select($0) }
        )
    }

    private var filesTabSession: Binding<FilesTabSession> {
        Binding(
            get: { tabNavigation.filesTabs },
            set: { tabNavigation.setFilesTabs($0) }
        )
    }

    private var featureVisibility: FeatureVisibility {
        FeatureVisibility(developerModeEnabled: developerModeActive)
    }

    private var developerModeActive: Bool {
#if targetEnvironment(simulator)
        developerModeEnabled
            || ProcessInfo.processInfo.arguments.contains("--simulate-developer-mode")
            || ProcessInfo.processInfo.arguments.contains("--simulate-files-tab")
#else
        developerModeEnabled
#endif
    }

    private var selectedVisibleSection: AppSection {
        let selected = AppSection(rawValue: tabNavigation.selectedTab)
        return selected.flatMap {
            featureVisibility.isVisible($0) ? $0 : nil
        } ?? .installed
    }

    private func openSettings() {
        showSettings = true
    }

    private func openLogs() {
        showLogs = true
    }
}

private struct CompactTabLabel: View {
    let title: String
    let systemImage: String

    @ViewBuilder
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { timeline in
            Group {
                if let image = UIImage(
                    systemName: systemImage,
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
                )?.withRenderingMode(.alwaysTemplate) {
                    Image(uiImage: image)
                } else if !systemImage.isEmpty {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .medium))
                }
                Text(title)
            }
            .foregroundStyle(AppTheme.animatedTextColor(at: timeline.date))
            .saturation(10)
            .brightness(0.10)
        }
    }
}

private extension AppSection {
    var titleKey: String {
        switch self {
        case .home: return "tab.home"
        case .new: return "tab.new"
        case .sources: return "tab.sources"
        case .installed: return "tab.panel"
        case .files: return "tab.files"
        case .search: return "tab.search"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .new: return "clock.fill"
        case .sources: return "shippingbox.fill"
        case .installed: return ""
        case .files: return "folder.fill"
        case .search: return "magnifyingglass"
        }
    }
}


struct LicenseLoginView: View {
    @EnvironmentObject private var session: LicenseSession
    @State private var clipboardKey = ""
    @State private var pasteMessage = ""

    var body: some View {
        ZStack {
            SnapchatAnimatedBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 55)
                    ZStack {
                        Circle().fill(AppTheme.accent.opacity(0.20)).frame(width: 104, height: 104).blur(radius: 8)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    VStack(spacing: 6) {
                        Text("EXTERNAL IOS")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("ACESSE COLANDO SUA KEY")
                            .font(.caption.weight(.bold))
                            .tracking(2.0)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    VStack(spacing: 10) {
                        HStack {
                            Image(systemName: clipboardKey.isEmpty ? "doc.on.clipboard" : "checkmark.circle.fill")
                            Text(clipboardKey.isEmpty ? "Nenhuma key colada" : "Key pronta para entrar")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        .foregroundStyle(clipboardKey.isEmpty ? .white.opacity(0.55) : AppTheme.accent)
                        .padding(17)
                        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.16)))
                    }
                    HStack(spacing: 12) {
                        Button {
                            let value = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            clipboardKey = value
                            pasteMessage = value.isEmpty ? "A área de transferência está vazia." : "Key colada."
                        } label: {
                            Label("COLAR", systemImage: "doc.on.clipboard.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LoginSecondaryButtonStyle())
                        Button { session.activate(key: clipboardKey) } label: {
                            if session.isLoading { ProgressView().tint(.white) }
                            else { Label("ENTRAR", systemImage: "arrow.right.circle.fill") }
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(LoginPrimaryButtonStyle())
                        .disabled(session.isLoading || clipboardKey.isEmpty)
                    }
                    if !pasteMessage.isEmpty {
                        Text(pasteMessage).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                    }
                    if let message = session.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red.opacity(0.95))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

private struct LoginPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.black)).foregroundStyle(.white)
            .padding(.vertical, 16)
            .background(AppTheme.accent.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: AppTheme.accent.opacity(0.35), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct LoginSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.black)).foregroundStyle(.white.opacity(0.92))
            .padding(.vertical, 16)
            .background(.white.opacity(configuration.isPressed ? 0.17 : 0.09), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.accent.opacity(0.65), lineWidth: 1.2))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
