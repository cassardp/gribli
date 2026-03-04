import SwiftUI

private extension View {
    @ViewBuilder
    func optionallyFocused<V: Hashable>(_ binding: FocusState<V>.Binding?, equals value: V) -> some View {
        if let binding {
            self.focused(binding, equals: value)
        } else {
            self
        }
    }
}

struct LeaderboardView: View {
    @Binding var playerName: String
    @Binding var playerLink: String
    var highlightPlayerName: String?
    var onSave: (() async -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var entries: [ScoreEntry] = []
    @State private var isLoading = true
    @State private var selectedTab: Int
    @State private var isSaving = false
    @State private var savedName = ""
    @State private var savedLink = ""
    @State private var nameTaken = false
    @State private var showScores = false
    private enum Field { case name, link }
    @FocusState private var focusedField: Field?

    private var bgColor: Color { Palette.background(for: colorScheme) }
    private var textColor: Color { Palette.text(for: colorScheme) }
    private var bestScore: Int { UserDefaults.standard.integer(forKey: "bestScore") }

    init(playerName: Binding<String>, playerLink: Binding<String>, startTab: Int = 0, highlightPlayerName: String? = nil, onSave: (() async -> Void)? = nil) {
        _playerName = playerName
        _playerLink = playerLink
        _selectedTab = State(initialValue: startTab)
        self.highlightPlayerName = highlightPlayerName
        self.onSave = onSave
    }

    private let tabIcons = [["star", "star"], ["signature", "signature"], ["info", "info"]]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 32) {
                ForEach(0..<3) { i in
                    Button {
                        withAnimation { selectedTab = i }
                    } label: {
                        Image(systemName: tabIcons[i][selectedTab == i ? 1 : 0])
                            .font(.system(size: i == 0 ? 24 : 26))
                            .foregroundStyle(textColor.opacity(selectedTab == i ? 1 : 0.2))
                            .animation(.easeInOut(duration: 0.2), value: selectedTab)
                    }
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 26)

            TabView(selection: $selectedTab) {
                scoresPage.tag(0)
                profilePage.tag(1)
                infoPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)
            .onChange(of: selectedTab) { focusedField = nil }
        }
        .background(bgColor.ignoresSafeArea())
        .fontDesign(.rounded)
        .task {
            savedName = playerName
            savedLink = playerLink
            await loadEntries()
            isLoading = false
            withAnimation(.easeOut(duration: 0.5)) {
                showScores = true
            }
        }
    }

    // MARK: - Scores

    private var scoresPage: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                Text("No scores yet")
                    .foregroundStyle(textColor.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Text("All Stars")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(textColor)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 12)
                                .padding(.bottom, 20)
                                .offset(y: showScores ? 0 : 12)
                                .opacity(showScores ? 1 : 0)
                                .animation(.easeOut(duration: 0.4).delay(0.05), value: showScores)

                            ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                                let isHighlighted = highlightPlayerName != nil && entry.playerName == highlightPlayerName
                                scoreRow(rank: offset + 1, entry: entry, isHighlighted: isHighlighted)
                                    .id(entry.id)
                                    .offset(y: showScores ? 0 : 12)
                                    .opacity(showScores ? 1 : 0)
                                    .animation(.easeOut(duration: 0.4).delay(0.1 + Double(offset) * 0.05), value: showScores)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: showScores) {
                        if showScores, let name = highlightPlayerName,
                           let match = entries.first(where: { $0.playerName == name }) {
                            let delay = 0.1 + Double(entries.firstIndex(where: { $0.id == match.id })!) * 0.05 + 0.3
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                withAnimation(.easeOut(duration: 0.4)) {
                                    proxy.scrollTo(match.id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func scoreRow(rank: Int, entry: ScoreEntry, isHighlighted: Bool = false) -> some View {
        let hasLink = entry.link != nil && !entry.link!.isEmpty
        return linkWrapper(entry) {
            HStack(spacing: 12) {
                Circle()
                    .fill(isHighlighted ? Palette.orangeRed : (hasLink ? Palette.olive : textColor.opacity(0.12)))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text("\(rank)")
                            .font(.system(size: 16, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(isHighlighted ? Palette.cream : (hasLink ? Palette.cream : textColor.opacity(0.5)))
                    )

                HStack(spacing: 4) {
                    Text(entry.playerName)
                    if hasLink {
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                    }
                }
                .font(.body.weight(.medium))
                .foregroundStyle(textColor)
                .lineLimit(1)

                Spacer()

                Text(verbatim: "\(entry.score)")
                    .font(.body.monospacedDigit().weight(.medium))
                    .foregroundStyle(isHighlighted ? textColor : textColor.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background((isHighlighted ? Palette.orangeRed.opacity(0.12) : textColor.opacity(0.06)), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func linkWrapper<Content: View>(_ entry: ScoreEntry, @ViewBuilder content: () -> Content) -> some View {
        if let link = entry.link, !link.isEmpty, let url = URL(string: link) {
            Link(destination: url) { content() }
        } else {
            content()
        }
    }

    // MARK: - Profile

    private var profileHasChanges: Bool {
        playerName != savedName || playerLink != savedLink
    }

    private var profilePage: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Profile")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                Text("Displayed on All Stars.")
                    .font(.body)
                    .foregroundStyle(textColor.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                VStack(spacing: 10) {
                    profileField(icon: "person.fill", text: $playerName, placeholder: "Username", capitalization: .words, status: nameTaken ? .error : nil, highlighted: !playerLink.isEmpty, focusBinding: $focusedField, focusValue: .name)
                        .onChange(of: playerName) { nameTaken = false }
                        .overlay(alignment: .trailing) {
                            if focusedField != .name && bestScore > 0 {
                                Text(verbatim: "\(bestScore)")
                                    .font(.body.monospacedDigit().weight(.medium))
                                    .foregroundStyle(textColor.opacity(0.5))
                                    .padding(.trailing, 14)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeOut(duration: 0.2), value: focusedField)
                    profileField(icon: "link", text: $playerLink, placeholder: "Link (optional)", keyboard: .URL, highlighted: false, focusBinding: $focusedField, focusValue: .link)
                }
                .padding(.horizontal, 20)

                if profileHasChanges {
                    Button {
                        guard !playerName.isEmpty else { return }
                        isSaving = true
                        nameTaken = false
                        Task {
                            do {
                                await onSave?()
                                try await API.updateProfile(
                                    playerName: playerName,
                                    link: playerLink.isEmpty ? nil : playerLink,
                                    deviceId: deviceId
                                )
                                await loadEntries()
                                savedName = playerName
                                savedLink = playerLink
                                selectedTab = 0
                            } catch APIError.nameTaken {
                                nameTaken = true
                            } catch {}
                            isSaving = false
                        }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView()
                                    .tint(bgColor)
                            } else {
                                Text("Save")
                            }
                        }
                        .font(.body.weight(.medium))
                        .foregroundStyle(bgColor)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(playerName.isEmpty ? textColor.opacity(0.15) : textColor, in: Capsule())
                    }
                    .disabled(playerName.isEmpty || isSaving)
                    .padding(.top, 36)
                }

            }
        }
    }

    enum FieldStatus { case error }

    private func profileField(icon: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default, capitalization: TextInputAutocapitalization = .never, status: FieldStatus? = nil, highlighted: Bool? = nil, focusBinding: FocusState<Field?>.Binding? = nil, focusValue: Field? = nil) -> some View {
        let filled = highlighted ?? !text.wrappedValue.isEmpty
        let circleColor: Color = status == .error ? Palette.orangeRed : (filled ? Palette.olive : textColor.opacity(0.12))
        let iconColor: Color = status == .error ? Palette.cream : (filled ? Palette.cream : textColor.opacity(0.5))
        return HStack(spacing: 12) {
            Circle()
                .fill(circleColor)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: status == .error ? "xmark" : icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(iconColor)
                )

            TextField(placeholder, text: text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(capitalization)
                .keyboardType(keyboard)
                .font(.body.weight(.medium))
                .foregroundStyle(textColor)
                .optionallyFocused(focusBinding, equals: focusValue ?? .name)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background((status == .error ? Palette.orangeRed.opacity(0.08) : textColor.opacity(0.06)), in: RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.2), value: status == .error)
        .animation(.easeOut(duration: 0.2), value: filled)
    }

    // MARK: - Info

    private var infoPage: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 28) {
                    Text("About Gribli")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(textColor)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, -8)

                    Text("Gribli is a minimalist match-3 puzzle game (free, open-source, no ads, no tracking, no in-app purchases, forever). Swap, match, and chase the high score. Add a link to your profile to showcase your project on the leaderboard.")
                        .font(.body)
                        .foregroundStyle(textColor.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity)

                    Spacer()

                    VStack(spacing: 10) {
                        infoLink(
                            icon: "at",
                            label: "Follow me on Twitter",
                            url: "https://x.com/patricecassard"
                        )
                        infoLink(
                            icon: "pin.fill",
                            label: "Try Pinpin (my other app)",
                            url: "https://apps.apple.com/fr/app/pinpin-mobile/id6748907154"
                        )
                        infoLink(
                            icon: "cup.and.saucer.fill",
                            label: "Buy me a coffee",
                            url: "https://buymeacoffee.com/patricecassard"
                        )
                    }

                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")")
                        .font(.footnote)
                        .foregroundStyle(textColor.opacity(0.3))
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
                .frame(minHeight: geo.size.height)
            }
        }
    }

    private func infoLink(icon: String, label: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                Circle()
                    .fill(textColor)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(bgColor)
                    )

                Text(label)
                    .font(.body.weight(.medium))

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11))
                    .opacity(0.4)
            }
            .foregroundStyle(textColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(textColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func loadEntries() async {
        entries = (try? await API.loadScores()) ?? []
    }
}
