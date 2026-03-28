import SwiftUI
import Theme

/// Settings view with theme picker, font settings, and preferences.
public struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("terminalFontFamily") private var fontFamily: String = "MesloLGS Nerd Font"
    @AppStorage("terminalFontSize") private var fontSize: Double = 13

    public init() {}

    public var body: some View {
        TabView {
            appearanceSettings
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            fontSettings
                .tabItem { Label("Font", systemImage: "textformat") }

            generalSettings
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 500, height: 400)
    }

    // MARK: - Appearance

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
                    Text("Theme switches automatically with system appearance")
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
            HStack(spacing: 4) {
                Circle().fill(theme.chrome.background).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.secondary.opacity(0.3), lineWidth: 0.5))
                Circle().fill(theme.chrome.accent).frame(width: 12, height: 12)
                Circle().fill(theme.chrome.green).frame(width: 12, height: 12)
                Circle().fill(theme.chrome.red).frame(width: 12, height: 12)
            }

            Text(theme.name)

            Spacer()

            if themeManager.selectedThemeID == theme.id {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            themeManager.selectTheme(theme)
        }
    }

    // MARK: - Font

    private var fontSettings: some View {
        Form {
            Section("Terminal Font") {
                Picker("Font Family", selection: $fontFamily) {
                    ForEach(availableMonoFonts(), id: \.self) { name in
                        Text(name)
                            .font(.system(size: 12, design: .monospaced))
                            .tag(name)
                    }
                }

                HStack {
                    Text("Size")
                    Slider(value: $fontSize, in: 9...24, step: 1)
                    Text("\(Int(fontSize))pt")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }

            Section("Preview") {
                let previewFont = NSFont(name: fontFamily, size: CGFloat(fontSize))
                    ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)

                Text("$ claude --help\n  ~/code/runway on  master [!3]\n❯ ls -la  total 42")
                    .font(Font(previewFont))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(themeManager.currentTheme.chrome.background)
                    .foregroundColor(themeManager.currentTheme.chrome.text)
                    .cornerRadius(6)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// List monospaced fonts available on the system, prioritizing Nerd Fonts.
    private func availableMonoFonts() -> [String] {
        let allFamilies = NSFontManager.shared.availableFontFamilies

        var nerdFonts: [String] = []
        var otherMono: [String] = []

        for family in allFamilies.sorted() {
            if family.contains("Nerd Font") {
                nerdFonts.append(family)
            } else if isMonospaced(family) {
                otherMono.append(family)
            }
        }

        return nerdFonts + ["---"] + otherMono
    }

    private func isMonospaced(_ family: String) -> Bool {
        guard let font = NSFont(name: family, size: 12) else { return false }
        let traits = NSFontManager.shared.traits(of: font)
        return traits.contains(.fixedPitchFontMask)
            || family.lowercased().contains("mono")
            || family.lowercased().contains("courier")
            || family.lowercased().contains("menlo")
            || family.lowercased().contains("consolas")
            || family.lowercased().contains("code")
    }

    // MARK: - General

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
