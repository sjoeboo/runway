import Models
import SwiftUI
import Theme

/// Settings view with theme picker, font settings, and preferences.
public struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("terminalFontFamily") private var fontFamily: String = "MesloLGS Nerd Font"
    @AppStorage("terminalFontSize") private var fontSize: Double = 13
    @AppStorage("defaultPermissionMode") private var defaultPermissionMode: PermissionMode = .default

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
                Picker(
                    "Mode",
                    selection: Binding(
                        get: { themeManager.themeMode },
                        set: { themeManager.themeMode = $0 }
                    )
                ) {
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
        let fonts = groupedFonts()
        return Form {
            Section("Terminal Font") {
                Picker("Font Family", selection: $fontFamily) {
                    if !fonts.nerd.isEmpty {
                        Section("Nerd Fonts") {
                            ForEach(fonts.nerd, id: \.self) { name in
                                Text(name).font(.system(size: 12, design: .monospaced)).tag(name)
                            }
                        }
                    }
                    if !fonts.mono.isEmpty {
                        Section("Monospaced") {
                            ForEach(fonts.mono, id: \.self) { name in
                                Text(name).font(.system(size: 12, design: .monospaced)).tag(name)
                            }
                        }
                    }
                    if !fonts.other.isEmpty {
                        Section("All Fonts") {
                            ForEach(fonts.other, id: \.self) { name in
                                Text(name).font(.system(size: 12, design: .monospaced)).tag(name)
                            }
                        }
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
                let previewFont =
                    NSFont(name: fontFamily, size: CGFloat(fontSize))
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

    /// Fonts available on the system, grouped: Nerd Fonts → Monospaced → All others.
    private func groupedFonts() -> (nerd: [String], mono: [String], other: [String]) {
        let allFamilies = NSFontManager.shared.availableFontFamilies

        var nerdFonts: [String] = []
        var monoFonts: [String] = []
        var otherFonts: [String] = []

        for family in allFamilies.sorted() {
            if family.contains("Nerd Font") {
                nerdFonts.append(family)
            } else if isMonospaced(family) {
                monoFonts.append(family)
            } else {
                otherFonts.append(family)
            }
        }

        return (nerdFonts, monoFonts, otherFonts)
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
            Section("Session Defaults") {
                Picker("Default Permission Mode", selection: $defaultPermissionMode) {
                    ForEach(PermissionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if defaultPermissionMode == .bypassAll {
                    Text("New sessions will skip all permission prompts by default")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

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
