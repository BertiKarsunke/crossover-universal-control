import AppKit
import ColorSync

struct RGBAColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: NSColor) {
        let color = color.usingColorSpace(.sRGB) ?? color
        red = color.redComponent
        green = color.greenComponent
        blue = color.blueComponent
        alpha = color.alphaComponent
    }
}

struct ZoneColors: Codable, Equatable {
    var connected: RGBAColor
    var standby: RGBAColor
    var disconnected: RGBAColor

    static let defaults = ZoneColors(
        connected: RGBAColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 0.5),
        standby: RGBAColor(red: 0, green: 0.478, blue: 1, alpha: 0.4),
        disconnected: RGBAColor(red: 1, green: 0.231, blue: 0.188, alpha: 0.3)
    )

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
    func save() {
        if let data = encoded() { UserDefaults.standard.set(data, forKey: "zoneColors") }
    }
    static func decode(_ data: Data) -> ZoneColors? { try? JSONDecoder().decode(ZoneColors.self, from: data) }
    static func load() -> ZoneColors {
        UserDefaults.standard.data(forKey: "zoneColors").flatMap(decode) ?? .defaults
    }
}

let zeroDisplayUUID = "00000000-0000-0000-0000-000000000000"

struct DisplayLayoutEntry: Equatable {
    let displayUUID: String
    let rect: CGRect
}

struct CrossingSegment: Equatable {
    let displayUUID: String
    let edge: ScreenEdge
    let startFraction: Double
    let endFraction: Double
}

private struct CrossingSegmentKey: Hashable {
    let displayUUID: String
    let edge: ScreenEdge
}

private extension CrossingSegment {
    var key: CrossingSegmentKey { CrossingSegmentKey(displayUUID: displayUUID, edge: edge) }
}

func overlayFrame(_ segment: CrossingSegment, screenFrame frame: CGRect) -> CGRect {
    let start = CGFloat(segment.startFraction)
    let end = CGFloat(segment.endFraction)
    return switch segment.edge {
    case .bottom: CGRect(x: frame.minX + frame.width * start, y: frame.minY, width: frame.width * (end - start), height: 6)
    case .top: CGRect(x: frame.minX + frame.width * start, y: frame.maxY - 6, width: frame.width * (end - start), height: 6)
    case .left: CGRect(x: frame.minX, y: frame.maxY - frame.height * end, width: 6, height: frame.height * (end - start))
    case .right: CGRect(x: frame.maxX - 6, y: frame.maxY - frame.height * end, width: 6, height: frame.height * (end - start))
    }
}

func parseDisplayLayout(_ line: String) -> [DisplayLayoutEntry]? {
    guard let label = line.range(of: "displayLayout:") else { return nil }
    let layoutText = String(line[label.upperBound...])
    guard !layoutText.contains("<…>") else { return nil }
    let pattern = #"[A-Fa-f0-9]+:([A-Fa-f0-9-]+): CGRect\((-?[0-9.]+), (-?[0-9.]+), ([0-9.]+), ([0-9.]+)\)"#
    let regex = try! NSRegularExpression(pattern: pattern)
    let text = layoutText as NSString
    let entries = regex.matches(in: layoutText, range: NSRange(location: 0, length: text.length)).compactMap { match -> DisplayLayoutEntry? in
        guard let x = Double(text.substring(with: match.range(at: 2))),
              let y = Double(text.substring(with: match.range(at: 3))),
              let width = Double(text.substring(with: match.range(at: 4))),
              let height = Double(text.substring(with: match.range(at: 5))) else { return nil }
        return DisplayLayoutEntry(displayUUID: text.substring(with: match.range(at: 1)).uppercased(),
                                  rect: CGRect(x: x, y: y, width: width, height: height))
    }
    guard entries.contains(where: { $0.displayUUID == zeroDisplayUUID }),
          entries.contains(where: { $0.displayUUID != zeroDisplayUUID }) else { return nil }
    return entries
}

func segments(_ layout: [DisplayLayoutEntry]) -> [CrossingSegment] {
    let iPads = layout.filter { $0.displayUUID == zeroDisplayUUID }
    let macs = layout.filter { $0.displayUUID != zeroDisplayUUID }
    return iPads.flatMap { iPad in macs.compactMap { segment(mac: $0, iPad: iPad) } }
}

private func segment(mac: DisplayLayoutEntry, iPad: DisplayLayoutEntry) -> CrossingSegment? {
    let tolerance = 2.0
    let horizontalStart = max(mac.rect.minX, iPad.rect.minX)
    let horizontalEnd = min(mac.rect.maxX, iPad.rect.maxX)
    if horizontalEnd > horizontalStart {
        let edge: ScreenEdge?
        if abs(mac.rect.maxY - iPad.rect.minY) <= tolerance { edge = .bottom }
        else if abs(mac.rect.minY - iPad.rect.maxY) <= tolerance { edge = .top }
        else { edge = nil }
        if let edge {
            return CrossingSegment(displayUUID: mac.displayUUID, edge: edge,
                                   startFraction: (horizontalStart - mac.rect.minX) / mac.rect.width,
                                   endFraction: (horizontalEnd - mac.rect.minX) / mac.rect.width)
        }
    }

    let verticalStart = max(mac.rect.minY, iPad.rect.minY)
    let verticalEnd = min(mac.rect.maxY, iPad.rect.maxY)
    guard verticalEnd > verticalStart else { return nil }
    let edge: ScreenEdge?
    if abs(mac.rect.maxX - iPad.rect.minX) <= tolerance { edge = .right }
    else if abs(mac.rect.minX - iPad.rect.maxX) <= tolerance { edge = .left }
    else { edge = nil }
    guard let edge else { return nil }
    return CrossingSegment(displayUUID: mac.displayUUID, edge: edge,
                           startFraction: (verticalStart - mac.rect.minY) / mac.rect.height,
                           endFraction: (verticalEnd - mac.rect.minY) / mac.rect.height)
}

func screen(for displayUUID: String) -> NSScreen? {
    NSScreen.screens.first { screen in
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return false }
        return (CFUUIDCreateString(nil, uuid) as String).caseInsensitiveCompare(displayUUID) == .orderedSame
    }
}

extension IPadPosition {
    var description: String {
        let name = screen(for: displayUUID)?.localizedName ?? "Mac screen"
        return "\(edge.positionLabel) · \(name)"
    }
}

extension CrossingSegment {
    var description: String {
        let name = screen(for: displayUUID)?.localizedName ?? "Mac screen"
        return "\(edge.positionLabel) · \(name) · \(Int((startFraction * 100).rounded()))-\(Int((endFraction * 100).rounded()))%"
    }
}

@MainActor
final class OverlayController {
    private var windows: [CrossingSegmentKey: NSWindow] = [:]

    func update(segments: [CrossingSegment], state: ConnectionState, session: SessionSubstate?,
                colors: ZoneColors, enabled: Bool, universalControlOff: Bool) {
        guard enabled, !universalControlOff, state != .unknown else {
            windows.values.forEach { $0.close() }
            windows.removeAll()
            return
        }
        let color = state == .disconnected
            ? colors.disconnected.nsColor
            : session == .standby ? colors.standby.nsColor : colors.connected.nsColor
        let activeKeys = Set(segments.map(\.key))
        for key in Array(windows.keys) where !activeKeys.contains(key) {
            windows.removeValue(forKey: key)?.close()
        }
        for segment in segments {
            guard let screen = screen(for: segment.displayUUID) else {
                windows.removeValue(forKey: segment.key)?.close()
                continue
            }
            let frame = overlayFrame(segment, screenFrame: screen.frame)
            let window = windows[segment.key] ?? makeWindow(frame: frame)
            window.setFrame(frame, display: true)
            window.backgroundColor = color
            window.orderFrontRegardless()
            windows[segment.key] = window
        }
    }

    private func makeWindow(frame: CGRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return window
    }
}
