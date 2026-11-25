import Foundation

/// Every item the menu bar (status item) menu can show. The raw values are
/// stored in UserDefaults: add cases, never rename them.
enum StatusMenuItemID: String, CaseIterable {
    case captureArea
    case captureScreen
    case captureOCR
    case quickCapture
    case captureLastArea
    case scrollCapture
    case captureActiveWindow
    case captureDelay
    case recordArea
    case recordGIF
    case recordScreen
    case recentCaptures
    case historyPanel
    case openImage
    case openVideo
    case showRecordings
    case openFromClipboard
    case pinFromClipboard
    /// The "More" submenu itself. It can be moved inside the menu and is only
    /// shown when something is in it.
    case more
    case settings
    case checkForUpdates
    case quit

    /// Items that can't leave the menu: without them the user couldn't get
    /// back to Settings or quit the app.
    var isLocked: Bool {
        switch self {
        case .settings, .quit, .more: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .captureArea: return L("Capture Area")
        case .captureScreen: return L("Capture Screen")
        case .captureOCR: return L("Capture OCR & QR")
        case .quickCapture: return L("Quick Capture")
        case .captureLastArea: return L("Capture Last Area")
        case .scrollCapture: return L("Scroll Capture")
        case .captureActiveWindow: return L("Capture Active Window")
        case .captureDelay: return L("Capture Delay")
        case .recordArea: return L("Record Area")
        case .recordGIF: return "\(L("Record")) \(L("GIF"))"
        case .recordScreen: return L("Record Screen")
        case .recentCaptures: return L("Recent Captures")
        case .historyPanel: return L("Show History Panel")
        case .openImage: return L("Open Image...")
        case .openVideo: return L("Open Video...")
        case .showRecordings: return L("Show Recordings in Finder")
        case .openFromClipboard: return L("Open from Clipboard")
        case .pinFromClipboard: return L("Pin from Clipboard")
        case .more: return L("More")
        case .settings: return L("Settings...")
        case .checkForUpdates: return L("Check for Updates...")
        case .quit: return L("Quit macshot")
        }
    }

    var symbolName: String {
        switch self {
        case .captureArea: return "crop"
        case .captureScreen: return "desktopcomputer"
        case .captureOCR: return "text.viewfinder"
        case .quickCapture: return "square.and.arrow.down"
        case .captureLastArea: return "arrow.counterclockwise.circle"
        case .scrollCapture: return "scroll"
        case .captureActiveWindow: return "macwindow"
        case .captureDelay: return "timer"
        case .recordArea: return "record.circle"
        case .recordGIF: return "photo.stack"
        case .recordScreen: return "menubar.dock.rectangle"
        case .recentCaptures: return "clock.arrow.circlepath"
        case .historyPanel: return "square.grid.2x2"
        case .openImage: return "photo.on.rectangle.angled"
        case .openVideo: return "film"
        case .showRecordings: return "folder"
        case .openFromClipboard: return "doc.on.clipboard"
        case .pinFromClipboard: return "pin.fill"
        case .more: return "ellipsis.circle"
        case .settings: return "gear"
        case .checkForUpdates: return "arrow.triangle.2.circlepath"
        case .quit: return "power"
        }
    }

    /// The global shortcut shown next to the item, if it has one.
    var hotkeySlot: HotkeyManager.HotkeySlot? {
        switch self {
        case .captureArea: return .captureArea
        case .captureScreen: return .captureFullScreen
        case .captureOCR: return .captureOCR
        case .quickCapture: return .quickCapture
        case .captureLastArea: return .captureLastArea
        case .scrollCapture: return .scrollCapture
        case .captureActiveWindow: return .captureActiveWindow
        case .recordArea: return .recordArea
        case .recordGIF: return .recordGIF
        case .recordScreen: return .recordScreen
        case .historyPanel: return .historyOverlay
        case .openFromClipboard: return .openFromClipboard
        case .pinFromClipboard: return .pinFromClipboard
        default: return nil
        }
    }

    /// Fixed in-menu shortcut (not a global hotkey).
    var fixedShortcut: String? {
        switch self {
        case .settings: return "⌘,"
        case .quit: return "⌘Q"
        default: return nil
        }
    }

    var hasSubmenu: Bool { self == .captureDelay || self == .recentCaptures || self == .more }

    var captureMenuItemID: CaptureMenuItemID? { CaptureMenuItemID(rawValue: rawValue) }
}

/// One row of the layout: an item or a separator line.
enum StatusMenuEntry: Hashable {
    case item(StatusMenuItemID)
    case separator

    static let separatorToken = "-"

    var token: String {
        switch self {
        case .item(let id): return id.rawValue
        case .separator: return Self.separatorToken
        }
    }

    init?(token: String) {
        if token == Self.separatorToken { self = .separator; return }
        guard let id = StatusMenuItemID(rawValue: token) else { return nil }
        self = .item(id)
    }

    var itemID: StatusMenuItemID? {
        if case .item(let id) = self { return id }
        return nil
    }

    var isLocked: Bool { itemID?.isLocked ?? false }
}

/// Where each entry of the menu bar menu goes: straight in the menu, under the
/// "More" submenu, or not shown. Every item is in exactly one zone; locked
/// items are always in `menu`.
struct StatusMenuLayout: Equatable {
    enum Zone: String, CaseIterable {
        case menu, more, hidden
    }

    var menu: [StatusMenuEntry]
    var more: [StatusMenuEntry]
    var hidden: [StatusMenuEntry]

    static let userDefaultsKey = "statusMenuLayout"

    static let `default` = StatusMenuLayout(
        menu: defaultMenu(captureOrder: CaptureMenuItemID.defaultOrder),
        more: [],
        hidden: []
    )

    static func defaultMenu(captureOrder: [CaptureMenuItemID]) -> [StatusMenuEntry] {
        captureOrder.compactMap { StatusMenuItemID(rawValue: $0.rawValue) }.map { .item($0) }
            + [.item(.captureActiveWindow), .item(.captureDelay), .separator,
               .item(.recordArea), .item(.recordGIF), .item(.recordScreen), .separator,
               .item(.recentCaptures), .item(.historyPanel), .separator,
               .item(.openImage), .item(.openVideo), .item(.showRecordings),
               .item(.openFromClipboard), .item(.pinFromClipboard), .separator,
               .item(.more), .item(.settings), .item(.checkForUpdates), .separator,
               .item(.quit)]
    }

    subscript(zone: Zone) -> [StatusMenuEntry] {
        get {
            switch zone {
            case .menu: return menu
            case .more: return more
            case .hidden: return hidden
            }
        }
        set {
            switch zone {
            case .menu: menu = newValue
            case .more: more = newValue
            case .hidden: hidden = newValue
            }
        }
    }

    func zone(of item: StatusMenuItemID) -> Zone? {
        Zone.allCases.first { self[$0].contains(.item(item)) }
    }

    /// Every item in every zone, in zone order (menu, more, hidden).
    var allItems: [StatusMenuItemID] {
        (menu + more + hidden).compactMap(\.itemID)
    }

    /// Whether `entry` may be dropped into `zone`.
    static func canPlace(_ entry: StatusMenuEntry, in zone: Zone) -> Bool {
        if entry.isLocked { return zone == .menu }
        return true
    }

    /// Moves the entry at `from` to `to` (index in the destination zone as it
    /// is after removing the entry). Returns false and changes nothing when the
    /// move isn't allowed. A separator dropped into Hidden is deleted.
    @discardableResult
    mutating func move(from source: (zone: Zone, index: Int), to destination: (zone: Zone, index: Int)) -> Bool {
        guard self[source.zone].indices.contains(source.index) else { return false }
        let entry = self[source.zone][source.index]
        guard Self.canPlace(entry, in: destination.zone) else { return false }
        self[source.zone].remove(at: source.index)
        if entry == .separator && destination.zone == .hidden { return true }
        let index = min(max(0, destination.index), self[destination.zone].count)
        self[destination.zone].insert(entry, at: index)
        return true
    }

    /// Adds a separator to the menu, just above the "More"/Settings block.
    mutating func addSeparator() {
        let anchor = menu.firstIndex(of: .item(.more)) ?? menu.firstIndex(of: .item(.settings)) ?? menu.count
        menu.insert(.separator, at: anchor)
    }

    /// Repairs anything a stored layout (older, newer or hand-edited) can get
    /// wrong: duplicates and unknown tokens are dropped, separators can't be
    /// hidden, locked items go back to the menu, and items this layout doesn't
    /// mention (added in a newer build) join the menu where the default has them.
    func normalized() -> StatusMenuLayout {
        var seen = Set<StatusMenuItemID>()
        func clean(_ entries: [StatusMenuEntry], zone: Zone) -> [StatusMenuEntry] {
            entries.filter { entry in
                guard let id = entry.itemID else { return zone != .hidden }
                return seen.insert(id).inserted
            }
        }
        var result = StatusMenuLayout(
            menu: clean(menu, zone: .menu),
            more: clean(more, zone: .more),
            hidden: clean(hidden, zone: .hidden)
        )

        for zone in [Zone.more, .hidden] {
            let locked = result[zone].filter(\.isLocked)
            guard !locked.isEmpty else { continue }
            result[zone].removeAll(where: \.isLocked)
            for entry in locked { result.insertInMenuLikeDefault(entry) }
        }

        let present = Set(result.allItems)
        for id in StatusMenuItemID.allCases where !present.contains(id) {
            result.insertInMenuLikeDefault(.item(id))
        }
        return result
    }

    /// Inserts `entry` into the menu after the nearest item that precedes it in
    /// the default layout, or at the top.
    private mutating func insertInMenuLikeDefault(_ entry: StatusMenuEntry) {
        let defaults = Self.default.menu
        guard let defaultIndex = defaults.firstIndex(of: entry) else {
            menu.append(entry)
            return
        }
        for previous in defaults[..<defaultIndex].reversed() where previous != .separator {
            if let index = menu.firstIndex(of: previous) {
                menu.insert(entry, at: index + 1)
                return
            }
        }
        menu.insert(entry, at: 0)
    }

    /// The entries to actually build: no leading/trailing or doubled separators,
    /// and no "More" item when More is empty.
    static func displayEntries(_ entries: [StatusMenuEntry], moreIsEmpty: Bool) -> [StatusMenuEntry] {
        var out: [StatusMenuEntry] = []
        for entry in entries {
            if entry == .item(.more) && moreIsEmpty { continue }
            if entry == .separator && (out.isEmpty || out.last == .separator) { continue }
            out.append(entry)
        }
        while out.last == .separator { out.removeLast() }
        return out
    }

    // MARK: Persistence

    static func load(defaults: UserDefaults = .standard) -> StatusMenuLayout {
        if let stored = defaults.dictionary(forKey: userDefaultsKey) {
            func entries(_ key: String) -> [StatusMenuEntry] {
                ((stored[key] as? [Any]) ?? []).compactMap { ($0 as? String).flatMap(StatusMenuEntry.init(token:)) }
            }
            return StatusMenuLayout(menu: entries("menu"), more: entries("more"), hidden: entries("hidden")).normalized()
        }
        // Before this layout existed only the capture actions could be reordered.
        if let legacy = defaults.stringArray(forKey: CaptureMenuItemID.userDefaultsKey) {
            var order: [CaptureMenuItemID] = []
            for raw in legacy {
                if let id = CaptureMenuItemID(rawValue: raw), !order.contains(id) { order.append(id) }
            }
            order += CaptureMenuItemID.defaultOrder.filter { !order.contains($0) }
            return StatusMenuLayout(menu: defaultMenu(captureOrder: order), more: [], hidden: []).normalized()
        }
        return .default
    }

    func save(defaults: UserDefaults = .standard) {
        let layout = normalized()
        defaults.set([
            "menu": layout.menu.map(\.token),
            "more": layout.more.map(\.token),
            "hidden": layout.hidden.map(\.token),
        ], forKey: Self.userDefaultsKey)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
        defaults.removeObject(forKey: CaptureMenuItemID.userDefaultsKey)
    }
}
