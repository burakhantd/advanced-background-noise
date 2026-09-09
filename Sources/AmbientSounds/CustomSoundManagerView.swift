import AppKit
import SwiftUI

struct CustomSoundManagerView: View {
    @ObservedObject var store: BackgroundSoundsStore
    let onClose: () -> Void
    @State private var newFolderName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            folderCreator

            if store.customSounds.isEmpty {
                ContentUnavailableView(
                    "No Custom Sounds Yet",
                    systemImage: "waveform.badge.plus",
                    description: Text("Add an audio file, then choose its icon and folder.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(store.customFolders) { folder in
                            let sounds = store.customSounds(in: folder.id)
                            if !sounds.isEmpty {
                                folderSection(folder.name, sounds: sounds)
                            }
                        }

                        let unfiled = store.customSounds(in: nil)
                        if !unfiled.isEmpty {
                            folderSection("Unfiled", sounds: unfiled)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

        }
        .padding(18)
        .frame(height: 440)
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 10) {
                checkForUpdatesButton
                brandLogo
            }
            .padding(.trailing, 18)
            .padding(.bottom, 18)
        }
        .overlay(alignment: .bottomLeading) {
            coffeeLink
                .padding(.leading, 18)
                .padding(.bottom, 18)
        }
    }

    private var checkForUpdatesButton: some View {
        Button(action: { AppUpdater.shared.checkForUpdates() }) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 25, height: 25)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Check for Updates")
        .accessibilityLabel("Check for Updates")
    }

    private var brandLogo: some View {
        Button(action: openBrandWebsite) {
            Group {
                if let logoURL = Bundle.main.url(forResource: "Logo Alpha", withExtension: "png"),
                   let logo = NSImage(contentsOf: logoURL) {
                    Image(nsImage: logo)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 25, height: 25)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open burakhan.studio")
        .accessibilityLabel("Open burakhan.studio")
    }

    private var coffeeLink: some View {
        Button(action: openCoffeeWebsite) {
            HStack(spacing: 6) {
                if let logoURL = Bundle.main.url(forResource: "BuyMeACoffee", withExtension: "png"),
                   let logo = NSImage(contentsOf: logoURL) {
                    Image(nsImage: logo)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "cup.and.saucer.fill")
                        .foregroundStyle(.secondary)
                }

                Text("Buy me a coffee")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(height: 25)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open buymeacoffee.com/burakhanstudio")
        .accessibilityLabel("Buy me a coffee")
    }

    private func openBrandWebsite() {
        guard let url = URL(string: "https://burakhan.studio") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openCoffeeWebsite() {
        guard let url = URL(string: "https://buymeacoffee.com/burakhanstudio") else { return }
        NSWorkspace.shared.open(url)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
                    .glassEffect(.clear.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .help("Back to controls")

            Text("Custom Sounds")
                .font(.headline)

            Spacer()

            Button(action: store.addCustomSound) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glassProminent)
            .clipShape(Circle())
            .help("Add sound")
        }
    }

    private var folderCreator: some View {
        HStack(spacing: 10) {
            TextField("New folder name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addFolder)

            Button(action: addFolder) {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.glass)
            .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !store.customFolders.isEmpty {
                Menu {
                    ForEach(store.customFolders) { folder in
                        Button(role: .destructive) {
                            store.removeFolder(folder)
                        } label: {
                            Label(folder.name, systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "folder.badge.minus")
                }
                .menuStyle(.borderlessButton)
                .help("Delete folder; its sounds move to Unfiled")
            }
        }
    }

    private func folderSection(_ title: String, sounds: [CustomSound]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            ForEach(sounds) { sound in
                soundRow(sound)
            }
        }
    }

    private func soundRow(_ sound: CustomSound) -> some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(BackgroundSoundsStore.customSymbols, id: \.self) { symbol in
                    Button {
                        store.setSymbol(symbol, for: sound.id)
                    } label: {
                        Label(symbol == sound.symbol ? "Selected" : symbolTitle(symbol), systemImage: symbol)
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.quaternary.opacity(0.55))
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.14), lineWidth: 1)
                        }

                    Image(systemName: sound.symbol)
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(width: 44, height: 44)
            }
            .menuStyle(.borderlessButton)
            .help("Change icon")

            VStack(alignment: .leading, spacing: 2) {
                ScrollingTrackName(text: sound.name)
                Text(durationLabel(sound.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Menu {
                Button("Unfiled") {
                    store.setFolder(nil, for: sound.id)
                }
                Divider()
                ForEach(store.customFolders) { folder in
                    Button(folder.name) {
                        store.setFolder(folder.id, for: sound.id)
                    }
                }
            } label: {
                Image(systemName: "folder")
            }
            .menuStyle(.borderlessButton)
            .help(store.folderName(for: sound))

            Button(role: .destructive) {
                store.removeCustomSound(sound)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove custom sound")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private func symbolTitle(_ symbol: String) -> String {
        switch symbol {
        case "waveform": return "Waveform"
        case "water.waves": return "Water waves"
        case "cloud.rain.fill": return "Rain cloud"
        case "drop.fill": return "Drop"
        case "flame.fill": return "Flame"
        case "leaf.fill": return "Leaf"
        case "wind": return "Wind"
        case "moon.stars.fill": return "Moon and stars"
        case "bird.fill": return "Bird"
        case "tree.fill": return "Tree"
        case "mountain.2.fill": return "Mountain"
        case "music.note": return "Music note"
        case "sparkles": return "Sparkles"
        case "heart.fill": return "Heart"
        case "headphones": return "Headphones"
        default:
            return symbol
                .replacingOccurrences(of: ".fill", with: "")
                .replacingOccurrences(of: ".", with: " ")
                .capitalized
        }
    }

    private func addFolder() {
        if store.addFolder(named: newFolderName) {
            newFolderName = ""
        }
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct ScrollingTrackName: View {
    let text: String

    @State private var isHovered = false
    @State private var textWidth: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .fixedSize(horizontal: true, vertical: false)
                .background {
                    GeometryReader { textProxy in
                        Color.clear
                            .onAppear { textWidth = textProxy.size.width }
                            .onChange(of: textProxy.size.width) { _, newWidth in
                                textWidth = newWidth
                            }
                    }
                }
                .offset(x: isHovered ? min(0, proxy.size.width - textWidth) : 0)
                .animation(.easeInOut(duration: 1.25), value: isHovered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .onHover { hovering in
                    isHovered = hovering
                }
        }
        .frame(height: 20)
        .clipped()
    }
}
