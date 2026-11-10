import AppKit
import SwiftUI
import UserNotifications

enum ConnectionState: String, Equatable {
    case connected, disconnected, unknown
}

enum SessionSubstate: String, Equatable {
    case inUse = "in use", standby
}

struct PeerConnection: Equatable {
    let id: String
    let status: String
}

enum ScreenEdge: String, Equatable {
    case top, bottom, left, right

    var iPadDirection: String {
        switch self {
        case .top: "above"
        case .bottom: "below"
        case .left: "to the left"
        case .right: "to the right"
        }
    }

    var crossingAxis: String { self == .top || self == .bottom ? "left" : "top" }
}

struct IPadPosition: Equatable {
    let edge: ScreenEdge
    let displayUUID: String
}

enum ReconnectDecision: Equatable {
    case ignoreDisconnect, schedule(TimeInterval), reconnect, failed, disabled
}

func reconnectDecision(autoEnabled: Bool, configuredDevicesEmpty: Bool = false, attempts: Int, secondsSinceReconnect: TimeInterval?, timerExpired: Bool) -> ReconnectDecision {
    if let elapsed = secondsSinceReconnect, elapsed < 10 { return .ignoreDisconnect }
    guard autoEnabled, !configuredDevicesEmpty else { return .disabled }
    let backoff: [TimeInterval] = [15, 30, 60]
    guard (0..<backoff.count).contains(attempts) else { return .failed }
    return timerExpired ? .reconnect : .schedule(backoff[attempts])
}

enum ConnectionEvent: Equatable {
    case connections([PeerConnection]?, connectedSignal: Bool), configuredDevices([String])
    case peerInUse, peerStandby, deviceLost, sourceChanged, config(IPadPosition?), layout([DisplayLayoutEntry])
}

let realDropPattern = "[com.apple.universalcontrol:CONN] Disconnected"

func stateAfter(_ connections: [PeerConnection], current: ConnectionState) -> ConnectionState {
    if connections.contains(where: { $0.status == "connected" }) { return .connected }
    return connections.isEmpty ? .disconnected : current
}

func stateAfter(_ event: ConnectionEvent, current: ConnectionState) -> ConnectionState {
    guard case .connections(let peers, _) = event, let peers else { return current }
    return stateAfter(peers, current: current)
}

func sessionSubstateAfter(_ event: ConnectionEvent, state: ConnectionState) -> SessionSubstate? {
    guard state == .connected else { return nil }
    switch event {
    case .peerInUse: return .inUse
    case .peerStandby, .sourceChanged: return .standby
    default: return nil
    }
}

func shouldNotify(previous: ConnectionState, next: ConnectionState, replay: Bool = false) -> Bool {
    !replay && ((previous == .connected && next == .disconnected) || (previous == .disconnected && next == .connected))
}

func shouldNotifyReconnect(pending: Bool, event: ConnectionEvent) -> Bool {
    guard pending, case .connections(let peers, let connectedSignal) = event, connectedSignal else { return false }
    return peers?.contains(where: { $0.status == "connected" }) ?? false
}

private let logTimestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return formatter
}()

func parseLogTimestamp(_ line: String) -> Date? {
    guard line.count >= 23 else { return nil }
    return logTimestampFormatter.date(from: String(line.prefix(23)))
}

func replayThenBuffered<T>(_ replay: [T], _ buffered: [T]) -> [T] { replay + buffered }

func parsePosition(_ line: String) -> IPadPosition? {
    let pattern = #"([A-Fa-f0-9]+):([A-Fa-f0-9-]+)/((?:top|bottom|left|right))@[0-9.]+=((?:top|bottom|left|right))@[0-9.]+/([A-Fa-f0-9]+):([A-Fa-f0-9-]+)"#
    guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
    let endpoints = line[range].split(separator: "=")
    guard endpoints.count == 2 else { return nil }
    let left = endpoints[0].split(separator: "/")
    let right = endpoints[1].split(separator: "/")
    guard left.count == 2, right.count == 2 else { return nil }
    let leftDevice = left[0].split(separator: ":", maxSplits: 1)
    let rightDevice = right[1].split(separator: ":", maxSplits: 1)
    let leftEdge = left[1].split(separator: "@")[0]
    let rightEdge = right[0].split(separator: "@")[0]
    if leftDevice.count == 2, leftDevice[1] == zeroDisplayUUID,
       rightDevice.count == 2, let edge = ScreenEdge(rawValue: String(rightEdge)) {
        return IPadPosition(edge: edge, displayUUID: String(rightDevice[1]).uppercased())
    }
    if rightDevice.count == 2, rightDevice[1] == zeroDisplayUUID,
       leftDevice.count == 2, let edge = ScreenEdge(rawValue: String(leftEdge)) {
        return IPadPosition(edge: edge, displayUUID: String(leftDevice[1]).uppercased())
    }
    return nil
}

func parseEvents(_ line: String) -> [ConnectionEvent] {
    var events: [ConnectionEvent] = []
    if line.contains("[com.apple.universalcontrol:CONN]") && line.contains("Connected, update connections:") {
        events.append(.connections(parseConnections(line), connectedSignal: true))
    } else if line.contains(realDropPattern) {
        events.append(.connections(parseConnections(line), connectedSignal: false))
    } else if line.contains("[com.apple.universalcontrol:SYNC] Configured Devices:") {
        events.append(.configuredDevices(parseDeviceList(line, after: "Configured Devices:")))
    } else if line.contains("[com.apple.universalcontrol:LINK]") && line.contains("Device Lost SF") {
        events.append(.deviceLost)
    } else if line.contains("[com.apple.universalcontrol:PEER]") && line.contains("Connection Ready") {
        events.append(.peerInUse)
    } else if line.contains("Deactivating due to idle timeout") || line.contains("Perform disconnect for system state transition") {
        events.append(.peerStandby)
    } else if line.contains("Current Source Device:") && line.contains(" -> nil") {
        events.append(.sourceChanged)
    }
    if line.contains("displayLayout:"), let layout = parseDisplayLayout(line) { events.append(.layout(layout)) }
    if line.contains("config:") { events.append(.config(parsePosition(line))) }
    return events
}

func parseEvent(_ line: String) -> ConnectionEvent? { parseEvents(line).first }

func parseConnections(_ line: String) -> [PeerConnection]? {
    guard let arrow = line.range(of: "->"),
          let open = line[arrow.upperBound...].firstIndex(of: "["),
          let close = line[line.index(after: open)...].firstIndex(of: "]") else { return nil }
    let list = line[line.index(after: open)..<close]
    guard !list.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
    let regex = try! NSRegularExpression(pattern: #"([A-Fa-f0-9]+)\s+\((connected|connecting|disconnecting)\)"#)
    let nsList = String(list) as NSString
    let matches = regex.matches(in: String(list), range: NSRange(location: 0, length: nsList.length))
    guard !matches.isEmpty else { return nil }
    return matches.map {
        PeerConnection(id: nsList.substring(with: $0.range(at: 1)), status: nsList.substring(with: $0.range(at: 2)))
    }
}

func parseDeviceList(_ line: String, after label: String) -> [String] {
    guard let labelRange = line.range(of: label),
          let open = line[labelRange.upperBound...].firstIndex(of: "["),
          let close = line[line.index(after: open)...].firstIndex(of: "]") else { return [] }
    return line[line.index(after: open)..<close].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
}

private func selfCheckFailure(_ name: String) -> Never {
    fputs("self-check failed: \(name)\n", stderr)
    exit(1)
}

private func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if !condition() { selfCheckFailure(name) }
}

private func checked<T>(_ name: String, _ value: T?) -> T {
    guard let value else { selfCheckFailure(name) }
    return value
}

func parserSelfCheck() {
    let connected = "2026-11-10 13:15:32.584 Df UniversalControl[5587:d30ae4] [com.apple.universalcontrol:CONN] Connected, update connections: [0D685417 (connecting)] -> [0D685417 (connected)]"
    let disconnected = "2026-11-10 13:17:32.489 Df UniversalControl[5587:d30ae4] [com.apple.universalcontrol:CONN] Disconnected 0D685417, update connections: [0D685417 (disconnecting)] -> []"
    let anotherPeerConnected = "[com.apple.universalcontrol:CONN] Disconnected 0D685417, update connections: [0D685417 (connected), 55283570 (connected)] -> [0D685417 (disconnecting), 55283570 (connected)]"
    let configuredEmpty = "2026-11-10 13:22:36.436 Df UniversalControl[5587:d30ae4] [com.apple.universalcontrol:SYNC] Configured Devices: []"
    let deviceLost = "2026-11-10 13:19:52.004 Df UniversalControl[5587:d30ae4] [com.apple.universalcontrol:LINK] IDS 0D685417: Device Lost SF <iWiFi DuetSync SharedHome Touch Owner ContextCollector MeDeviceIsMe>"
    let idle = "2026-11-10 13:11:43.786 Df UniversalControl[5587:d30ae4] [com.apple.universalcontrol:PEER] P2P 0D685417/7A95: Deactivating due to idle timeout"
    let config = "config: [V: '[0D685417:00000000-0000-0000-0000-000000000000/top@0.50=bottom@0.20/55283570:83C79C5D-BB83-4577-8946-1870855150FB]']"
    let reversedConfig = "config: [V: '[55283570:83C79C5D-BB83-4577-8946-1870855150FB/bottom@0.20=top@0.50/0D685417:00000000-0000-0000-0000-000000000000]']"
    let layoutLine = "displayLayout: [V: '[0D685417:00000000-0000-0000-0000-000000000000: CGRect(0.0, 0.0, 1210.0, 834.0),55283570:37D8832A-2D66-02CA-B9F7-8F30A301B230: CGRect(1766.0, 0.0, 1512.0, 982.0),55283570:833B132E-542B-4367-8A60-67C7D42B8003: CGRect(-1697.0, -1080.0, 1920.0, 1080.0),55283570:83C79C5D-BB83-4577-8946-1870855150FB: CGRect(223.0, -1080.0, 1920.0, 1080.0))](v2)']"
    let connectedEvent = checked("parse CONN connected", parseEvent(connected))
    check("CONN connected peers", connectedEvent == .connections([PeerConnection(id: "0D685417", status: "connected")], connectedSignal: true))
    check("CONN connected state", stateAfter(connectedEvent, current: .unknown) == .connected)
    let disconnectedEvent = checked("parse CONN disconnected", parseEvent(disconnected))
    check("CONN disconnected state", stateAfter(disconnectedEvent, current: .connected) == .disconnected)
    check("disconnect does not confirm reconnect", !shouldNotifyReconnect(pending: true, event: disconnectedEvent))
    check("disconnect notification decision", shouldNotify(previous: .connected, next: .disconnected))
    check("replay suppresses notification", !shouldNotify(previous: .connected, next: .disconnected, replay: true))
    let multiPeerEvent = checked("parse multi-peer connection", parseEvent(anotherPeerConnected))
    check("remaining connected peer", stateAfter(multiPeerEvent, current: .connected) == .connected)
    let configuredEvent = checked("parse Configured Devices empty", parseEvent(configuredEmpty))
    check("configured empty event", configuredEvent == .configuredDevices([]))
    check("configured empty leaves state", stateAfter(configuredEvent, current: .disconnected) == .disconnected)
    check("configured empty disables reconnect", reconnectDecision(autoEnabled: true, configuredDevicesEmpty: true, attempts: 0, secondsSinceReconnect: nil, timerExpired: false) == .disabled)
    let lostEvent = checked("parse Device Lost", parseEvent(deviceLost))
    check("Device Lost event", lostEvent == .deviceLost)
    check("Device Lost leaves state", stateAfter(lostEvent, current: .connected) == .connected)
    let idleEvent = checked("parse PEER idle", parseEvent(idle))
    check("PEER idle event", idleEvent == .peerStandby)
    check("PEER idle leaves main state", stateAfter(idleEvent, current: .connected) == .connected)
    check("PEER idle connected substate", sessionSubstateAfter(idleEvent, state: .connected) == .standby)
    check("PEER idle disconnected substate", sessionSubstateAfter(idleEvent, state: .disconnected) == nil)
    check("PEER ready does not confirm reconnect", !shouldNotifyReconnect(pending: true, event: .peerInUse))
    let configEvent = checked("parse config forward", parseEvent(config))
    let expectedPosition = IPadPosition(edge: .bottom, displayUUID: "83C79C5D-BB83-4577-8946-1870855150FB")
    check("config forward direction", configEvent == .config(expectedPosition))
    check("config reversed direction", parseEvent(reversedConfig) == .config(expectedPosition))
    check("config leaves state", stateAfter(configEvent, current: .connected) == .connected)
    let layoutEvent = checked("parse combined display layout", parseEvent(layoutLine))
    guard case .layout(let layout) = layoutEvent else { selfCheckFailure("combined display layout event") }
    let crossing = segments(layout)
    check("crossing segment count", crossing.count == 2)
    let u2414h = checked("U2414H crossing segment", crossing.first { $0.displayUUID == "83C79C5D-BB83-4577-8946-1870855150FB" })
    check("U2414H crossing start", u2414h.edge == .bottom && abs(u2414h.startFraction) < 0.001)
    check("U2414H crossing end", abs(u2414h.endFraction - (987.0 / 1920.0)) < 0.001)
    let p2425h = checked("P2425H crossing segment", crossing.first { $0.displayUUID == "833B132E-542B-4367-8A60-67C7D42B8003" })
    check("P2425H crossing start", p2425h.edge == .bottom && abs(p2425h.startFraction - (1697.0 / 1920.0)) < 0.001)
    check("P2425H crossing end", abs(p2425h.endFraction - 1.0) < 0.001)
    check("buffer drain ordering", replayThenBuffered(["history-1", "history-2"], ["live-1", "live-2"]) == ["history-1", "history-2", "live-1", "live-2"])
    let timestamp = checked("parse log timestamp", parseLogTimestamp(connected))
    check("log timestamp value", logTimestampFormatter.string(from: timestamp) == "2026-11-10 13:15:32.584")
    check("invalid log timestamp", parseLogTimestamp("not a log line") == nil)
    check("unrelated log ignored", parseEvent("unrelated log line") == nil)
    check("reconnect grace", reconnectDecision(autoEnabled: true, attempts: 0, secondsSinceReconnect: 5, timerExpired: false) == .ignoreDisconnect)
    check("reconnect attempt limit", reconnectDecision(autoEnabled: true, attempts: 3, secondsSinceReconnect: nil, timerExpired: true) == .failed)
}

@MainActor
final class ConnectionMonitor: ObservableObject {
    @Published private(set) var state: ConnectionState = .unknown
    @Published private(set) var changedAt: Date?
    @Published private(set) var iPadPosition: IPadPosition?
    @Published private(set) var sessionSubstate: SessionSubstate?
    @Published private(set) var configuredDevicesEmpty = false
    @Published var showCrossingZone: Bool = UserDefaults.standard.object(forKey: "showCrossingZone") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showCrossingZone, forKey: "showCrossingZone")
            updateOverlay()
        }
    }
    @Published var autoReconnectEnabled: Bool = UserDefaults.standard.object(forKey: "autoReconnectEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoReconnectEnabled, forKey: "autoReconnectEnabled")
            if autoReconnectEnabled {
                autoReconnectAttempts = 0
                if state == .disconnected { beginAutoReconnect() }
            }
            else { autoReconnectTask?.cancel(); autoReconnectTask = nil }
        }
    }
    private var process: Process?
    private var pendingOutput = ""
    private var replayingHistory = true
    private var bufferedLiveLines: [String] = []
    private var autoReconnectTask: Task<Void, Never>?
    private var autoReconnectAttempts = 0
    private var lastReconnectAt: Date?
    private var reconnectPending = false
    private var reconnectTimeoutTask: Task<Void, Never>?
    @Published private(set) var crossingSegments: [CrossingSegment] = []
    private let overlay = OverlayController()
    private var screenObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        if let savedState = defaults.string(forKey: "lastConnectionState").flatMap(ConnectionState.init(rawValue:)) {
            state = savedState
            sessionSubstate = savedState == .connected ? .standby : nil
        }
        if defaults.object(forKey: "lastConfiguredDevicesEmpty") != nil {
            configuredDevicesEmpty = defaults.bool(forKey: "lastConfiguredDevicesEmpty")
        }
        if let line = defaults.string(forKey: "lastCombinedLayoutLine") { processLine(line, replay: true) }
        if let line = defaults.string(forKey: "lastConfigLine") { processLine(line, replay: true) }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateOverlay() }
        }
        updateOverlay()
        start()
        recoverHistory()
    }

    private func recoverHistory() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = ["show", "--last", "6h", "--style", "compact", "--predicate", "subsystem == \"com.apple.universalcontrol\""]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var output = ""
            if (try? process.run()) != nil {
                output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let historyLines = output.split(whereSeparator: \.isNewline).map(String.init)
                for line in historyLines { self.processLine(line, replay: true) }
                if self.state == .disconnected, !self.configuredDevicesEmpty { self.beginAutoReconnect() }
                let buffered = self.bufferedLiveLines
                self.bufferedLiveLines.removeAll()
                self.replayingHistory = false
                for line in buffered { self.processLine(line, replay: false) }
                self.updateOverlay()
            }
        }
    }

    func start() {
        pendingOutput = ""
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "compact", "--predicate", "subsystem == \"com.apple.universalcontrol\""]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        self.process = process

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let output = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.consumeLiveOutput(output)
            }
        }
        process.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            let leftover = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !leftover.isEmpty { self.consumeLiveOutput(leftover, flush: true) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.start() }
            }
        }
        do { try process.run() } catch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.start() }
        }
    }

    private func consumeLiveOutput(_ output: String, flush: Bool = false) {
        let lines = (pendingOutput + output).split(separator: "\n", omittingEmptySubsequences: false)
        pendingOutput = flush ? "" : String(lines.last ?? "")
        let completeLines = flush ? lines[...] : lines.dropLast()
        for line in completeLines {
            let line = String(line)
            if replayingHistory { bufferedLiveLines.append(line) }
            else { processLine(line, replay: false) }
        }
    }

    private func processLine(_ line: String, replay: Bool) {
        let timestamp = replay ? parseLogTimestamp(line) : nil
        for event in parseEvents(line) {
            switch event {
            case .connections(let peers, _):
                guard let peers else { continue }
                let next = stateAfter(peers, current: state)
                if next == .disconnected {
                    handleDisconnect(replay: replay, timestamp: timestamp)
                } else if next == .connected {
                    let wasReconnecting = shouldNotifyReconnect(pending: reconnectPending, event: event)
                    let previous = state
                    reconnectPending = false
                    reconnectTimeoutTask?.cancel()
                    reconnectTimeoutTask = nil
                    update(to: .connected, replay: replay, timestamp: timestamp)
                    if !replay, wasReconnecting && previous == .connected { notify("Universal Control reconnected") }
                }
            case .configuredDevices(let devices):
                configuredDevicesEmpty = devices.isEmpty
                UserDefaults.standard.set(configuredDevicesEmpty, forKey: "lastConfiguredDevicesEmpty")
                if !replay { updateOverlay() }
                if configuredDevicesEmpty, !replay {
                    autoReconnectTask?.cancel()
                    autoReconnectTask = nil
                    reconnectTimeoutTask?.cancel()
                    reconnectTimeoutTask = nil
                    reconnectPending = false
                    lastReconnectAt = nil
                } else if !replay, state == .disconnected {
                    beginAutoReconnect()
                }
            case .peerInUse:
                if state == .connected {
                    sessionSubstate = .inUse
                    if !replay { updateOverlay() }
                }
            case .peerStandby, .sourceChanged:
                if let substate = sessionSubstateAfter(event, state: state) {
                    sessionSubstate = substate
                    if !replay { updateOverlay() }
                }
            case .deviceLost: break
            case .config(let position):
                if let position {
                    iPadPosition = position
                    UserDefaults.standard.set(line, forKey: "lastConfigLine")
                }
            case .layout(let layout):
                crossingSegments = segments(layout)
                UserDefaults.standard.set(line, forKey: "lastCombinedLayoutLine")
                if !replay { updateOverlay() }
            }
        }
    }

    private func update(to next: ConnectionState, replay: Bool = false, timestamp: Date? = nil) {
        guard next != state else { return }
        let previous = state
        state = next
        UserDefaults.standard.set(next.rawValue, forKey: "lastConnectionState")
        if replay { changedAt = timestamp ?? changedAt }
        else { changedAt = Date() }
        if next == .connected {
            if previous != .connected { sessionSubstate = .standby }
        } else {
            sessionSubstate = nil
        }
        if !replay { updateOverlay() }
        if next == .disconnected, !replay {
            autoReconnectAttempts = 0
            beginAutoReconnect()
        } else if next == .connected, !replay {
            autoReconnectTask?.cancel()
            autoReconnectTask = nil
            autoReconnectAttempts = 0
        }
        guard shouldNotify(previous: previous, next: next, replay: replay) else { return }
        notify(next == .connected ? "Universal Control reconnected" : configuredDevicesEmpty ? "Universal Control turned off" : "Universal Control disconnected")
    }

    func reconnectNow() {
        reconnect()
    }

    private func handleDisconnect(replay: Bool = false, timestamp: Date? = nil) {
        if replay {
            update(to: .disconnected, replay: true, timestamp: timestamp)
            return
        }
        let elapsed = lastReconnectAt.map { Date().timeIntervalSince($0) }
        if reconnectDecision(autoEnabled: autoReconnectEnabled, configuredDevicesEmpty: configuredDevicesEmpty, attempts: autoReconnectAttempts, secondsSinceReconnect: elapsed, timerExpired: false) == .ignoreDisconnect { return }
        update(to: .disconnected)
    }

    private func notify(_ title: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func updateOverlay() {
        overlay.update(segments: crossingSegments, state: state, session: sessionSubstate,
                       enabled: showCrossingZone, universalControlOff: configuredDevicesEmpty)
    }

    var positionDescription: String {
        if !crossingSegments.isEmpty {
            return crossingSegments.sorted { $0.startFraction < $1.startFraction }.map(\.description).joined(separator: ", ")
        }
        return iPadPosition?.description ?? "Unknown"
    }

    private func reconnect() {
        reconnectPending = true
        lastReconnectAt = Date()
        reconnectTimeoutTask?.cancel()
        reconnectTimeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, reconnectPending else { return }
            reconnectPending = false
            reconnectTimeoutTask = nil
            update(to: .disconnected)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-KILL", "UniversalControl"]
        try? process.run()
    }

    private func beginAutoReconnect() {
        guard autoReconnectEnabled, !configuredDevicesEmpty, state == .disconnected else { return }
        guard autoReconnectTask == nil else { return }
        let decision = reconnectDecision(autoEnabled: autoReconnectEnabled, configuredDevicesEmpty: configuredDevicesEmpty, attempts: autoReconnectAttempts, secondsSinceReconnect: nil, timerExpired: false)
        if case .schedule(let delay) = decision { scheduleAutoReconnect(after: delay) }
    }

    private func scheduleAutoReconnect(after delay: TimeInterval) {
        autoReconnectTask?.cancel()
        autoReconnectTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, autoReconnectEnabled, !configuredDevicesEmpty, state == .disconnected else { return }
            let elapsed = lastReconnectAt.map { Date().timeIntervalSince($0) }
            switch reconnectDecision(autoEnabled: autoReconnectEnabled, configuredDevicesEmpty: configuredDevicesEmpty, attempts: autoReconnectAttempts, secondsSinceReconnect: elapsed, timerExpired: true) {
            case .ignoreDisconnect:
                scheduleAutoReconnect(after: max(0.1, 10 - (elapsed ?? 0)))
            case .reconnect:
                autoReconnectAttempts += 1
                reconnect()
                if autoReconnectAttempts < 3 {
                    let next = reconnectDecision(autoEnabled: autoReconnectEnabled, configuredDevicesEmpty: configuredDevicesEmpty, attempts: autoReconnectAttempts, secondsSinceReconnect: nil, timerExpired: false)
                    if case .schedule(let nextDelay) = next { scheduleAutoReconnect(after: nextDelay) }
                } else {
                    scheduleAutoReconnect(after: 10)
                }
            case .failed:
                autoReconnectTask = nil
                reconnectPending = false
                notify("Universal Control auto-reconnect failed")
            case .disabled, .schedule:
                autoReconnectTask = nil
            }
        }
    }
}

@main
struct UniversalControlHelperApp: App {
    @StateObject private var monitor: ConnectionMonitor

    init() {
        if CommandLine.arguments.contains("--self-check") {
            parserSelfCheck()
            exit(0)
        }
        _monitor = StateObject(wrappedValue: ConnectionMonitor())
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        MenuBarExtra("UC \(monitor.state.rawValue.capitalized)", systemImage: monitor.state == .connected ? "link" : "link.slash") {
            Text("State: \(monitor.state.rawValue.capitalized)")
            if monitor.state == .connected {
                Text("Session: \(monitor.sessionSubstate?.rawValue ?? "standby")")
            }
            Text("Last change: \(monitor.changedAt?.formatted(date: .abbreviated, time: .standard) ?? "Never")")
            Text("iPad position: \(monitor.positionDescription)")
            if monitor.configuredDevicesEmpty { Text("Universal Control off (in settings?)") }
            Divider()
            Button("Reconnect now") { monitor.reconnectNow() }
            Toggle("Auto-reconnect", isOn: $monitor.autoReconnectEnabled)
            Toggle("Show crossing zone", isOn: $monitor.showCrossingZone)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.window)
    }
}
