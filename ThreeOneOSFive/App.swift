import SwiftUI
import UIKit
import Foundation
import Security

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var licenseSession = LicenseSession()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var patchStore = PatchProjectStore()
    @StateObject private var repositoryStore = PackageRepositoryStore()
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var showOnboarding = OnboardingStore.shouldShow()
    @State private var showAttribution = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        setupLogCapture()
        log("app: 3105 launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if licenseSession.isAuthorized {
                        ContentView()
                            .environmentObject(appState)
                            .environmentObject(patchDraftCoordinator)
                            .environmentObject(fileOperationCoordinator)
                            .environmentObject(patchStore)
                            .environmentObject(repositoryStore)
                            .environmentObject(licenseSession)
                            .environment(\.appLanguage, language)
                            .environment(\.locale, language.locale)
                            .opacity(showOnboarding ? 0 : 1)
                            .allowsHitTesting(!showOnboarding)
                    } else {
                        LicenseLoginView()
                            .environmentObject(licenseSession)
                            .environment(\.appLanguage, language)
                            .environment(\.locale, language.locale)
                    }
                }

                if showOnboarding {
                    OnboardingView {
                        OnboardingStore.markCompleted()
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                            showOnboarding = false
                        }
                        appState.detectSupport()
                    }
                    .environment(\.appLanguage, language)
                    .environment(\.locale, language.locale)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.98))
                    )
                    .zIndex(1)
                }
            }
            .displayIdentityAttribution(isPresented: $showAttribution, enabled: !showOnboarding)
            .sheet(isPresented: $showAttribution) {
                DisplayAttributionSheet()
            }
            .onAppear {
                licenseSession.restore()
                if !showOnboarding && licenseSession.isAuthorized {
                    appState.detectSupport()
                }
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                licenseSession.revalidateIfNeeded()
                if !showOnboarding && licenseSession.isAuthorized { appState.detectSupport() }
            }
            .onChange(of: licenseSession.isAuthorized) { authorized in
                if authorized && !showOnboarding { appState.detectSupport() }
            }
            .onOpenURL { url in
                patchDraftCoordinator.presentImport(url)
            }
        }
    }
}

@MainActor
final class LicenseSession: ObservableObject {
    @Published private(set) var isAuthorized = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var activeKey = ""
    @Published private(set) var activatedAt: Date?
    @Published private(set) var expiresAt: Date?

    private let endpoint = URL(string: "https://painel-dono-external-ios.vercel.app/api/license/activate")!
    private let keychainService = "com.apple.mobile.MobileHouseArrest.license-session"
    private var lastValidation = Date.distantPast

    func restore() {
        guard !isLoading, let key = read("license-key"), let device = read("installation-id") else { return }
        activeKey = key
        validate(key: key, deviceID: device, persistKey: false)
    }

    func revalidateIfNeeded() {
        guard Date().timeIntervalSince(lastValidation) > 60,
              let key = read("license-key"), let device = read("installation-id") else { return }
        validate(key: key, deviceID: device, persistKey: false)
    }

    func activate(key: String) {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 160 else {
            errorMessage = "Digite uma key válida."
            return
        }
        let device = read("installation-id") ?? makeInstallationID()
        validate(key: normalized, deviceID: device, persistKey: true)
    }

    func logout() {
        delete("license-key")
        isAuthorized = false
        activeKey = ""
        activatedAt = nil
        expiresAt = nil
        errorMessage = nil
    }

    private func validate(key: String, deviceID: String, persistKey: Bool) {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["key": key, "deviceId": deviceID])

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let payload = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any]
            let serverError = payload?["error"] as? String
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                self.lastValidation = Date()
                guard (200..<300).contains(statusCode), payload?["ok"] as? Bool == true else {
                    self.isAuthorized = false
                    self.activeKey = ""
                    self.activatedAt = nil
                    self.expiresAt = nil
                    self.delete("license-key")
                    self.errorMessage = Self.userMessage(for: serverError, status: statusCode)
                    return
                }
                if persistKey {
                    self.write(key, account: "license-key")
                    self.write(deviceID, account: "installation-id")
                }
                self.activeKey = key
                self.activatedAt = Self.date(from: payload?["activatedAt"])
                self.expiresAt = Self.date(from: payload?["expiresAt"])
                self.isAuthorized = true
                self.errorMessage = nil
            }
        }.resume()
    }

    private func makeInstallationID() -> String {
        let value = "install-" + UUID().uuidString
        write(value, account: "installation-id")
        return value
    }

    private static func userMessage(for code: String?, status: Int) -> String {
        switch code {
        case "KEY_INVÁLIDA": return "Key inválida."
        case "KEY_PAUSADA": return "Esta key está pausada."
        case "KEY_EXPIRADA": return "Esta key expirou."
        case "LIMITE_DE_DISPOSITIVOS": return "Limite de dispositivos atingido."
        case "DISPOSITIVO_BLOQUEADO": return "Este dispositivo está bloqueado."
        case "IP_BLOQUEADO": return "Este IP está bloqueado."
        case "SISTEMA_PAUSADO": return "O sistema está temporariamente pausado."
        default: return status == 0 ? "Não foi possível conectar ao servidor." : "Não foi possível validar a key."
        }
    }

    private static func date(from value: Any?) -> Date? {
        if let milliseconds = value as? Double { return Date(timeIntervalSince1970: milliseconds / 1000) }
        if let milliseconds = value as? Int { return Date(timeIntervalSince1970: Double(milliseconds) / 1000) }
        if let timestamp = value as? [String: Any] {
            if let seconds = timestamp["_seconds"] as? Double { return Date(timeIntervalSince1970: seconds) }
            if let seconds = timestamp["_seconds"] as? Int { return Date(timeIntervalSince1970: Double(seconds)) }
        }
        return nil
    }

    private func write(_ value: String, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: account]
        let data = Data(value.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) != errSecSuccess {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            _ = SecItemAdd(item as CFDictionary, nil)
        }
    }

    private func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(_ account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: account]
        _ = SecItemDelete(query as CFDictionary)
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?
    @Published var kernelExploitRunning = false

    private var autoRunAttempted = false

    var kernelExploitApplicable: Bool {
        KernelExploit.isApplicable(
            major: AppInfo.versionTuple.major,
            minor: AppInfo.versionTuple.minor,
            patch: AppInfo.versionTuple.patch,
            build: AppInfo.osBuild
        )
    }

    var isSupported: Bool { unsupportedMessage == nil }

    func detectSupport() {
        let v = AppInfo.versionTuple
        let supported = ExploitSupportPolicy.isSupported(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-access") {
            exploitStatus = .success(method: "Simulator preview")
        }
#endif

        unsupportedMessage = supported ? nil : "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))"
        if let unsupportedMessage {
            exploitStatus = .unsupported(unsupportedMessage)
            return
        }

        let applicable = KernelExploit.isApplicable(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
        guard applicable else { return }

        refreshKernelExploitStatus()
        maybeAutoRunKernelExploit()
    }

    private func maybeAutoRunKernelExploit() {
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed,
              !autoRunAttempted else { return }
        autoRunAttempted = true
        log("app: starting kernel exploit automatically")
        runKernelExploitIfNeeded()
    }

    private func refreshKernelExploitStatus() {
        guard !kernelExploitRunning else { return }

        // iOS < 26: kernel R/W success persists (no sandbox probe)
        // iOS >= 26: verify full sandbox escape is still active
        if KernelExploit.requiresSandboxEscape {
            if KernelExploit.hasSandboxAccess() {
                if !exploitStatus.isSuccess {
                    exploitStatus = .success(method: "kexploit")
                    log("app: existing sandbox access is still active; skipping kernel exploit")
                }
            } else if exploitStatus.isSuccess {
                exploitStatus = .notStarted
                log("app: sandbox access is no longer active")
            }
        }
    }

    func runKernelExploitIfNeeded() {
        refreshKernelExploitStatus()
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed else { return }
        kernelExploitRunning = true
        exploitStatus = .notStarted
        log("app: running kernel exploit on background...")
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = KernelExploit.run()
            DispatchQueue.main.async {
                self.kernelExploitRunning = false
                if ok {
                    self.exploitStatus = .success(method: "kexploit")
                    if KernelExploit.requiresSandboxEscape {
                        log("app: kernel exploit success — sandbox access verified")
                    } else {
                        log("app: kernel exploit success — kernel access active")
                    }
                } else {
                    self.exploitStatus = .failed(method: "kexploit", code: -1)
                    log("app: kernel exploit failed — relaunch the app before retrying")
                }
            }
        }
    }
}
