import AppKit
import ApplicationServices

private final class ResourceBundleFinder {}

enum AppResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return Bundle(for: ResourceBundleFinder.self)
        #endif
    }
}

enum AppLanguage: String, CaseIterable {
    case en
    case fr
    case es

    static let fallback: AppLanguage = .en

    static func from(identifier: String?) -> AppLanguage? {
        guard let identifier, !identifier.isEmpty else {
            return nil
        }

        let languageCode = Locale(identifier: identifier).language.languageCode?.identifier
            ?? String(identifier.prefix(2)).lowercased()

        return AppLanguage(rawValue: languageCode)
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var readmeBaseName: String {
        switch self {
        case .fr:
            return "README.fr"
        case .en, .es:
            return "README"
        }
    }
}

enum LanguageResolver {
    static let selectedLanguage: AppLanguage = resolve()

    private static func resolve() -> AppLanguage {
        // Highest priority: launch arguments
        if let fromArgs = languageFromLaunchArguments() {
            return fromArgs
        }

        // Then optional environment override
        if let fromEnvironment = AppLanguage.from(identifier: ProcessInfo.processInfo.environment["MOVERESIZE_LANG"]) {
            return fromEnvironment
        }

        // Finally, follow the system language order
        for preferred in Locale.preferredLanguages {
            if let language = AppLanguage.from(identifier: preferred) {
                return language
            }
        }

        return AppLanguage.fallback
    }

    private static func languageFromLaunchArguments() -> AppLanguage? {
        let arguments = Array(CommandLine.arguments.dropFirst())

        for (index, argument) in arguments.enumerated() {
            if argument == "--lang" || argument == "--language" || argument == "-l" {
                guard arguments.indices.contains(index + 1) else {
                    continue
                }

                if let language = AppLanguage.from(identifier: arguments[index + 1]) {
                    return language
                }
            }

            if argument.hasPrefix("--lang=") {
                let value = String(argument.dropFirst("--lang=".count))
                if let language = AppLanguage.from(identifier: value) {
                    return language
                }
            }

            if argument.hasPrefix("--language=") {
                let value = String(argument.dropFirst("--language=".count))
                if let language = AppLanguage.from(identifier: value) {
                    return language
                }
            }
        }

        return nil
    }
}

enum L10n {
    private static let resolvedLanguage = LanguageResolver.selectedLanguage

    private static let localizedBundle: Bundle = {
        guard
            let lprojPath = AppResources.bundle.path(forResource: resolvedLanguage.rawValue, ofType: "lproj"),
            let bundle = Bundle(path: lprojPath)
        else {
            return AppResources.bundle
        }

        return bundle
    }()

    static func text(_ key: String) -> String {
        let translated = localizedBundle.localizedString(forKey: key, value: nil, table: nil)
        if translated != key {
            return translated
        }

        return AppResources.bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: resolvedLanguage.locale, arguments: arguments)
    }
}

enum InteractionMode {
    case move
    case resize
}

enum ConstraintMode {
    case none
    case horizontal
    case vertical
}

enum ModifierKey: String, CaseIterable {
    case option
    case command
    case function

    var displayName: String {
        switch self {
        case .option:
            return L10n.text("modifier.option")
        case .command:
            return L10n.text("modifier.command")
        case .function:
            return L10n.text("modifier.function")
        }
    }

    var eventFlag: CGEventFlags {
        switch self {
        case .option:
            return .maskAlternate
        case .command:
            return .maskCommand
        case .function:
            return .maskSecondaryFn
        }
    }
}

enum ShortcutAction: String {
    case move
    case resize

    var displayName: String {
        switch self {
        case .move:
            return L10n.text("action.move")
        case .resize:
            return L10n.text("action.resize")
        }
    }

    var defaultsKey: String {
        switch self {
        case .move:
            return "moveModifier"
        case .resize:
            return "resizeModifier"
        }
    }

    var defaultModifier: ModifierKey {
        switch self {
        case .move:
            return .option
        case .resize:
            return .command
        }
    }
}

enum ResizeAnchor: String, CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var displayName: String {
        switch self {
        case .topLeft:
            return L10n.text("anchor.top_left")
        case .topRight:
            return L10n.text("anchor.top_right")
        case .bottomLeft:
            return L10n.text("anchor.bottom_left")
        case .bottomRight:
            return L10n.text("anchor.bottom_right")
        }
    }
}

struct WindowFrame {
    var origin: CGPoint
    var size: CGSize

    var cgRect: CGRect {
        CGRect(origin: origin, size: size)
    }
}

final class AccessibilityWindowController {
    private let systemWideElement = AXUIElementCreateSystemWide()

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func windowElement(at screenPoint: CGPoint) -> AXUIElement? {
        for point in candidateLookupPoints(for: screenPoint) {
            var element: AXUIElement?
            let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &element)
            guard result == .success, let rawElement = element else {
                continue
            }

            if let window = resolveWindow(from: rawElement) {
                return window
            }
        }

        return fallbackWindowElement(at: screenPoint)
    }

    func lookupDescription(for screenPoint: CGPoint) -> String {
        candidateLookupPoints(for: screenPoint)
            .map { describe(point: $0) }
            .joined(separator: " | ")
    }

    func frame(for window: AXUIElement) -> WindowFrame? {
        guard
            let position = value(for: window, attribute: kAXPositionAttribute, as: CGPoint.self),
            let size = value(for: window, attribute: kAXSizeAttribute, as: CGSize.self)
        else {
            return nil
        }

        let cgOrigin = CoordinateSpace.shared.axToCG(position)
        return WindowFrame(origin: cgOrigin, size: size)
    }

    func setFrame(_ frame: WindowFrame, for window: AXUIElement) {
        var axOrigin = CoordinateSpace.shared.cgToAX(frame.origin)
        var size = frame.size

        guard
            let positionValue = AXValueCreate(.cgPoint, &axOrigin),
            let sizeValue = AXValueCreate(.cgSize, &size)
        else {
            return
        }

        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }

    private func climbToWindow(from element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element

        while let node = current {
            if role(of: node) == kAXWindowRole as String {
                return node
            }

            var parent: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(node, kAXParentAttribute as CFString, &parent)
            guard result == .success, let parentElement = parent else {
                break
            }
            current = (parentElement as! AXUIElement)
        }

        return nil
    }

    private func resolveWindow(from element: AXUIElement) -> AXUIElement? {
        if role(of: element) == kAXWindowRole as String {
            return element
        }

        for attribute in [kAXWindowAttribute as String, kAXTopLevelUIElementAttribute as String] {
            if let candidate = childElement(for: element, attribute: attribute),
               let window = climbToWindow(from: candidate) {
                return window
            }
        }

        return climbToWindow(from: element)
    }

    private func candidateLookupPoints(for screenPoint: CGPoint) -> [CGPoint] {
        let directPoint = screenPoint
        let flippedPoint = CoordinateSpace.shared.cgToAX(screenPoint)

        guard directPoint != flippedPoint else {
            return [directPoint]
        }

        return [directPoint, flippedPoint]
    }

    private func childElement(for element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard
            result == .success,
            let candidate = value,
            CFGetTypeID(candidate) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return unsafeBitCast(candidate, to: AXUIElement.self)
    }

    private func fallbackWindowElement(at screenPoint: CGPoint) -> AXUIElement? {
        for candidate in onScreenWindowCandidates(at: screenPoint) {
            let application = AXUIElementCreateApplication(candidate.ownerPID)
            if let window = matchingWindow(in: application, screenPoint: screenPoint, expectedBounds: candidate.bounds) {
                return window
            }
        }

        return nil
    }

    private func onScreenWindowCandidates(at screenPoint: CGPoint) -> [(ownerPID: pid_t, bounds: CGRect)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let lookupPoints = candidateLookupPoints(for: screenPoint)

        return windowInfoList.compactMap { info in
            guard
                let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                let ownerPIDValue = info[kCGWindowOwnerPID as String] as? NSNumber,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0
            else {
                return nil
            }

            let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            guard let bounds, lookupPoints.contains(where: { bounds.contains($0) }) else {
                return nil
            }

            return (ownerPID: pid_t(ownerPIDValue.int32Value), bounds: bounds)
        }
    }

    private func matchingWindow(in application: AXUIElement, screenPoint: CGPoint, expectedBounds: CGRect) -> AXUIElement? {
        let windows = elements(for: application, attribute: kAXWindowsAttribute)
        guard !windows.isEmpty else {
            return nil
        }

        if let exactMatch = windows.first(where: { window in
            guard let frame = frame(for: window) else {
                return false
            }

            return frame.cgRect.contains(screenPoint) || approximatelyEqual(frame.cgRect, expectedBounds)
        }) {
            return exactMatch
        }

        return windows.first(where: { frame(for: $0) != nil })
    }

    private func elements(for element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let rawArray = value as? [Any] else {
            return []
        }

        return rawArray.compactMap { candidate in
            guard CFGetTypeID(candidate as CFTypeRef) == AXUIElementGetTypeID() else {
                return nil
            }

            return unsafeBitCast(candidate, to: AXUIElement.self)
        }
    }

    private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.size.width - rhs.size.width) <= tolerance
            && abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    private func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value as? String
    }

    private func value<T>(for element: AXUIElement, attribute: String, as type: T.Type) -> T? {
        var rawValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
        guard result == .success, let axValue = rawValue, CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        let typedValue = axValue as! AXValue

        if type == CGPoint.self {
            var point = CGPoint.zero
            guard AXValueGetValue(typedValue, .cgPoint, &point) else {
                return nil
            }
            return point as? T
        }

        if type == CGSize.self {
            var size = CGSize.zero
            guard AXValueGetValue(typedValue, .cgSize, &size) else {
                return nil
            }
            return size as? T
        }

        return nil
    }

    private func describe(point: CGPoint) -> String {
        "(x: \(String(format: "%.1f", point.x)), y: \(String(format: "%.1f", point.y)))"
    }
}

final class CoordinateSpace {
    static let shared = CoordinateSpace()

    private init() {}

    private var desktopMaxY: CGFloat {
        NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
    }

    func cgToAX(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: desktopMaxY - point.y)
    }

    func axToCG(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: desktopMaxY - point.y)
    }
}

struct DragState {
    let mode: InteractionMode
    let constraint: ConstraintMode
    let window: AXUIElement
    let initialMouse: CGPoint
    let initialFrame: WindowFrame
}

final class WindowInteractionManager {
    private let windowController = AccessibilityWindowController()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var dragState: DragState?
    private let minimumWindowSize = CGSize(width: 240, height: 160)
    private let loggingEnabled = false

    var resizeAnchor: ResizeAnchor {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: "resizeAnchor"), let anchor = ResizeAnchor(rawValue: rawValue) else {
                return .topLeft
            }
            return anchor
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "resizeAnchor")
        }
    }

    func modifier(for action: ShortcutAction) -> ModifierKey {
        guard
            let rawValue = UserDefaults.standard.string(forKey: action.defaultsKey),
            let modifier = ModifierKey(rawValue: rawValue)
        else {
            return action.defaultModifier
        }

        return modifier
    }

    func setModifier(_ modifier: ModifierKey, for action: ShortcutAction) {
        let otherAction: ShortcutAction = action == .move ? .resize : .move
        let currentModifier = self.modifier(for: action)

        UserDefaults.standard.set(modifier.rawValue, forKey: action.defaultsKey)

        if self.modifier(for: otherAction) == modifier {
            UserDefaults.standard.set(currentModifier.rawValue, forKey: otherAction.defaultsKey)
        }
    }

    func menuDescription(for action: ShortcutAction) -> String {
        L10n.format("shortcut.description", modifier(for: action).displayName, action.displayName)
    }

    func usesConfiguredModifier(in flags: CGEventFlags) -> Bool {
        ShortcutAction.allCases.contains { flags.contains(modifier(for: $0).eventFlag) }
    }

    func start() {
        windowController.requestAccessibilityPermission()

        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let manager = Unmanaged<WindowInteractionManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            NSLog("Unable to create event tap. Check Accessibility and Input Monitoring permissions.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        log("event tap started")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            log("event tap re-enabled after \(type.rawValue)")
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown:
            return handleMouseDown(event)
        case .leftMouseDragged:
            return handleMouseDragged(event)
        case .leftMouseUp:
            return handleMouseUp(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleMouseDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let mode = interactionMode(for: flags)

        guard let mode else {
            return Unmanaged.passUnretained(event)
        }

        let constraint = constraintMode(for: flags)
        let mouseLocation = event.location
        guard
            let window = windowController.windowElement(at: mouseLocation),
            let frame = windowController.frame(for: window)
        else {
            log("mouseDown mode=\(mode.label) point=\(describe(point: mouseLocation)) window=none lookup=\(windowController.lookupDescription(for: mouseLocation))")
            return Unmanaged.passUnretained(event)
        }

        dragState = DragState(mode: mode, constraint: constraint, window: window, initialMouse: mouseLocation, initialFrame: frame)
        log("mouseDown mode=\(mode.label) constraint=\(constraint.label) point=\(describe(point: mouseLocation)) frame=\(describe(frame: frame))")
        return nil
    }

    private func handleMouseDragged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let state = dragState else {
            if usesConfiguredModifier(in: event.flags) {
                log("drag ignored point=\(describe(point: event.location)) activeCapture=false")
            }
            return Unmanaged.passUnretained(event)
        }

        let currentMouse = event.location
        var deltaX = currentMouse.x - state.initialMouse.x
        // CGEvent uses top-left origin (Y down), window frames use NSScreen origin (Y up) — invert Y.
        var deltaY = -(currentMouse.y - state.initialMouse.y)

        // Apply constraints
        switch state.constraint {
        case .horizontal:
            deltaY = 0
        case .vertical:
            deltaX = 0
        case .none:
            break
        }

        switch state.mode {
        case .move:
            let frame = WindowFrame(
                origin: CGPoint(x: state.initialFrame.origin.x + deltaX, y: state.initialFrame.origin.y + deltaY),
                size: state.initialFrame.size
            )
            log("drag move delta=(\(format(deltaX)), \(format(deltaY))) target=\(describe(frame: frame))")
            windowController.setFrame(frame, for: state.window)
        case .resize:
            let frame = resizedFrame(from: state.initialFrame, deltaX: deltaX, deltaY: deltaY)
            log("drag resize delta=(\(format(deltaX)), \(format(deltaY))) anchor=\(resizeAnchor.displayName) target=\(describe(frame: frame))")
            windowController.setFrame(frame, for: state.window)
        }

        return nil
    }

    private func handleMouseUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard dragState != nil else {
            return Unmanaged.passUnretained(event)
        }

        log("mouseUp point=\(describe(point: event.location))")
        dragState = nil
        return nil
    }

    private func interactionMode(for flags: CGEventFlags) -> InteractionMode? {
        if flags.contains(modifier(for: .resize).eventFlag) {
            return .resize
        }

        if flags.contains(modifier(for: .move).eventFlag) {
            return .move
        }

        return nil
    }

    private func constraintMode(for flags: CGEventFlags) -> ConstraintMode {
        let hasShift = flags.contains(.maskShift)
        let hasControl = flags.contains(.maskControl)

        if hasShift && !hasControl {
            return .horizontal
        } else if hasControl && !hasShift {
            return .vertical
        }

        return .none
    }

    private func log(_ message: String) {
        guard loggingEnabled else {
            return
        }

        NSLog("[MoveResize] \(message)")
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    private func describe(point: CGPoint) -> String {
        "(x: \(format(point.x)), y: \(format(point.y)))"
    }

    private func describe(frame: WindowFrame) -> String {
        "origin=(x: \(format(frame.origin.x)), y: \(format(frame.origin.y))) size=(w: \(format(frame.size.width)), h: \(format(frame.size.height)))"
    }

    private func resizedFrame(from frame: WindowFrame, deltaX: CGFloat, deltaY: CGFloat) -> WindowFrame {
        // frame.origin is the TOP-LEFT corner in NSScreen (Y-up) coordinates.
        // deltaY > 0 → mouse moved up; deltaY < 0 → mouse moved down.
        // The bottom of the window is at origin.y - height (lower Y = lower on screen).
        var originX = frame.origin.x
        var originY = frame.origin.y
        var width = frame.size.width
        var height = frame.size.height

        switch resizeAnchor {
        case .topLeft:
            // top-left is fixed; bottom-right corner moves
            width += deltaX
            height -= deltaY    // drag down (deltaY<0) → height grows
        case .topRight:
            // top-right is fixed; bottom-left corner moves
            originX += deltaX
            width -= deltaX
            height -= deltaY
        case .bottomLeft:
            // bottom-left is fixed; top-right corner moves
            originY += deltaY   // top edge shifts up/down
            width += deltaX
            height += deltaY    // drag up (deltaY>0) → height grows
        case .bottomRight:
            // bottom-right is fixed; top-left corner moves
            originX += deltaX
            originY += deltaY
            width -= deltaX
            height += deltaY
        }

        // Enforce minimum width
        if width < minimumWindowSize.width {
            let excess = minimumWindowSize.width - width
            width = minimumWindowSize.width
            if resizeAnchor == .topRight || resizeAnchor == .bottomRight {
                originX -= excess
            }
        }

        // Enforce minimum height
        if height < minimumWindowSize.height {
            let excess = minimumWindowSize.height - height
            height = minimumWindowSize.height
            if resizeAnchor == .bottomLeft || resizeAnchor == .bottomRight {
                originY -= excess
            }
        }

        return WindowFrame(
            origin: CGPoint(x: originX, y: originY),
            size: CGSize(width: width, height: height)
        )
    }
}

private extension InteractionMode {
    var label: String {
        switch self {
        case .move:
            return "move"
        case .resize:
            return "resize"
        }
    }
}

private extension ConstraintMode {
    var label: String {
        switch self {
        case .none:
            return "none"
        case .horizontal:
            return "horizontal"
        case .vertical:
            return "vertical"
        }
    }
}

extension ShortcutAction: CaseIterable {}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let interactionManager = WindowInteractionManager()
    private var statusItem: NSStatusItem?
    private var moveShortcutItem: NSMenuItem?
    private var resizeShortcutItem: NSMenuItem?
    private var moveModifierMenu: NSMenu?
    private var resizeModifierMenu: NSMenu?
    private var readmeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        interactionManager.start()
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.load()
            button.image?.accessibilityDescription = L10n.text("app.name")
        }

        let menu = NSMenu()
        let moveShortcutItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let resizeShortcutItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(moveShortcutItem)
        menu.addItem(resizeShortcutItem)
        menu.addItem(.separator())

        let moveModifierItem = NSMenuItem(title: L10n.text("menu.move_modifier"), action: nil, keyEquivalent: "")
        let moveModifierMenu = NSMenu(title: L10n.text("menu.move_modifier"))
        populateModifierMenu(moveModifierMenu, action: .move)
        menu.setSubmenu(moveModifierMenu, for: moveModifierItem)
        menu.addItem(moveModifierItem)

        let resizeModifierItem = NSMenuItem(title: L10n.text("menu.resize_modifier"), action: nil, keyEquivalent: "")
        let resizeModifierMenu = NSMenu(title: L10n.text("menu.resize_modifier"))
        populateModifierMenu(resizeModifierMenu, action: .resize)
        menu.setSubmenu(resizeModifierMenu, for: resizeModifierItem)
        menu.addItem(resizeModifierItem)

        menu.addItem(.separator())

        for anchor in ResizeAnchor.allCases {
            let item = NSMenuItem(title: anchor.displayName, action: #selector(selectAnchor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = anchor.rawValue
            item.state = anchor == interactionManager.resizeAnchor ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let readmeItem = NSMenuItem(title: L10n.text("menu.open_readme"), action: #selector(openReadme), keyEquivalent: "")
        readmeItem.target = self
        menu.addItem(readmeItem)

        let accessibilityItem = NSMenuItem(title: L10n.text("menu.open_accessibility_settings"), action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.text("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
        self.moveShortcutItem = moveShortcutItem
        self.resizeShortcutItem = resizeShortcutItem
        self.moveModifierMenu = moveModifierMenu
        self.resizeModifierMenu = resizeModifierMenu
        refreshShortcutMenuState()
    }

    private func populateModifierMenu(_ menu: NSMenu, action: ShortcutAction) {
        for modifier in ModifierKey.allCases {
            let item = NSMenuItem(title: modifier.displayName, action: #selector(selectModifier(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = "\(action.rawValue):\(modifier.rawValue)"
            item.state = modifier == interactionManager.modifier(for: action) ? .on : .off
            menu.addItem(item)
        }
    }

    private func refreshShortcutMenuState() {
        moveShortcutItem?.title = interactionManager.menuDescription(for: .move)
        resizeShortcutItem?.title = interactionManager.menuDescription(for: .resize)
        refreshModifierMenuState(moveModifierMenu, action: .move)
        refreshModifierMenuState(resizeModifierMenu, action: .resize)
    }

    private func refreshModifierMenuState(_ menu: NSMenu?, action: ShortcutAction) {
        guard let menu else {
            return
        }

        let selectedModifier = interactionManager.modifier(for: action)
        for item in menu.items {
            guard let rawValue = item.representedObject as? String else {
                continue
            }

            item.state = rawValue == "\(action.rawValue):\(selectedModifier.rawValue)" ? .on : .off
        }
    }

    @objc private func selectModifier(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let separatorIndex = rawValue.firstIndex(of: ":")
        else {
            return
        }

        let actionValue = String(rawValue[..<separatorIndex])
        let modifierValue = String(rawValue[rawValue.index(after: separatorIndex)...])

        guard
            let action = ShortcutAction(rawValue: actionValue),
            let modifier = ModifierKey(rawValue: modifierValue)
        else {
            return
        }

        interactionManager.setModifier(modifier, for: action)
        refreshShortcutMenuState()
    }

    @objc private func selectAnchor(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let anchor = ResizeAnchor(rawValue: rawValue),
            let menu = sender.menu
        else {
            return
        }

        interactionManager.resizeAnchor = anchor
        for item in menu.items where item.representedObject != nil {
            item.state = .off
        }
        sender.state = .on
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func openReadme() {
        // If window already exists, just bring it to front
        if let window = readmeWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        if let url = readmeURLForCurrentLanguage() {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                showReadmePreview(title: L10n.text("menu.open_readme"), content: content)
            } catch {
                NSSound.beep()
            }
        } else {
            NSSound.beep()
        }
    }

    private func showReadmePreview(title: String, content: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = title
        window.isReleasedWhenClosed = false

        // Create a scroll view with text view
        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: scrollView.bounds)
        textView.string = content
        textView.isEditable = false
        textView.isSelectable = true
        textView.autoresizingMask = [.width, .height]
        textView.font = NSFont.userFixedPitchFont(ofSize: 12)

        scrollView.documentView = textView
        window.contentView = scrollView

        // Center window on screen
        window.center()

        window.makeKeyAndOrderFront(nil)
        self.readmeWindow = window
    }

    private func readmeURLForCurrentLanguage() -> URL? {
        let preferredBaseName = LanguageResolver.selectedLanguage.readmeBaseName
        let fallbackBaseName = "README"

        let namesToTry: [String]
        if preferredBaseName == fallbackBaseName {
            namesToTry = [preferredBaseName]
        } else {
            namesToTry = [preferredBaseName, fallbackBaseName]
        }

        let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if let found = findFirstReadmeURL(inParentChainFrom: currentDirectoryURL, fileBaseNames: namesToTry, maxDepth: 8) {
            return found
        }

        // Also search relative to the app bundle location for packaged distributions.
        let appDirectoryURL = Bundle.main.bundleURL.deletingLastPathComponent()
        if let found = findFirstReadmeURL(inParentChainFrom: appDirectoryURL, fileBaseNames: namesToTry, maxDepth: 6) {
            return found
        }

        // Final fallback: open online README.
        if preferredBaseName == "README.fr" {
            return URL(string: "https://github.com/charlene/moveresize/blob/main/README.fr.md")
        }

        return URL(string: "https://github.com/charlene/moveresize/blob/main/README.md")
    }

    private func findFirstReadmeURL(inParentChainFrom startDirectory: URL, fileBaseNames: [String], maxDepth: Int) -> URL? {
        var currentDirectory = startDirectory
        let fileManager = FileManager.default

        for _ in 0...maxDepth {
            for baseName in fileBaseNames {
                let candidate = currentDirectory.appendingPathComponent("\(baseName).md")
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }

            let parent = currentDirectory.deletingLastPathComponent()
            if parent.path == currentDirectory.path {
                break
            }

            currentDirectory = parent
        }

        return nil
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
