import AppKit
import CoreText
import SwiftUI

enum ZoneColorRole: CaseIterable, Hashable {
    case connected, disconnected

    var label: String {
        switch self {
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        }
    }
}

struct PopoverTokens {
    let background: Color
    let mapSurface: Color
    let textPrimary: Color
    let textSecondary: Color
    let textDisabled: Color
    let border: Color
    let hover: Color
    let pressed: Color
    let focus: Color
    let actionBackground: Color
    let actionText: Color
    let connected: Color
    let disconnected: Color
    let clear: Color
    let display: Font
    let body: Font
    let bodySmall: Font
    let caption: Font
    let mapLabel: Font
    let mono: Font
    let mapLabelNS: NSFont

    init(_ scheme: ColorScheme) {
        background = scheme == .dark ? Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1) : Color(.sRGB, red: 0.961, green: 0.953, blue: 0.937, opacity: 1)
        mapSurface = scheme == .dark ? Color(.sRGB, red: 0.26, green: 0.26, blue: 0.26, opacity: 1) : Color(.sRGB, red: 0.88, green: 0.87, blue: 0.84, opacity: 1)
        textPrimary = scheme == .dark ? Color(.sRGB, red: 0.91, green: 0.91, blue: 0.91, opacity: 1) : Color(.sRGB, red: 0.1, green: 0.1, blue: 0.1, opacity: 1)
        textSecondary = scheme == .dark ? Color(.sRGB, red: 0.67, green: 0.67, blue: 0.67, opacity: 1) : Color(.sRGB, red: 0.37, green: 0.37, blue: 0.37, opacity: 1)
        textDisabled = scheme == .dark ? Color(.sRGB, red: 0.42, green: 0.42, blue: 0.42, opacity: 1) : Color(.sRGB, red: 0.52, green: 0.52, blue: 0.52, opacity: 1)
        border = scheme == .dark ? Color(.sRGB, red: 0.24, green: 0.24, blue: 0.24, opacity: 1) : Color(.sRGB, red: 0.78, green: 0.78, blue: 0.78, opacity: 1)
        hover = scheme == .dark ? Color(.sRGB, red: 0.12, green: 0.12, blue: 0.12, opacity: 1) : Color(.sRGB, red: 0.91, green: 0.90, blue: 0.88, opacity: 1)
        pressed = scheme == .dark ? Color(.sRGB, red: 0.16, green: 0.16, blue: 0.16, opacity: 1) : Color(.sRGB, red: 0.86, green: 0.85, blue: 0.83, opacity: 1)
        focus = textPrimary
        actionBackground = scheme == .dark ? Color(.sRGB, red: 0.22, green: 0.22, blue: 0.22, opacity: 1) : Color(.sRGB, red: 0.88, green: 0.87, blue: 0.84, opacity: 1)
        actionText = scheme == .dark ? Color(.sRGB, red: 0.92, green: 0.92, blue: 0.92, opacity: 1) : Color(.sRGB, red: 0.12, green: 0.12, blue: 0.12, opacity: 1)
        connected = Color(.sRGB, red: 0.29, green: 0.62, blue: 0.36, opacity: 1)
        disconnected = Color(.sRGB, red: 0.84, green: 0.10, blue: 0.13, opacity: 1)
        clear = .clear
        display = .custom("Doto", size: 36).weight(.medium)
        body = .custom("Space Grotesk", size: 14)
        bodySmall = .custom("Space Grotesk", size: 11)
        caption = .custom("Space Grotesk", size: 11)
        mapLabelNS = NSFont(name: "Space Grotesk", size: 11) ?? .systemFont(ofSize: 11)
        mapLabel = Font(mapLabelNS)
        mono = .custom("Space Mono", size: 11)
    }
}

enum FontRegistrar {
    static func register() {
        let folders = [Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
                       Bundle.module.resourceURL?.appendingPathComponent("Resources/Fonts")].compactMap { $0 }
        for folder in folders {
            guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for url in urls where url.pathExtension == "ttf" {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

@MainActor
func renderPreviews(to directory: String) throws {
    let folder = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let monitor = ConnectionMonitor(previewOnly: true)
    for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
        let renderer = ImageRenderer(content: NothingPopover(monitor: monitor, previewScheme: scheme))
        renderer.proposedSize = ProposedViewSize(width: 320, height: nil)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Crossover.Preview", code: 1)
        }
        try data.write(to: folder.appendingPathComponent("nothing-\(name).png"))
    }
}

@MainActor
func renderTrayIconSheet(to path: String) throws {
    let renderer = ImageRenderer(content: TrayIconSheet())
    renderer.proposedSize = ProposedViewSize(width: 700, height: 112)
    renderer.scale = 2
    guard let image = renderer.cgImage,
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Crossover.Preview", code: 2)
    }
    try data.write(to: URL(fileURLWithPath: path))
}

private struct TrayIconSheet: View {
    private let labels = ["Connected", "Standby", "Disconnected", "Off", "Unknown"]
    private let tokens = PopoverTokens(.dark)

    var body: some View {
        HStack(spacing: 24) {
            ForEach(Array(TrayState.allCases.enumerated()), id: \.offset) { index, state in
                let spec = trayIconSpec(for: state)
                VStack(spacing: 8) {
                    Image(systemName: spec.symbol)
                        .font(tokens.body.weight(.medium))
                        .foregroundStyle(tokens.textPrimary)
                        .opacity(spec.opacity)
                        .overlay(alignment: .topTrailing) {
                            if spec.showsRedDot {
                                Circle().fill(tokens.disconnected).frame(width: 8, height: 8)
                            }
                        }
                    Text(labels[index])
                        .font(tokens.caption)
                        .foregroundStyle(tokens.textSecondary)
                }
                .frame(width: 112)
            }
        }
        .frame(width: 700, height: 112)
        .background(tokens.background)
    }
}

struct NothingPopover: View {
    @ObservedObject var monitor: ConnectionMonitor
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var previewScheme: ColorScheme? = nil
    @State private var settingsExpanded = false
    @State private var hoveredColorPicker: ZoneColorRole?
    @FocusState private var focusedControl: PopoverControl?

    private enum PopoverControl: Hashable {
        case reconnect, settings, autoReconnect, crossingZone, launchAtLogin, loginItems, connectedColor, disconnectedColor, resetColors, quit
    }

    private var tokens: PopoverTokens { PopoverTokens(previewScheme ?? scheme) }
    private var stateWord: String {
        switch monitor.trayState {
        case .connected, .standby: "Connected"
        case .disconnected: "Disconnected"
        case .off: "Off"
        case .unknown: "Unknown"
        }
    }

    private var stateColor: Color {
        switch monitor.trayState {
        case .connected, .standby: tokens.connected
        case .disconnected: tokens.disconnected
        case .off: tokens.textDisabled
        case .unknown: tokens.textSecondary
        }
    }

    private var stateDetail: Text {
        if monitor.configuredDevicesEmpty { return Text("Turn on Universal Control in System Settings") }
        return switch monitor.state {
        case .connected:
            Text(monitor.sessionSubstate == .inUse ? "In use since " : "Standby since ") +
                Text(formattedLastChange(monitor.changedAt ?? Date())).font(tokens.mono)
        case .disconnected:
            if let changedAt = monitor.changedAt {
                Text("Since ") + Text(formattedLastChange(changedAt)).font(tokens.mono)
            } else {
                Text("Not connected")
            }
        case .unknown: Text("Waiting for Universal Control")
        }
    }

    private var reconnectStyle: PopoverButtonKind {
        monitor.state == .disconnected || monitor.reconnectStatus == "[FAILED]" ? .primary : .row
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stateWord)
                    .font(tokens.display)
                    .foregroundStyle(stateColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                stateDetail
                    .font(tokens.bodySmall)
                    .foregroundStyle(tokens.textPrimary)
                    .lineLimit(1)
            }

            LayoutMap(layout: monitor.displayLayout, segments: monitor.crossingSegments,
                      zoneColor: stateColor, tokens: tokens)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(monitor.positionLines.enumerated()), id: \.offset) { _, line in
                    positionText(line)
                        .font(tokens.bodySmall)
                        .foregroundStyle(tokens.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Button { monitor.reconnectNow() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Reconnect")
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PopoverButtonStyle(tokens: tokens, kind: reconnectStyle, pill: true))
                .popoverFocusRing(focusedControl == .reconnect, tokens: tokens, radius: 21)
                .focused($focusedControl, equals: .reconnect)
                .disabled(monitor.reconnectStatus == "[RECONNECTING...]")

                if let status = reconnectMessage {
                    Text(status)
                        .font(tokens.bodySmall)
                        .foregroundStyle(monitor.reconnectStatus == "[FAILED]" ? tokens.disconnected : tokens.textSecondary)
                        .padding(.leading, 12)
                }
            }
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { settingsExpanded.toggle() }
                } label: {
                    HStack {
                        Text("Settings")
                        Spacer()
                        Image(systemName: settingsExpanded ? "chevron.up" : "chevron.down")
                            .font(tokens.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PopoverButtonStyle(tokens: tokens, kind: .row))
                .popoverFocusRing(focusedControl == .settings, tokens: tokens, radius: 8)
                .focused($focusedControl, equals: .settings)
                .accessibilityValue(settingsExpanded ? "Expanded" : "Collapsed")

                if settingsExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        PopoverToggle(label: "Reconnect automatically", isOn: $monitor.autoReconnectEnabled,
                                      tokens: tokens, focused: focusedControl == .autoReconnect)
                            .focused($focusedControl, equals: .autoReconnect)
                        PopoverToggle(label: "Show crossing zone", isOn: $monitor.showCrossingZone,
                                      tokens: tokens, focused: focusedControl == .crossingZone)
                            .focused($focusedControl, equals: .crossingZone)
                        PopoverToggle(label: "Open at login", isOn: launchAtLoginBinding,
                                      tokens: tokens, focused: focusedControl == .launchAtLogin,
                                      enabled: monitor.canLaunchAtLogin)
                            .focused($focusedControl, equals: .launchAtLogin)
                        if monitor.canLaunchAtLogin {
                            Text("Open at login: \(monitor.loginItemStatusLabel)")
                                .font(tokens.bodySmall)
                                .foregroundStyle(tokens.textSecondary)
                        } else {
                            Text("Move Crossover to Applications to enable Open at login")
                                .font(tokens.caption)
                                .foregroundStyle(tokens.textSecondary)
                        }
                        if monitor.loginItemNeedsApproval {
                            Button("Approve in System Settings › Login Items") { monitor.openLoginItemsSettings() }
                                .buttonStyle(PopoverButtonStyle(tokens: tokens, kind: .text))
                                .popoverFocusRing(focusedControl == .loginItems, tokens: tokens, radius: 8)
                                .focused($focusedControl, equals: .loginItems)
                        }
                        if let error = monitor.loginItemError {
                            Text(error).font(tokens.caption).foregroundStyle(tokens.textSecondary)
                        }
                        if let osLabel = monitor.unverifiedOSLabel {
                            Text(osLabel)
                                .font(tokens.caption)
                                .foregroundStyle(tokens.textSecondary)
                        }

                        Text("Crossing zone colors")
                            .font(tokens.bodySmall)
                            .foregroundStyle(tokens.textSecondary)
                            .padding(.top, 12)
                        ForEach(ZoneColorRole.allCases, id: \.self) { role in
                            HStack {
                                Text(role.label)
                                    .font(tokens.bodySmall)
                                    .foregroundStyle(tokens.textPrimary)
                                Spacer()
                                ColorPicker(role.label, selection: colorBinding(role), supportsOpacity: true)
                                    .labelsHidden()
                                    .frame(width: 34, height: 30)
                                    .background(hoveredColorPicker == role ? tokens.hover : tokens.clear,
                                                in: RoundedRectangle(cornerRadius: 8))
                                    .popoverFocusRing(focusedControl == colorControl(role), tokens: tokens, radius: 8)
                                    .focusEffectDisabled()
                                    .focused($focusedControl, equals: colorControl(role))
                                    .accessibilityLabel(role.label + " zone color")
                                    .onHover { hoveredColorPicker = $0 ? role : nil }
                            }
                            .frame(minHeight: 32)
                            .padding(.trailing, 5)
                        }

                        HStack {
                            Spacer()
                            Button("Reset colors") { monitor.resetZoneColors() }
                                .buttonStyle(PopoverButtonStyle(tokens: tokens, kind: .text))
                                .popoverFocusRing(focusedControl == .resetColors, tokens: tokens, radius: 8)
                                .focused($focusedControl, equals: .resetColors)
                        }
                    }
                    .transition(reduceMotion ? .identity : .opacity)
                }
            }

            Rectangle()
                .fill(tokens.border)
                .frame(height: 1)

            HStack {
                (Text("Crossover ").font(tokens.caption) + Text(appVersion).font(tokens.mono))
                    .foregroundStyle(tokens.textDisabled)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(PopoverButtonStyle(tokens: tokens, kind: .text))
                    .popoverFocusRing(focusedControl == .quit, tokens: tokens, radius: 8)
                    .focused($focusedControl, equals: .quit)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(tokens.background)
        .focusEffectDisabled()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focusedControl = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { focusedControl = nil }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var reconnectMessage: String? {
        if monitor.logFormatUnrecognized { return "Log format not recognized" }
        if monitor.logStreamUnavailable { return "Log stream unavailable" }
        return switch monitor.reconnectStatus {
        case "[RECONNECTING...]": "Reconnecting…"
        case "[FAILED]": "Couldn’t reconnect"
        default: nil
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { monitor.launchAtLoginEnabled }, set: { monitor.setLaunchAtLogin($0) })
    }

    private func positionText(_ line: String) -> Text {
        guard let comma = line.range(of: ",", options: .backwards) else { return Text(line) }
        return Text(String(line[..<comma.upperBound])) + Text(String(line[comma.upperBound...])).font(tokens.mono)
    }

    private func colorControl(_ role: ZoneColorRole) -> PopoverControl {
        switch role {
        case .connected: .connectedColor
        case .disconnected: .disconnectedColor
        }
    }

    private func colorBinding(_ role: ZoneColorRole) -> Binding<Color> {
        Binding {
            switch role {
            case .connected: Color(monitor.zoneColors.connected.nsColor)
            case .disconnected: Color(monitor.zoneColors.disconnected.nsColor)
            }
        } set: { monitor.setZoneColor(role, color: NSColor($0)) }
    }
}

private struct PopoverToggle: View {
    let label: String
    @Binding var isOn: Bool
    let tokens: PopoverTokens
    let focused: Bool
    var enabled = true

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack {
                Text(label)
                    .font(tokens.bodySmall)
                    .foregroundStyle(tokens.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer()
                RoundedRectangle(cornerRadius: 10)
                    .fill(isOn ? tokens.actionBackground : tokens.border)
                    .frame(width: 36, height: 20)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(isOn ? tokens.actionText : tokens.mapSurface)
                            .frame(width: 14, height: 14)
                            .padding(3)
                    }
            }
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        }
        .buttonStyle(PopoverButtonStyle(tokens: tokens, kind: .row))
        .popoverFocusRing(focused, tokens: tokens, radius: 8)
        .focusEffectDisabled()
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
        .disabled(!enabled)
    }
}

private enum PopoverButtonKind: Equatable {
    case primary, row, text
}

private struct PopoverButtonStyle: ButtonStyle {
    let tokens: PopoverTokens
    let kind: PopoverButtonKind
    var pill = false

    func makeBody(configuration: Configuration) -> some View {
        PopoverButtonVisual(configuration: configuration, tokens: tokens, kind: kind, pill: pill)
    }
}

private struct PopoverButtonVisual: View {
    let configuration: ButtonStyle.Configuration
    let tokens: PopoverTokens
    let kind: PopoverButtonKind
    let pill: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    private var radius: CGFloat { kind == .primary || pill ? 21 : 8 }
    private var foreground: Color {
        guard isEnabled else { return tokens.textDisabled }
        return tokens.textPrimary
    }
    private var fill: Color {
        guard isEnabled else { return tokens.clear }
        if configuration.isPressed { return tokens.pressed }
        if hovered { return tokens.hover }
        return kind == .primary ? tokens.actionBackground : tokens.clear
    }

    var body: some View {
        configuration.label
            .font(kind == .primary ? tokens.body.weight(.medium) : tokens.bodySmall)
            .foregroundStyle(foreground)
            .padding(.horizontal, pill ? 22 : kind == .primary ? 14 : kind == .row ? 0 : 8)
            .frame(minHeight: kind == .primary ? 42 : 38)
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .stroke(kind == .primary || pill ? tokens.border : tokens.clear, lineWidth: 1))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .onHover { hovered = $0 }
    }
}

private extension View {
    func popoverFocusRing(_ focused: Bool, tokens: PopoverTokens, radius: CGFloat) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius)
            .stroke(focused ? tokens.focus : tokens.clear, lineWidth: 1)
            .padding(-2))
            .focusEffectDisabled()
    }
}
