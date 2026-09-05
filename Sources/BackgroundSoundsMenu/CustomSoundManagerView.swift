import SwiftUI

struct CustomSoundManagerView: View {
    @ObservedObject var store: BackgroundSoundsStore
    let onClose: () -> Void
    @State private var newFolderName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            layerVolumeControl
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
    }

    private var layerVolumeControl: some View {
        HStack(spacing: 12) {
            Label("Second layer", systemImage: "square.stack.3d.up.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.secondaryLayerAccent)
                .frame(width: 112, alignment: .leading)
                .help("Layer volume relative to the master")

            Slider(
                value: Binding(
                    get: { store.layerVolume },
                    set: { store.layerVolumeChanged($0) }
                ),
                in: 0...1
            )
            .tint(Color.secondaryLayerAccent)

            Text("%\(Int(store.layerVolume * 100))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)

        }
        .padding(12)
        .glassEffect(
            .clear.tint(Color.secondaryLayerAccent.opacity(0.06)),
            in: .rect(cornerRadius: 12)
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .glassEffect(.clear.interactive(), in: .circle)
            .help("Back to controls")

            Text("Custom Sounds")
                .font(.headline)

            Spacer()

            Button(action: store.addCustomSound) {
                Image(systemName: "plus")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
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
                        Label(symbol == sound.symbol ? "Selected" : symbol, systemImage: symbol)
                    }
                }
            } label: {
                Image(systemName: sound.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .menuStyle(.borderlessButton)
            .glassEffect(.clear.interactive(), in: .circle)
            .help("Change icon")

            VStack(alignment: .leading, spacing: 2) {
                Text(sound.name)
                    .lineLimit(1)
                Text(durationLabel(sound.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Text(sound.measuredRMSDecibels == nil ? "Normalizing…" : "Matched to system sound level")
                    .font(.caption2)
                    .foregroundStyle(sound.measuredRMSDecibels == nil ? .orange : .secondary)
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
