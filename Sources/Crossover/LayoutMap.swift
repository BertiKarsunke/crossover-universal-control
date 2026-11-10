import AppKit
import SwiftUI

struct LayoutMapDisplay: Identifiable {
    let displayUUID: String
    let isIPad: Bool
    let frame: CGRect
    var id: String { displayUUID }
}

struct LayoutMapCrossing: Identifiable {
    let start: CGPoint
    let end: CGPoint
    let id: String
}

struct LayoutMapGeometry {
    let displays: [LayoutMapDisplay]
    let crossings: [LayoutMapCrossing]
}

func layoutMapGeometry(layout: [DisplayLayoutEntry], segments: [CrossingSegment], size: CGSize) -> LayoutMapGeometry? {
    guard !layout.isEmpty, size.width > 0, size.height > 0,
          layout.allSatisfy({ $0.rect.width > 0 && $0.rect.height > 0 }) else { return nil }
    let bounds = layout.reduce(CGRect.null) { $0.union($1.rect) }
    guard bounds.width > 0, bounds.height > 0 else { return nil }
    let scale = min(size.width / bounds.width, size.height / bounds.height)
    let offsetX = (size.width - bounds.width * scale) / 2
    let offsetY = (size.height - bounds.height * scale) / 2
    let displays = layout.map { entry -> LayoutMapDisplay in
        let frame = CGRect(x: offsetX + (entry.rect.minX - bounds.minX) * scale,
                           y: offsetY + (entry.rect.minY - bounds.minY) * scale,
                           width: entry.rect.width * scale,
                           height: entry.rect.height * scale)
        return LayoutMapDisplay(displayUUID: entry.displayUUID, isIPad: entry.displayUUID == zeroDisplayUUID,
                                frame: CGRect(x: frame.minX / size.width, y: frame.minY / size.height,
                                              width: frame.width / size.width, height: frame.height / size.height))
    }
    let crossings = segments.compactMap { segment -> LayoutMapCrossing? in
        guard let display = displays.first(where: { $0.displayUUID == segment.displayUUID }) else { return nil }
        let frame = CGRect(x: display.frame.minX * size.width, y: display.frame.minY * size.height,
                           width: display.frame.width * size.width, height: display.frame.height * size.height)
        let start: CGPoint
        let end: CGPoint
        switch segment.edge {
        case .top, .bottom:
            let y = segment.edge == .top ? frame.minY : frame.maxY
            start = CGPoint(x: frame.minX + frame.width * segment.startFraction, y: y)
            end = CGPoint(x: frame.minX + frame.width * segment.endFraction, y: y)
        case .left, .right:
            let x = segment.edge == .left ? frame.minX : frame.maxX
            start = CGPoint(x: x, y: frame.minY + frame.height * segment.startFraction)
            end = CGPoint(x: x, y: frame.minY + frame.height * segment.endFraction)
        }
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return nil }
        let inset = min(2.5, length / 2)
        let unitX = (end.x - start.x) / length
        let unitY = (end.y - start.y) / length
        let shortenedStart = CGPoint(x: start.x + unitX * inset, y: start.y + unitY * inset)
        let shortenedEnd = CGPoint(x: end.x - unitX * inset, y: end.y - unitY * inset)
        return LayoutMapCrossing(start: CGPoint(x: shortenedStart.x / size.width, y: shortenedStart.y / size.height),
                                 end: CGPoint(x: shortenedEnd.x / size.width, y: shortenedEnd.y / size.height),
                                 id: "\(segment.displayUUID)-\(segment.edge.rawValue)-\(segment.startFraction)-\(segment.endFraction)")
    }
    return LayoutMapGeometry(displays: displays, crossings: crossings)
}

struct LayoutMap: View {
    let layout: [DisplayLayoutEntry]
    let segments: [CrossingSegment]
    let zoneColor: Color
    let tokens: PopoverTokens

    private let size = CGSize(width: 288, height: 120)

    var body: some View {
        if let geometry = layoutMapGeometry(layout: layout, segments: segments, size: size) {
            ZStack(alignment: .topLeading) {
                ForEach(geometry.displays) { display in
                    let frame = CGRect(x: display.frame.minX * size.width, y: display.frame.minY * size.height,
                                       width: display.frame.width * size.width, height: display.frame.height * size.height)
                    let outlineFrame = frame.insetBy(dx: 1, dy: 1)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tokens.mapSurface)
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .stroke(tokens.textSecondary, lineWidth: 1))
                        .frame(width: outlineFrame.width, height: outlineFrame.height)
                        .position(x: outlineFrame.midX, y: outlineFrame.midY)
                    if frame.width >= 48 && frame.height >= 18 {
                        Text(displayName(display, availableWidth: frame.width - 8))
                            .font(tokens.mapLabel)
                            .foregroundStyle(tokens.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(width: frame.width - 8)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
                ForEach(geometry.crossings) { crossing in
                    Path { path in
                        path.move(to: CGPoint(x: crossing.start.x * size.width, y: crossing.start.y * size.height))
                        path.addLine(to: CGPoint(x: crossing.end.x * size.width, y: crossing.end.y * size.height))
                    }
                    .stroke(zoneColor, style: StrokeStyle(lineWidth: 5, lineCap: .butt))
                }
            }
            .frame(width: size.width, height: size.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Display layout with \(geometry.displays.count) displays and \(geometry.crossings.count) crossing zones")
        } else {
            Text("No layout yet")
                .font(tokens.bodySmall)
                .foregroundStyle(tokens.textSecondary)
                .frame(width: size.width, height: size.height, alignment: .leading)
        }
    }

    private func displayName(_ display: LayoutMapDisplay, availableWidth: CGFloat) -> String {
        guard !display.isIPad else { return "iPad" }
        let name = screen(for: display.displayUUID)?.localizedName ?? "Mac display"
        guard name != "Built-in Retina Display" else { return "Built-in" }
        guard name.hasPrefix("DELL ") else { return name }
        let font = tokens.mapLabelNS
        let fullWidth = (name as NSString).size(withAttributes: [.font: font]).width
        guard fullWidth > availableWidth else { return name }
        let shortName = String(name.dropFirst(5))
        return (shortName as NSString).size(withAttributes: [.font: font]).width <= availableWidth ? shortName : name
    }
}
