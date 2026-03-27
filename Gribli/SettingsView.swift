import SwiftUI

struct SettingsView: View {
    @Environment(PaletteStore.self) private var palette
    @Environment(\.colorScheme) private var colorScheme

    private var textColor: Color { Palette.text(for: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                // MARK: - Appearance

                sectionHeader("Appearance")

                HStack(spacing: 8) {
                    ForEach(PaletteStore.AppearanceMode.allCases, id: \.self) { mode in
                        Button {
                            palette.appearanceMode = mode
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: mode == .dark ? "moon.fill" : "sun.max.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(mode.label)
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundStyle(palette.appearanceMode == mode ? Palette.background(for: colorScheme) : textColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(palette.appearanceMode == mode ? textColor : textColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 3)

                // MARK: - Colors

                sectionHeader("Colors")
                    .padding(.top, 24)

                ForEach(PaletteStore.definitions) { def in
                    colorRow(def: def)
                }

                if palette.isCustomized {
                    Button {
                        withAnimation { palette.reset() }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(textColor.opacity(0.12))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(textColor.opacity(0.5))
                                )
                            Text("Reset Colors")
                                .font(.body.weight(.medium))
                                .foregroundStyle(textColor)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(textColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(textColor.opacity(0.5))
            .textCase(.uppercase)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
    }

    private func colorRow(def: PaletteStore.GameColor) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(palette.colors[def.id] ?? def.defaultColor)
                .frame(width: 36, height: 36)

            Text(def.label)
                .font(.body.weight(.medium))
                .foregroundStyle(textColor)

            Spacer()

            ColorPicker("", selection: Binding(
                get: { palette.colors[def.id] ?? def.defaultColor },
                set: {
                    palette.colors[def.id] = $0
                    palette.save()
                }
            ), supportsOpacity: false)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(textColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.vertical, 3)
    }
}
