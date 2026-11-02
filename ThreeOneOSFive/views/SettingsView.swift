import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseSession: LicenseSession
    @AppStorage(VisualPreferences.animatedColorsKey) private var animatedColorsEnabled = true
    @AppStorage(VisualPreferences.appearanceKey) private var appearanceRawValue = VisualAppearance.system.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Aparência") {
                    Toggle("Cores animadas", isOn: $animatedColorsEnabled)
                    Picker("Tema", selection: $appearanceRawValue) {
                        ForEach(VisualAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance.rawValue)
                        }
                    }
                }

                Section("Licença") {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("KEY USADA")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(licenseSession.activeKey.isEmpty ? "Não disponível" : licenseSession.activeKey)
                                .font(.footnote.monospaced().weight(.semibold))
                                .textSelection(.enabled)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = licenseSession.activeKey
                        } label: {
                            Label("COPIAR", systemImage: "doc.on.doc.fill")
                                .font(.caption.weight(.bold))
                        }
                        .disabled(licenseSession.activeKey.isEmpty)
                    }
                    LabeledContent("Data e hora de uso", value: formatted(licenseSession.activatedAt))
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        LabeledContent("Tempo restante", value: remaining(from: context.date))
                    }
                }

                Section("Acesso") {
                    Button(role: .destructive) {
                        licenseSession.logout()
                        dismiss()
                    } label: {
                        Label("Sair da key", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("Device") {
                    LabeledContent("Modelo", value: AppInfo.displayMachineName)
                    LabeledContent("Sistema", value: "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))")
                    LabeledContent("Compatibilidade", value: appState.isSupported ? "Suportado" : "Não suportado")
                }
            }
            .tint(AppTheme.accent)
            .animatedTextAppearance()
            .navigationTitle("CONFIG")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("FECHAR") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "Aguardando primeira ativação" }
        return date.formatted(date: .numeric, time: .standard)
    }

    private func remaining(from now: Date) -> String {
        guard let expires = licenseSession.expiresAt else { return "Indisponível" }
        let seconds = max(0, Int(expires.timeIntervalSince(now)))
        return "\(seconds / 86_400)d \((seconds % 86_400) / 3_600)h \((seconds % 3_600) / 60)m \(seconds % 60)s"
    }
}
