import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: BackgroundSoundsStore
    @StateObject private var mediaController = MediaControllerStore()
    @State private var isManagingCustomSounds = false
    @State private var mediaSeekPosition: TimeInterval = 0
    @State private var isSeekingMedia = false
    @State private var isHoveringMediaSeek = false
    @State private var artworkAccent: ArtworkAccent?

    var body: some View {
        Group {
            if isManagingCustomSounds {
                CustomSoundManagerView(store: store) {
                    withAnimation(.snappy(duration: 0.22)) {
                        isManagingCustomSounds = false
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                panel
                    .padding(18)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: 360)
        .containerBackground(.clear, for: .window)
        .animation(.snappy(duration: 0.25), value: store.isEnabled)
        .animation(.snappy(duration: 0.22), value: store.isLayerEnabled)
        .animation(.snappy(duration: 0.2), value: store.isVinylNoiseEnabled)
        .onAppear { mediaController.startPolling() }
        .onDisappear { mediaController.stopPolling() }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 16) {
            soundAndPlayback
            shortcutBar
            layerShortcutBar
            volumeControl
            timerControls
            mediaControls

            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            utilityButtons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mediaControls: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: mediaController.openSourceApplication) {
                mediaArtwork
            }
            .buttonStyle(.plain)
            .disabled(mediaController.item.source.applicationBundleIdentifier == nil)
            .help(mediaController.item.source.openApplicationLabel)
            .accessibilityLabel(mediaController.item.source.openApplicationLabel)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mediaController.item.hasContent ? mediaController.item.title : "Spotify / Apple Music")
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(mediaController.item.hasContent ? mediaController.item.artist : "Nothing is playing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 2)

                    Button(action: store.toggleVinylNoise) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(
                                store.isVinylNoiseEnabled
                                    ? AnyShapeStyle(.white)
                                    : AnyShapeStyle(.tertiary)
                            )
                            .frame(width: 24, height: 24)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        store.isVinylNoiseEnabled
                            ? .regular.tint(.brown.opacity(0.72)).interactive()
                            : .clear.interactive(),
                        in: .circle
                    )
                    .accessibilityLabel("Vinyl texture")
                    .accessibilityValue(store.isVinylNoiseEnabled ? "On" : "Off")
                    .help(store.isVinylNoiseEnabled ? "Turn off vinyl texture" : "Add vinyl hiss and crackle")

                    MediaVolumeControl(
                        controller: mediaController,
                        accentColor: mediaAccentColor
                    )
                    .zIndex(10)
                }

                HStack(spacing: 15) {
                    mediaButton("backward.end.fill", help: "Previous", action: mediaController.previous)

                    Button(action: mediaController.togglePlayback) {
                        Image(systemName: mediaController.item.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 34, height: 31)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(mediaController.item.isPlaying ? "Pause" : "Play")

                    mediaButton("forward.end.fill", help: "Next", action: mediaController.next)
                }
                .frame(maxWidth: .infinity)
                .disabled(!mediaController.isAvailable || !mediaController.item.hasContent)

                Slider(
                    value: $mediaSeekPosition,
                    in: 0...max(mediaController.item.duration, 1),
                    onEditingChanged: handleMediaSeeking
                )
                    .controlSize(.mini)
                    .tint(isHoveringMediaSeek ? mediaAccentColor : .white)
                    .disabled(!mediaController.item.hasContent || mediaController.item.duration <= 0)
                    .accessibilityLabel("Playback position")
                    .accessibilityValue(mediaTimeLabel(displayedMediaPosition))
                    .onHover { isHoveringMediaSeek = $0 }
                    .animation(.easeOut(duration: 0.16), value: isHoveringMediaSeek)

                HStack {
                    Text(mediaTimeLabel(displayedMediaPosition))
                    Spacer()
                    Text("−\(mediaTimeLabel(max(mediaController.item.duration - displayedMediaPosition, 0)))")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            syncMediaSeekPosition(with: mediaController.item)
            store.setVinylMusicVolume(mediaController.item.volume)
        }
        .onChange(of: mediaController.item) { _, item in
            syncMediaSeekPosition(with: item)
            store.setVinylMusicVolume(item.volume)
        }
        .task(id: mediaController.item.artworkURL) {
            guard let artworkURL = mediaController.item.artworkURL else {
                artworkAccent = nil
                return
            }
            artworkAccent = await ArtworkColorExtractor.accent(from: artworkURL)
        }
    }

    private var mediaArtwork: some View {
        Group {
            if let artworkURL = mediaController.item.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        mediaArtworkPlaceholder
                    }
                }
            } else {
                mediaArtworkPlaceholder
            }
        }
        .frame(width: 86, height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .scaleEffect(mediaController.item.isPlaying ? 1 : 0.78)
        .saturation(mediaController.item.isPlaying ? 1 : 0.08)
        .opacity(mediaController.item.isPlaying ? 1 : 0.58)
        .animation(
            .spring(response: 0.48, dampingFraction: 0.82),
            value: mediaController.item.isPlaying
        )
    }

    private var mediaArtworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(.quaternary)
            Image(systemName: "music.note")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func mediaButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 31, height: 31)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func mediaTimeLabel(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var displayedMediaPosition: TimeInterval {
        isSeekingMedia ? mediaSeekPosition : mediaController.item.elapsedTime
    }

    private var mediaAccentColor: Color {
        guard let artworkAccent else { return .white }
        let readableAccent = artworkAccent.lifted(toMinimumLuminance: 0.42)
        return Color(
            red: readableAccent.red,
            green: readableAccent.green,
            blue: readableAccent.blue
        )
    }

    private func handleMediaSeeking(_ isEditing: Bool) {
        isSeekingMedia = isEditing
        if !isEditing {
            mediaController.seek(to: mediaSeekPosition)
        }
    }

    private func syncMediaSeekPosition(with item: NowPlayingItem) {
        guard !isSeekingMedia else { return }
        mediaSeekPosition = item.clampedPosition(item.elapsedTime)
    }

    private var layerShortcutBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { index in
                    let sound = store.layerSound(at: index)
                    let isActive = store.isLayerActive(at: index)

                    Button {
                        store.toggleLayer(at: index)
                    } label: {
                        Image(systemName: sound?.symbol ?? "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(
                                isActive
                                    ? Color.white
                                    : Color.secondaryLayerAccent.opacity(0.72)
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        isActive
                            ? .regular.tint(Color.secondaryLayerAccent.opacity(0.34)).interactive()
                            : .clear.tint(Color.secondaryLayerAccent.opacity(0.035)).interactive(),
                        in: .capsule
                    )
                    .contextMenu {
                        Text("Change second layer")
                        Divider()
                        layerSoundMenuItems(for: index)
                        if sound != nil {
                            Divider()
                            Button("Clear Shortcut", role: .destructive) {
                                store.clearLayerShortcut(at: index)
                            }
                        }
                    }
                    .help(sound.map { "Second layer: \($0.name) • Right-click to change" } ?? "Add a sound to the second layer")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var shortcutBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Array(store.shortcuts.enumerated()), id: \.offset) { index, reference in
                    let isActive = store.isSelected(reference) && store.isEnabled

                    Button {
                        store.activatePrimary(reference)
                    } label: {
                        Image(systemName: store.symbol(for: reference))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isActive ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        isActive
                            ? .regular.tint(.blue.opacity(0.62)).interactive()
                            : .clear.interactive(),
                        in: .capsule
                    )
                    .contextMenu {
                        Text("Change shortcut")
                        Divider()
                        ForEach(BackgroundSound.all) { replacement in
                            Button {
                                store.replaceShortcut(at: index, with: .system(replacement.group))
                            } label: {
                                Label(replacement.title, systemImage: replacement.symbol)
                            }
                        }
                        customShortcutMenuItems(for: index)
                    }
                    .help("\(store.title(for: reference)) • Click to play/pause • Right-click to change")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var soundAndPlayback: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(BackgroundSound.all) { sound in
                    Button {
                        store.activatePrimary(.system(sound.group))
                    } label: {
                        Label(
                            sound.title,
                            systemImage: !store.isCustomSelected && sound.group == store.selectedGroup ? "checkmark" : sound.symbol
                        )
                    }
                }

                Divider()

                customSoundMenuItems

                Button(action: store.addCustomSound) {
                    Label("Add Custom Sound…", systemImage: "plus.circle")
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.blue.gradient)
                            .frame(width: 38, height: 38)
                        Image(systemName: store.selectedSymbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative, isActive: store.isEnabled)
                    }

                    Text(store.selectedTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            if store.timerEnd != nil {
                Text(store.remainingLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    isManagingCustomSounds = true
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.clear.interactive(), in: .circle)
            .help("Manage custom sounds")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func layerSoundMenuItems(for index: Int) -> some View {
        ForEach(store.customFolders) { folder in
            let sounds = store.customSounds(in: folder.id)
            if !sounds.isEmpty {
                Menu(folder.name) {
                    ForEach(sounds) { sound in
                        Button {
                            store.replaceLayerShortcut(at: index, with: sound.id)
                        } label: {
                            Label(sound.name, systemImage: sound.symbol)
                        }
                    }
                }
            }
        }

        let unfiled = store.customSounds(in: nil)
        if !unfiled.isEmpty {
            Menu("Unfiled") {
                ForEach(unfiled) { sound in
                    Button {
                        store.replaceLayerShortcut(at: index, with: sound.id)
                    } label: {
                        Label(sound.name, systemImage: sound.symbol)
                    }
                }
            }
        }

        if store.customSounds.isEmpty {
            Button(action: store.addCustomSound) {
                Label("Add Custom Sound…", systemImage: "plus.circle")
            }
        }
    }


    @ViewBuilder
    private var customSoundMenuItems: some View {
        ForEach(store.customFolders) { folder in
            let sounds = store.customSounds(in: folder.id)
            if !sounds.isEmpty {
                Menu(folder.name) {
                    ForEach(sounds) { sound in
                        customSoundButton(sound)
                    }
                }
            }
        }

        let unfiled = store.customSounds(in: nil)
        if !unfiled.isEmpty {
            Menu("Unfiled") {
                ForEach(unfiled) { sound in
                    customSoundButton(sound)
                }
            }
        }
    }

    @ViewBuilder
    private func customShortcutMenuItems(for index: Int) -> some View {
        if !store.customSounds.isEmpty {
            Divider()
            Text("Custom Sounds")

            ForEach(store.customFolders) { folder in
                let sounds = store.customSounds(in: folder.id)
                if !sounds.isEmpty {
                    Menu(folder.name) {
                        ForEach(sounds) { sound in
                            Button {
                                store.replaceShortcut(at: index, with: .custom(sound.id))
                            } label: {
                                Label(sound.name, systemImage: sound.symbol)
                            }
                        }
                    }
                }
            }

            let unfiled = store.customSounds(in: nil)
            if !unfiled.isEmpty {
                Menu("Unfiled") {
                    ForEach(unfiled) { sound in
                        Button {
                            store.replaceShortcut(at: index, with: .custom(sound.id))
                        } label: {
                            Label(sound.name, systemImage: sound.symbol)
                        }
                    }
                }
            }
        }
    }

    private func customSoundButton(_ sound: CustomSound) -> some View {
        Button {
            store.activatePrimary(.custom(sound.id))
        } label: {
            Label(
                sound.name,
                systemImage: store.selectedCustomID == sound.id ? "checkmark" : sound.symbol
            )
        }
    }

    private var volumeControl: some View {
        VStack(spacing: 8) {
            if store.isLayerEnabled {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.wave.1.fill")
                        .foregroundStyle(Color.secondaryLayerAccent)
                        .frame(width: 18)

                    Slider(
                        value: Binding(
                            get: { store.layerVolume },
                            set: { store.layerVolumeChanged($0) }
                        ),
                        in: 0...1
                    )
                    .tint(Color.secondaryLayerAccent)
                    .help("Layer volume relative to the master")

                    Text("%\(Int(store.layerVolume * 100))")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(Color.secondaryLayerAccent)
                        .frame(width: 34, alignment: .trailing)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Slider(
                    value: Binding(
                        get: { store.volume },
                        set: { store.volumeChanged($0) }
                    ),
                    in: 0...1,
                    onEditingChanged: store.volumeEditingChanged
                )
                .help("Master volume • controls all layers")

                Text("%\(Int(store.volume * 100))")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }

    private var timerControls: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    if store.timerEnd != nil { store.cancelTimer() }
                } label: {
                    Image(systemName: store.timerEnd == nil ? "timer" : "xmark.circle.fill")
                        .foregroundStyle(store.timerEnd == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                        .frame(width: 18, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.timerEnd == nil)
                .help(store.timerEnd == nil ? "Sleep timer" : "Cancel timer")

                ForEach(TimerPreset.allCases) { preset in
                    let isActive = store.activeTimerMinutes == preset.rawValue
                    Button {
                        store.startTimer(minutes: preset.rawValue)
                    } label: {
                        Text(preset.label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(isActive ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .contentShape(Capsule())
                    }
                        .buttonStyle(.plain)
                        .glassEffect(
                            isActive
                                ? .regular.tint(.blue.opacity(0.68)).interactive()
                                : .clear.interactive(),
                            in: .capsule
                        )
                        .help("\(preset.label) start timer")
                }
            }
        }
    }

    private var utilityButtons: some View {
        HStack(spacing: 14) {
            Button(action: store.openAccessibilitySettings) {
                Image(systemName: "accessibility")
            }
            .buttonStyle(.plain)
            .help("Accessibility Settings")

            Button(action: store.quit) {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.tertiary)
        .padding(.leading, 2)
    }
}

struct MediaVolumeHoverState: Equatable {
    private(set) var isPresented = false
    private(set) var isButtonHovered = false
    private(set) var isPopoverHovered = false
    private(set) var isEditing = false

    mutating func buttonHoverChanged(_ isHovered: Bool) {
        isButtonHovered = isHovered
        if isHovered { isPresented = true }
    }

    mutating func popoverHoverChanged(_ isHovered: Bool) {
        isPopoverHovered = isHovered
        if isHovered { isPresented = true }
    }

    mutating func editingChanged(_ editing: Bool) {
        isEditing = editing
        if editing { isPresented = true }
    }

    mutating func dismissIfIdle() {
        if !isButtonHovered, !isPopoverHovered, !isEditing {
            isPresented = false
        }
    }

    mutating func dismiss() {
        isPresented = false
        isButtonHovered = false
        isPopoverHovered = false
        isEditing = false
    }
}

private struct MediaVolumeControl: View {
    @ObservedObject var controller: MediaControllerStore
    let accentColor: Color
    @State private var hoverState = MediaVolumeHoverState()
    @State private var volumeBeforeMute = 0.7
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        Button(action: toggleMute) {
            Image(systemName: volumeSymbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(controller.item.volume > 0.001 ? "Mute" : "Unmute")
        .onHover(perform: buttonHoverChanged)
        .popover(
            isPresented: Binding(
                get: { hoverState.isPresented },
                set: { isPresented in
                    if !isPresented { hoverState.dismiss() }
                }
            ),
            arrowEdge: .top
        ) {
            HStack(spacing: 7) {
                Slider(
                    value: Binding(
                        get: { controller.item.volume },
                        set: { controller.setVolume($0) }
                    ),
                    in: 0...1,
                    onEditingChanged: volumeEditingChanged
                )
                .controlSize(.mini)
                .tint(accentColor)
                .frame(width: 96)
                .accessibilityLabel("Music volume")

                Text("%\(Int(controller.item.volume * 100))")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .onHover(perform: popoverHoverChanged)
        }
    }

    private var volumeSymbol: String {
        switch controller.item.volume {
        case ...0.001: return "speaker.slash.fill"
        case ..<0.5: return "speaker.wave.1.fill"
        default: return "speaker.wave.2.fill"
        }
    }

    private func toggleMute() {
        if controller.item.volume > 0.001 {
            volumeBeforeMute = controller.item.volume
            controller.setVolume(0)
        } else {
            controller.setVolume(max(volumeBeforeMute, 0.35))
        }
    }

    private func buttonHoverChanged(_ isHovering: Bool) {
        hideTask?.cancel()
        hoverState.buttonHoverChanged(isHovering)
        if !isHovering { scheduleHide() }
    }

    private func popoverHoverChanged(_ isHovering: Bool) {
        hideTask?.cancel()
        hoverState.popoverHoverChanged(isHovering)
        if !isHovering { scheduleHide() }
    }

    private func volumeEditingChanged(_ isEditing: Bool) {
        hoverState.editingChanged(isEditing)
        controller.volumeEditingChanged(isEditing)
        if !isEditing { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled else { return }
            hoverState.dismissIfIdle()
        }
    }
}
