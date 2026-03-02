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

    private var bgColor: Color { colorScheme == .dark ? Color(white: 0.1) : .white }
    private var textColor: Color { colorScheme == .dark ? Color(white: 0.85) : Color(white: 0.2) }

    init(playerName: Binding<String>, playerLink: Binding<String>, startTab: Int = 0, onSave: (() async -> Void)? = nil) {
        _playerName = playerName
        _playerLink = playerLink
        _selectedTab = State(initialValue: startTab)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                textTab("Scores", tab: 0)
                textTab("Profile", tab: 1)
                textTab("Info", tab: 2)
            }
            .padding(.top, 28)
            .padding(.bottom, 44)

            Group {
                switch selectedTab {
                case 1: profileContent
                case 2: infoContent
                default: leaderboardContent
                }
            }
        }
        .background(bgColor.ignoresSafeArea())
        .fontDesign(.rounded)
        .task {
            savedName = playerName
            savedLink = playerLink
            await loadEntries()
            isLoading = false
        }
    }

    // MARK: - Navigation

    private func textTab(_ title: String, tab: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
        } label: {
            VStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(selectedTab == tab ? textColor : textColor.opacity(0.2))
                Circle()
                    .fill(selectedTab == tab ? textColor : .clear)
                    .frame(width: 4, height: 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Leaderboard

    private var leaderboardContent: some View {
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
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            leaderboardRow(index: index, entry: entry)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func leaderboardRow(index: Int, entry: ScoreEntry) -> some View {
        HStack(spacing: 12) {
            rankBadge(index + 1)

            playerLabel(entry)
                .font(index == 0 ? .body.weight(.bold) : .body.weight(.medium))
                .lineLimit(1)

            Spacer()

            Text("\(entry.score)")
                .font(index == 0 ? .title3.monospacedDigit().bold() : .body.monospacedDigit().weight(.medium))
                .foregroundStyle(index == 0 ? textColor : textColor.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func rankBadge(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.subheadline.monospacedDigit().bold())
            .foregroundStyle(textColor.opacity(rank == 1 ? 1 : 0.25))
            .frame(width: 24, alignment: .trailing)
    }

    // MARK: - Profile

    private var profileHasChanges: Bool {
        playerName != savedName || playerLink != savedLink
    }

    private var profileContent: some View {
        ScrollView {
            VStack(spacing: 36) {
                VStack(spacing: 24) {
                    profileField("Username", text: $playerName, placeholder: "Enter a name")
                    profileField("Link", text: $playerLink, placeholder: "Optional", keyboard: .URL)
                }
                .padding(.horizontal, 20)

                if profileHasChanges {
                    Button {
                        guard !playerName.isEmpty else { return }
                        isSaving = true
                        Task {
                            await onSave?()
                            _ = try? await API.updateProfile(
                                playerName: playerName,
                                link: playerLink.isEmpty ? nil : playerLink,
                                deviceId: deviceId
                            )
                            await loadEntries()
                            savedName = playerName
                            savedLink = playerLink
                            isSaving = false
                            selectedTab = 0
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
                }

                Text("Visible on the leaderboard")
                    .font(.footnote)
                    .foregroundStyle(textColor.opacity(0.3))
            }
        }
    }

    private func profileField(_ label: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(textColor.opacity(0.4))
            TextField(placeholder, text: text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(keyboard)
                .foregroundStyle(textColor)
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(textColor.opacity(0.1))
                        .frame(height: 1)
                }
        }
    }

    // MARK: - Info

    private var infoContent: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 24) {
                    Text("Gribli is a free, open-source match-3 puzzle game. No ads, no tracking, no in-app purchases — just swap, match, and chase the high score.\n\nBuilt by a \"solo\" indie developer (with me), with SwiftUI, too much coffee, and the help of Claude Code — an overly enthusiastic AI who also picked the name.\n\nAnd guess who wrote this text?")
                        .font(.body)
                        .foregroundStyle(textColor.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("(My human says it's a decent game!)")
                        .font(.body)
                        .foregroundStyle(textColor.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    VStack(spacing: 0) {
                        infoLink("Made by Patrice (& Claude)", url: "https://x.com/patricecassard")
                        infoLink("Source on GitHub", url: "https://github.com/cassardp/gribli")
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

    private func infoLink(_ label: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Text(label)
                    .font(.body)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
            }
            .foregroundStyle(textColor)
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(textColor.opacity(0.1))
                    .frame(height: 1)
            }
        }
    }

    private func loadEntries() async {
        entries = (try? await API.loadScores()) ?? []
    }

    // MARK: - Shared

    @ViewBuilder
    private func playerLabel(_ entry: ScoreEntry) -> some View {
        if let link = entry.link, !link.isEmpty, let url = URL(string: link) {
            Link(destination: url) {
                HStack(spacing: 4) {
                    Text(entry.playerName)
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                }
                .foregroundStyle(textColor)
            }
        } else {
            Text(entry.playerName)
                .foregroundStyle(textColor)
        }
    }
}
