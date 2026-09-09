import AppKit
import ApplicationServices

/// Spotify's scripting dictionary does not expose queue or library operations.
/// Read live queue items and favorite states via accessibility without activating or raising its window.
enum SpotifyAccessibility {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func label(_ element: AXUIElement) -> String {
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute] {
            if let text = attribute(element, name) as? String, !text.isEmpty { return text }
        }
        return ""
    }

    static func allLabels(_ element: AXUIElement) -> [String] {
        var results: [String] = []
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute] {
            if let text = attribute(element, name) as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                results.append(text)
            }
        }
        return results
    }

    static func descendants(_ root: AXUIElement, maxCount: Int = 20000) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var pending = [root]
        while let element = pending.popLast(), result.count < maxCount {
            result.append(element)
            let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            pending.append(contentsOf: children.reversed())
        }
        return result
    }

    static func root() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)

        var role: CFTypeRef?
        return AXUIElementCopyAttributeValue(root, kAXRoleAttribute as CFString, &role) == .success ? root : nil
    }

    static func favoriteState(for label: String) -> Bool? {
        let l = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .lowercased()
        guard !l.isEmpty else { return nil }

        // Ignore library navigation / sidebar items
        if l == "your library" || l == "kitaplığın" || l == "kitaplık" ||
           l == "kütüphane" || l == "kütüphanem" ||
           l.contains("collapse your library") || l.contains("expand your library") ||
           l.contains("kitaplığını daralt") || l.contains("kitaplığını genişlet") ||
           l.contains("kitaplığında ara") || l.contains("search in your library") {
            return nil
        }

        // Favorited / Saved (liked = true)
        if l.contains("beğenilen şarkılar'dan kaldır") || l.contains("beğenilen şarkılardan kaldır") ||
           l.contains("beğenilen şarkılar'dan çıkar") || l.contains("beğenilen şarkılardan çıkar") ||
           l.contains("remove from liked songs") || l.contains("remove from your liked songs") ||
           l.contains("remove from your library") || l.contains("kitaplığından kaldır") ||
           l.contains("kitaplığından çıkar") || l.contains("saved to your library") ||
           l.contains("kitaplığına eklendi") || l.contains("kitaplığa eklendi") ||
           l.contains("added to your library") || l.contains("added to liked songs") ||
           l.contains("saved to liked songs") || l == "saved" || l == "kaydedildi" ||
           l == "liked" || l == "beğenildi" || l.contains("kütüphanenden kaldır") ||
           l.contains("kütüphanenden çıkar") || l.contains("kütüphanene eklendi") {
            return true
        }

        // Not favorited / Unsaved (liked = false)
        if l.contains("beğenilen şarkılar'a ekle") || l.contains("beğenilen şarkılara ekle") ||
           l.contains("beğenilen şarkılar'a kaydet") || l.contains("beğenilen şarkılara kaydet") ||
           l.contains("add to liked songs") || l.contains("save to your liked songs") ||
           l.contains("save to your library") || l.contains("add to your library") ||
           l.contains("kitaplığına ekle") || l.contains("kitaplığına kaydet") ||
           l.contains("kitaplığa ekle") || l.contains("kitaplığa kaydet") ||
           l.contains("kütüphanene ekle") || l.contains("kütüphanene kaydet") ||
           l == "save" || l == "kaydet" {
            return false
        }
        return nil
    }

    static func elementFavoriteState(_ element: AXUIElement) -> Bool? {
        for text in allLabels(element) {
            if let state = favoriteState(for: text) {
                return state
            }
        }
        return nil
    }

    private static func isButtonRole(_ role: String) -> Bool {
        role == (kAXButtonRole as String) ||
        role == (kAXCheckBoxRole as String) ||
        role == "AXButton" || role == "AXCheckBox" || role == "AXRadioButton"
    }

    static func favoriteControl(_ root: AXUIElement) -> AXUIElement? {
        let all = descendants(root)
        if let bar = all.first(where: {
            let l = label($0).lowercased()
            return l.contains("now playing") || l.contains("şu anda çalan") || l.contains("çalınan parça")
        }), let control = descendants(bar).first(where: {
            let role = attribute($0, kAXRoleAttribute) as? String ?? ""
            return isButtonRole(role) && elementFavoriteState($0) != nil
        }) {
            return control
        }
        return all.first(where: {
            let role = attribute($0, kAXRoleAttribute) as? String ?? ""
            return isButtonRole(role) && elementFavoriteState($0) != nil
        }) ?? all.first(where: {
            elementFavoriteState($0) != nil
        })
    }

    static func favorite() -> Bool? {
        guard let root = root(), let control = favoriteControl(root) else { return nil }
        return elementFavoriteState(control)
    }

    static func upcomingTracks() -> [QueueTrackItem] {
        guard let root = root() else { return [] }
        var windowsRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windowsRef)
        guard let windows = windowsRef as? [AXUIElement], let mainWindow = windows.first else { return [] }

        let allElements = descendants(mainWindow, maxCount: 20000)

        let queueTable = allElements.first { el in
            let role = attribute(el, kAXRoleAttribute) as? String ?? ""
            guard role == "AXTable" || role == "AXOutline" || role == "AXList" else { return false }
            let l = label(el).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return l.contains("sonraki") ||
                   l.contains("next up") ||
                   l.contains("next in queue") ||
                   l.contains("sırada") ||
                   l.contains("çalma sırası") ||
                   l.contains("queue")
        }

        guard let table = queueTable else { return [] }

        let rows = descendants(table, maxCount: 2000).filter { el in
            let role = attribute(el, kAXRoleAttribute) as? String ?? ""
            return role == (kAXRowRole as String) || role == "AXRow"
        }

        return rows.compactMap { row -> QueueTrackItem? in
            var title = label(row)
            var artists = descendants(row, maxCount: 50).filter { el in
                attribute(el, kAXRoleAttribute) as? String == "AXLink"
            }.map { el in
                label(el)
            }.filter { txt in
                !txt.isEmpty
            }

            if artists.isEmpty {
                let texts = descendants(row, maxCount: 50).filter { el in
                    attribute(el, kAXRoleAttribute) as? String == (kAXStaticTextRole as String)
                }.map { el in
                    label(el)
                }.filter { txt in
                    !txt.isEmpty && txt != title
                }
                if let first = texts.first {
                    artists = [first]
                }
            }

            if title.isEmpty {
                title = descendants(row, maxCount: 50).first(where: { el in
                    let r = attribute(el, kAXRoleAttribute) as? String ?? ""
                    return r == "AXLink" || r == (kAXStaticTextRole as String)
                }).map { el in
                    label(el)
                } ?? ""
            }
            guard !title.isEmpty else { return nil }
            return QueueTrackItem(title: title, artist: artists.joined(separator: ", "), duration: "")
        }
    }
}
