import SwiftUI

struct LeaderboardView: View {
    @Binding var playerName: String
    @Binding var playerLink: String
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

    private var bgColor: Color { colorScheme == .dark ? Color(white: 0.1) : .white }
    private var textColor: Color { colorScheme == .dark ? Color(white: 0.85) : Color(white: 0.2) }

    init(playerName: Binding<String>, playerLink: Binding<String>, startTab: Int = 0, onSave: (() async -> Void)? = nil) {
        _playerName = playerName
        _playerLink = playerLink
        _selectedTab = State(initialValue: startTab)
        self.onSave = onSave
    }

    private let tabIcons = [["trophy", "trophy.fill"], ["person", "person.fill"], ["info.circle", "info.circle.fill"]]

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
            .padding(.bottom, 24)

            TabView(selection: $selectedTab) {
                scoresPage.padding(.top, 12).tag(0)
                profilePage.padding(.top, 12).tag(1)
                infoPage.padding(.top, 12).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)
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

    // MARK: - Helpers

    private var dashedLine: some View {
        Line()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(textColor.opacity(0.12))
            .frame(height: 1)
    }

    private var plainLine: some View {
        Line()
            .stroke(lineWidth: 1)
            .foregroundStyle(textColor.opacity(0.12))
            .frame(height: 1)
    }

    private func initialLetter(_ name: String) -> String {
        String(name.prefix(1)).uppercased()
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
                ScrollView {
                    VStack(spacing: 0) {
                        Text("Top Scores")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(textColor)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 16)
                            .offset(y: showScores ? 0 : 12)
                            .opacity(showScores ? 1 : 0)
                            .animation(.easeOut(duration: 0.4).delay(0.05), value: showScores)
                        if let first = entries.first {
                            championCard(first)
                                .padding(.top, 16)
                                .padding(.bottom, 24)
                                .offset(y: showScores ? 0 : 16)
                                .opacity(showScores ? 1 : 0)
                                .animation(.easeOut(duration: 0.45).delay(0.12), value: showScores)
                        }

                        if entries.count > 1 {
                            HStack(spacing: 12) {
                                plainLine
                                Text("HALL OF FAME")
                                    .font(.system(size: 12, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundStyle(textColor.opacity(0.3))
                                plainLine
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                            .offset(y: showScores ? 0 : 12)
                            .opacity(showScores ? 1 : 0)
                            .animation(.easeOut(duration: 0.4).delay(0.22), value: showScores)
                        }

                        ForEach(Array(entries.dropFirst().enumerated()), id: \.element.id) { offset, entry in
                            restRow(rank: offset + 2, entry: entry)
                                .offset(y: showScores ? 0 : 12)
                                .opacity(showScores ? 1 : 0)
                                .animation(.easeOut(duration: 0.4).delay(0.28 + Double(offset) * 0.05), value: showScores)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func championCard(_ entry: ScoreEntry) -> some View {
        linkWrapper(entry) {
            VStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(textColor)

                HStack(spacing: 4) {
                    Text(entry.playerName)
                    if entry.link != nil && !entry.link!.isEmpty {
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                    }
                }
                .font(.body.weight(.bold))
                .foregroundStyle(textColor)
                .lineLimit(1)

                Text("\(entry.score)")
                    .font(.system(size: 28, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(textColor)
            }
        }
    }

    private func restRow(rank: Int, entry: ScoreEntry) -> some View {
        linkWrapper(entry) {
            HStack(spacing: 12) {
                Circle()
                    .fill(textColor.opacity(0.08))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text("\(rank)")
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(textColor.opacity(0.5))
                    )

                HStack(spacing: 4) {
                    Text(entry.playerName)
                    if entry.link != nil && !entry.link!.isEmpty {
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                    }
                }
                .font(.body.weight(.medium))
                .foregroundStyle(textColor)
                .lineLimit(1)

                Spacer()

                Text("\(entry.score)")
                    .font(.body.monospacedDigit().weight(.medium))
                    .foregroundStyle(textColor.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
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
                    .padding(.bottom, 16)

                Text("Displayed on Top Scores.")
                    .font(.body)
                    .foregroundStyle(textColor.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                VStack(spacing: 10) {
                    profileField(icon: "person.fill", text: $playerName, placeholder: "Username", capitalization: .words, status: nameTaken ? .error : nil)
                        .onChange(of: playerName) { nameTaken = false }
                    profileField(icon: "link", text: $playerLink, placeholder: "Link (optional)", keyboard: .URL)
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

    private func profileField(icon: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default, capitalization: TextInputAutocapitalization = .never, status: FieldStatus? = nil) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(status == .error ? .red.opacity(0.8) : textColor)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: status == .error ? "xmark" : icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(status == .error ? .white : bgColor)
                )

            TextField(placeholder, text: text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(capitalization)
                .keyboardType(keyboard)
                .font(.body.weight(.medium))
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background((status == .error ? Color.red.opacity(0.08) : textColor.opacity(0.06)), in: RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.2), value: status == .error)
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

                    Text("Gribli is a free, open-source match-3 puzzle game. No ads, no tracking, no in-app purchases — just swap, match, and chase the high score.")
                        .font(.body)
                        .foregroundStyle(textColor.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity)

                    Spacer()

                    VStack(spacing: 10) {
                        infoLink(
                            icon: "at",
                            label: "Follow me on X",
                            url: "https://x.com/patricecassard"
                        )
                        infoLink(
                            icon: "pin.fill",
                            label: "Try also Pinpin",
                            url: "https://apps.apple.com/fr/app/pinpin-mobile/id6748907154"
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

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        }
    }
}
