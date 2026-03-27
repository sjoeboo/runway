import SwiftUI
import Theme

/// Settings view with theme picker and preferences.
public struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager

    public init() {}

    public var body: some View {
        @Bindable var tm = themeManager

        TabView {
            appearanceSettings
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            generalSettings
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 450, height: 350)
    }

    private var appearanceSettings: some View {
        Form {
            Section("Theme Mode") {
                Picker("Mode", selection: Binding(
                    get: { themeManager.themeMode },
                    set: { themeManager.themeMode = $0 }
                )) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if themeManager.themeMode == .system {
                    Text("Theme will switch automatically with system appearance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Dark Themes") {
                ForEach(themeManager.darkThemes, id: \.id) { theme in
                    themeRow(theme)
                }
            }

            Section("Light Themes") {
                ForEach(themeManager.lightThemes, id: \.id) { theme in
                    themeRow(theme)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func themeRow(_ theme: AppTheme) -> some View {
        HStack {
            // Color preview circles
            HStack(spacing: 4) {
                Circle().fill(theme.chrome.background).frame(width: 12, height: 12)
                Circle().fill(theme.chrome.accent).frame(width: 12, height: 12)
                Circle().fill(theme.chrome.green).frame(width: 12, height: 12)
                Circle().fill(theme.chrome.red).frame(width: 12, height: 12)
            }

            Text(theme.name)

            Spacer()

            if themeManager.selectedThemeID == theme.id {
                Image(systemName: "checkmark")
                    .foregroundColor(themeManager.currentTheme.chrome.accent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            themeManager.selectTheme(theme)
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Hooks") {
                LabeledContent("Hook Server Port") {
                    Text("47437")
                        .foregroundColor(.secondary)
                }
                LabeledContent("Status") {
                    Text("Running")
                        .foregroundColor(.green)
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text("0.1.0")
                        .foregroundColor(.secondary)
                }
                LabeledContent("Config Directory") {
                    Text("~/.runway/")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
