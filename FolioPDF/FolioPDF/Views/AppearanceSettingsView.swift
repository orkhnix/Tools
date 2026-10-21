import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppearanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("nightPages") private var nightPages = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { mode in Text(mode.rawValue).tag(mode.rawValue) }
                    }.pickerStyle(.segmented)
                }
                Section {
                    Toggle("Invert PDF colors", isOn: $nightPages)
                } header: { Text("Night reading") } footer: {
                    Text("Inverts text, paper, and image colors in Book mode. Exported PDFs keep their original colors.")
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
    }
}
