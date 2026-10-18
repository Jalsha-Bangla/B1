import SwiftUI
import Network
import Security
import Combine
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var remote: BluetoothRemoteManager
    @StateObject private var maintenance = MaintenanceManager()

    var body: some View {
        TabView {
            RemoteControlView()
                .environmentObject(remote)
                .tabItem {
                    Label("Remote", systemImage: "remote")
                }

            MaintenanceView(manager: maintenance)
                .tabItem {
                    Label("Maintenance", systemImage: "wrench.and.screwdriver")
                }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
    }
}

// MARK: - Remote

private struct RemoteControlView: View {
    @EnvironmentObject private var remote: BluetoothRemoteManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("B1 Remote")
                            .font(.largeTitle.bold())
                        Text("Bluetooth • Wi-Fi not required")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        remote.reconnect()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.title2.bold())
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(RemoteSquareButtonStyle())
                }

                HStack(spacing: 12) {
                    Circle()
                        .fill(remote.isReady ? Color.green : Color.orange)
                        .frame(width: 12, height: 12)

                    Text(remote.statusText)
                        .font(.headline)

                    Spacer()
                }
                .padding()
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))

                dpad

                HStack(spacing: 12) {
                    commandButton("Back", icon: "arrow.uturn.backward", command: "BACK")
                    commandButton("Home", icon: "house.fill", command: "HOME")
                    commandButton("Play", icon: "playpause.fill", command: "PLAY_PAUSE")
                }

                HStack(spacing: 12) {
                    commandButton("Volume −", icon: "speaker.minus.fill", command: "VOL_DOWN")
                    commandButton("Volume +", icon: "speaker.plus.fill", command: "VOL_UP")
                }
            }
            .padding(20)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var dpad: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 300, height: 300)

            VStack(spacing: 42) {
                dpadButton("chevron.up", "UP")

                HStack(spacing: 42) {
                    dpadButton("chevron.left", "LEFT")

                    Button {
                        remote.send("OK")
                    } label: {
                        Text("OK")
                            .font(.title2.bold())
                            .frame(width: 88, height: 88)
                    }
                    .buttonStyle(RemoteRoundButtonStyle())

                    dpadButton("chevron.right", "RIGHT")
                }

                dpadButton("chevron.down", "DOWN")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func dpadButton(_ icon: String, _ command: String) -> some View {
        Button {
            remote.send(command)
        } label: {
            Image(systemName: icon)
                .font(.title.bold())
                .frame(width: 72, height: 72)
        }
        .buttonStyle(RemoteRoundButtonStyle())
    }

    private func commandButton(_ title: String, icon: String, command: String) -> some View {
        Button {
            remote.send(command)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
        }
        .buttonStyle(RemoteSquareButtonStyle())
    }
}

private struct RemoteSquareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                configuration.isPressed ? .white.opacity(0.18) : .white.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct RemoteRoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                configuration.isPressed ? .white.opacity(0.20) : .white.opacity(0.11),
                in: Circle()
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

// MARK: - Maintenance UI

private struct MaintenanceView: View {
    @ObservedObject var manager: MaintenanceManager
    @State private var showAPKPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    connectionCard
                    quickActions
                    shellCard
                    apkCard
                    outputCard
                }
                .padding()
            }
            .navigationTitle("Maintenance")
            .background(Color.black.ignoresSafeArea())
        }
        .fileImporter(
            isPresented: $showAPKPicker,
            allowedContentTypes: [UTType(filenameExtension: "apk") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await manager.installAPK(from: url) }
            case .failure(let error):
                manager.setOutput("APK picker error: " + error.localizedDescription)
            }
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("ADB over local Wi-Fi", systemImage: "network")
                .font(.headline)

            Text("B1 Developer options + USB debugging must be ON. Default port: 5555.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("B1 IP address, e.g. 192.168.68.108", text: $manager.host)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            HStack {
                Circle()
                    .fill(manager.isConnected ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)

                Text(manager.status)
                    .font(.subheadline.weight(.semibold))

                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    Task { await manager.connect() }
                } label: {
                    Label(manager.isConnected ? "Reconnect" : "Connect", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.busy || manager.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    manager.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!manager.isConnected)
            }
        }
        .maintenanceCard()
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 10) {
                quickButton("Enter", "return", "input keyevent 66")
                quickButton("Home", "house", "input keyevent 3")
                quickButton("Back", "arrow.uturn.backward", "input keyevent 4")
            }

            HStack(spacing: 10) {
                quickButton("Up", "chevron.up", "input keyevent 19")
                quickButton("Down", "chevron.down", "input keyevent 20")
                quickButton("Left", "chevron.left", "input keyevent 21")
                quickButton("Right", "chevron.right", "input keyevent 22")
            }

            Button {
                Task { await manager.restartReceiver() }
            } label: {
                Label("Restart B1 BLE Receiver", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!manager.isConnected || manager.busy)

            Button {
                Task { await manager.receiverHealth() }
            } label: {
                Label("Receiver Health Check", systemImage: "heart.text.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!manager.isConnected || manager.busy)
        }
        .maintenanceCard()
    }

    private func quickButton(_ title: String, _ icon: String, _ command: String) -> some View {
        Button {
            Task { await manager.runShell(command) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
        }
        .buttonStyle(.bordered)
        .disabled(!manager.isConnected || manager.busy)
    }

    private var shellCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shell")
                .font(.headline)

            TextField("Command", text: $manager.shellCommand)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button {
                    Task { await manager.runCurrentShell() }
                } label: {
                    Label("Run", systemImage: "terminal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!manager.isConnected || manager.busy || manager.shellCommand.isEmpty)

                Button {
                    Task { await manager.readLogs() }
                } label: {
                    Label("Logs", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!manager.isConnected || manager.busy)
            }
        }
        .maintenanceCard()
    }

    private var apkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("APK Update")
                .font(.headline)

            Text("Select a trusted APK from Files. It is copied to /data/local/tmp and installed with pm install -r.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                showAPKPicker = true
            } label: {
                Label("Select APK & Install", systemImage: "shippingbox.and.arrow.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!manager.isConnected || manager.busy)
        }
        .maintenanceCard()
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Output")
                    .font(.headline)
                Spacer()
                if manager.busy {
                    ProgressView()
                }
                Button("Clear") {
                    manager.setOutput("")
                }
                .font(.caption)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(manager.output.isEmpty ? "No output yet." : manager.output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 150, maxHeight: 320)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        }
        .maintenanceCard()
    }
}

private extension View {
    func maintenanceCard() -> some View {
        self
            .padding()
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Maintenance Manager

@MainActor
final class MaintenanceManager: ObservableObject {
    @Published var host: String = UserDefaults.standard.string(forKey: "B1ADBHost") ?? ""
    @Published var status = "Not connected"
    @Published var isConnected = false
    @Published var busy = false
    @Published var output = ""
    @Published var shellCommand = "getprop ro.product.model"

    private var client: ADBClient?

    func setOutput(_ value: String) {
        output = value
    }

    func connect() async {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = "Enter B1 IP address"
            return
        }

        busy = true
        isConnected = false
        status = "Connecting to " + trimmed + ":5555…"
        output = ""

        do {
            let newClient = ADBClient(host: trimmed, port: 5555) { [weak self] message in
                Task { @MainActor in
                    self?.status = message
                }
            }
            try await newClient.connect()
            client = newClient
            UserDefaults.standard.set(trimmed, forKey: "B1ADBHost")
            isConnected = true
            status = "ADB Connected"
            let identity = try await newClient.shell("getprop ro.product.model; getprop ro.product.manufacturer; getprop ro.product.device")
            output = "Connected to B1\n\n" + identity
        } catch {
            client = nil
            isConnected = false
            status = "ADB connection failed"
            output = error.localizedDescription
        }

        busy = false
    }

    func disconnect() {
        client?.disconnect()
        client = nil
        isConnected = false
        busy = false
        status = "Not connected"
    }

    func runCurrentShell() async {
        await runShell(shellCommand)
    }

    func runShell(_ command: String) async {
        guard let client else {
            output = "ADB is not connected."
            return
        }

        busy = true
        do {
            let result = try await client.shell(command)
            output = "$ " + command + "\n\n" + (result.isEmpty ? "(no output)" : result)
            status = "ADB Connected"
        } catch {
            output = "Shell error:\n" + error.localizedDescription
            status = "ADB command failed"
            isConnected = false
        }
        busy = false
    }

    func restartReceiver() async {
        let command = """
        am stopservice -n com.fks.b1remote/.BleRemoteService >/dev/null 2>&1
        sleep 1
        am start-foreground-service -n com.fks.b1remote/.BleRemoteService
        """
        await runShell(command)
    }

    func receiverHealth() async {
        let command = """
        echo '=== PACKAGE ==='
        dumpsys package com.fks.b1remote | grep -E 'versionName|versionCode' | head -8
        echo '=== SERVICES ==='
        dumpsys activity services com.fks.b1remote | head -100
        echo '=== ACCESSIBILITY ==='
        settings get secure enabled_accessibility_services
        settings get secure accessibility_enabled
        """
        await runShell(command)
    }

    func readLogs() async {
        await runShell("logcat -d -t 250")
    }

    func installAPK(from url: URL) async {
        guard let client else {
            output = "ADB is not connected."
            return
        }

        busy = true
        status = "Reading APK…"

        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard !data.isEmpty else {
                throw ADBError.protocolError("Selected APK is empty.")
            }

            status = "Uploading APK…"
            output = "Uploading " + url.lastPathComponent + " (" + ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file) + ")…"

            let result = try await client.installAPK(data: data)
            output = result
            status = result.localizedCaseInsensitiveContains("success") ? "APK update complete" : "APK installer returned output"
        } catch {
            output = "APK install error:\n" + error.localizedDescription
            status = "APK install failed"
        }

        busy = false
    }
}

// MARK: - ADB Client

private enum ADBError: LocalizedError {
    case invalidAddress
    case disconnected
    case protocolError(String)
    case authentication(String)
    case security(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Invalid B1 IP address or port."
        case .disconnected:
            return "ADB connection closed."
        case .protocolError(let message):
            return "ADB protocol error: " + message
        case .authentication(let message):
            return "ADB authentication: " + message
        case .security(let message):
            return "ADB key error: " + message
        }
    }
}

private final class ADBClient {
    private static let commandCNXN: UInt32 = 0x4E584E43
    private static let commandAUTH: UInt32 = 0x48545541
    private static let commandOPEN: UInt32 = 0x4E45504F
    private static let commandOKAY: UInt32 = 0x59414B4F
    private static let commandCLSE: UInt32 = 0x45534C43
    private static let commandWRTE: UInt32 = 0x45545257

    private let host: String
    private let port: UInt16
    private let queue = DispatchQueue(label: "com.fks.b1remote.adb")
    private let keyStore = ADBKeyStore()
    private let statusHandler: (String) -> Void

    private var connection: NWConnection?
    private var nextLocalID: UInt32 = 1
    private var maxPayload = 4096

    init(host: String, port: UInt16, statusHandler: @escaping (String) -> Void) {
        self.host = host
        self.port = port
        self.statusHandler = statusHandler
    }

    func connect() async throws {
        disconnect()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ADBError.invalidAddress
        }

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connection = conn

        try await withCheckedThrowingContinuation { continuation in
            var completed = false

            conn.stateUpdateHandler = { state in
                guard !completed else { return }

                switch state {
                case .ready:
                    completed = true
                    continuation.resume()
                case .failed(let error):
                    completed = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    completed = true
                    continuation.resume(throwing: ADBError.disconnected)
                default:
                    break
                }
            }

            conn.start(queue: queue)
        }

        statusHandler("ADB socket connected — authenticating…")

        try await sendMessage(
            command: Self.commandCNXN,
            arg0: 0x01000000,
            arg1: 4096,
            payload: Data("host::\0".utf8)
        )

        var sentSignature = false
        var sentPublicKey = false

        while true {
            let message = try await readMessage()

            switch message.command {
            case Self.commandCNXN:
                if message.arg1 > 0 {
                    maxPayload = max(1024, min(Int(message.arg1), 1024 * 1024))
                }
                statusHandler("ADB Connected")
                return

            case Self.commandAUTH:
                guard message.arg0 == 1 else {
                    throw ADBError.authentication("Unsupported AUTH type " + String(message.arg0))
                }

                if !sentSignature {
                    let signature = try keyStore.signADBToken(message.payload)
                    try await sendMessage(
                        command: Self.commandAUTH,
                        arg0: 2,
                        arg1: 0,
                        payload: signature
                    )
                    sentSignature = true
                } else if !sentPublicKey {
                    let publicKey = try keyStore.adbPublicKeyPayload()
                    try await sendMessage(
                        command: Self.commandAUTH,
                        arg0: 3,
                        arg1: 0,
                        payload: publicKey
                    )
                    sentPublicKey = true
                    statusHandler("On B1: Allow USB debugging, then tap OK")
                } else {
                    throw ADBError.authentication("B1 did not accept this iPhone ADB key.")
                }

            default:
                break
            }
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    func shell(_ command: String) async throws -> String {
        let stream = try await openStream(service: "shell:" + command)
        var output = Data()

        while true {
            let message = try await readMessage()

            if message.command == Self.commandWRTE,
               message.arg0 == stream.remoteID,
               message.arg1 == stream.localID {
                output.append(message.payload)
                try await sendMessage(
                    command: Self.commandOKAY,
                    arg0: stream.localID,
                    arg1: stream.remoteID,
                    payload: Data()
                )
            } else if message.command == Self.commandCLSE,
                      message.arg0 == stream.remoteID,
                      message.arg1 == stream.localID {
                try await sendMessage(
                    command: Self.commandCLSE,
                    arg0: stream.localID,
                    arg1: stream.remoteID,
                    payload: Data()
                )
                break
            }
        }

        return String(data: output, encoding: .utf8) ?? output.base64EncodedString()
    }

    func installAPK(data: Data) async throws -> String {
        let remotePath = "/data/local/tmp/B1RemoteUpdate.apk"
        try await uploadUsingCat(data: data, remotePath: remotePath)

        let installResult = try await shell("pm install -r '" + remotePath + "'; rc=$?; rm -f '" + remotePath + "'; exit $rc")
        return "=== APK INSTALL ===\n" + installResult
    }

    private func uploadUsingCat(data: Data, remotePath: String) async throws {
        let stream = try await openStream(service: "shell:cat > '" + remotePath + "'")
        let chunkSize = max(512, min(maxPayload, 4096))

        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<end)

            try await sendMessage(
                command: Self.commandWRTE,
                arg0: stream.localID,
                arg1: stream.remoteID,
                payload: chunk
            )

            try await waitForWriteAck(stream: stream)
            offset = end
        }

        try await sendMessage(
            command: Self.commandCLSE,
            arg0: stream.localID,
            arg1: stream.remoteID,
            payload: Data()
        )

        while true {
            let message = try await readMessage()

            if message.command == Self.commandCLSE,
               message.arg0 == stream.remoteID,
               message.arg1 == stream.localID {
                break
            }

            if message.command == Self.commandWRTE,
               message.arg0 == stream.remoteID,
               message.arg1 == stream.localID {
                try await sendMessage(
                    command: Self.commandOKAY,
                    arg0: stream.localID,
                    arg1: stream.remoteID,
                    payload: Data()
                )
            }
        }
    }

    private func waitForWriteAck(stream: ADBStream) async throws {
        while true {
            let message = try await readMessage()

            if message.command == Self.commandOKAY,
               message.arg0 == stream.remoteID,
               message.arg1 == stream.localID {
                return
            }

            if message.command == Self.commandWRTE,
               message.arg0 == stream.remoteID,
               message.arg1 == stream.localID {
                try await sendMessage(
                    command: Self.commandOKAY,
                    arg0: stream.localID,
                    arg1: stream.remoteID,
                    payload: Data()
                )
                continue
            }

            if message.command == Self.commandCLSE {
                throw ADBError.protocolError("Remote closed the APK upload stream.")
            }
        }
    }

    private func openStream(service: String) async throws -> ADBStream {
        let localID = nextLocalID
        nextLocalID &+= 1

        var payload = Data(service.utf8)
        payload.append(0)

        try await sendMessage(
            command: Self.commandOPEN,
            arg0: localID,
            arg1: 0,
            payload: payload
        )

        while true {
            let message = try await readMessage()

            if message.command == Self.commandOKAY,
               message.arg1 == localID {
                return ADBStream(localID: localID, remoteID: message.arg0)
            }

            if message.command == Self.commandCLSE,
               message.arg1 == localID {
                throw ADBError.protocolError("B1 rejected service: " + service)
            }
        }
    }

    private func sendMessage(command: UInt32, arg0: UInt32, arg1: UInt32, payload: Data) async throws {
        var packet = Data()
        packet.appendUInt32LE(command)
        packet.appendUInt32LE(arg0)
        packet.appendUInt32LE(arg1)
        packet.appendUInt32LE(UInt32(payload.count))
        packet.appendUInt32LE(payload.adbChecksum)
        packet.appendUInt32LE(command ^ 0xFFFF_FFFF)
        packet.append(payload)

        try await sendRaw(packet)
    }

    private func readMessage() async throws -> ADBMessage {
        let header = try await readExactly(24)

        let command = header.uint32LE(at: 0)
        let arg0 = header.uint32LE(at: 4)
        let arg1 = header.uint32LE(at: 8)
        let length = Int(header.uint32LE(at: 12))
        let checksum = header.uint32LE(at: 16)
        let magic = header.uint32LE(at: 20)

        guard magic == (command ^ 0xFFFF_FFFF) else {
            throw ADBError.protocolError("Invalid message magic.")
        }

        guard length >= 0 && length <= 16 * 1024 * 1024 else {
            throw ADBError.protocolError("Invalid payload length.")
        }

        let payload = length == 0 ? Data() : try await readExactly(length)

        if !payload.isEmpty && payload.adbChecksum != checksum {
            throw ADBError.protocolError("Payload checksum mismatch.")
        }

        return ADBMessage(command: command, arg0: arg0, arg1: arg1, payload: payload)
    }

    private func sendRaw(_ data: Data) async throws {
        guard let connection else {
            throw ADBError.disconnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func readExactly(_ count: Int) async throws -> Data {
        guard connection != nil else {
            throw ADBError.disconnected
        }

        var result = Data()
        result.reserveCapacity(count)

        while result.count < count {
            let chunk = try await receiveChunk(maximumLength: count - result.count)
            guard !chunk.isEmpty else {
                throw ADBError.disconnected
            }
            result.append(chunk)
        }

        return result
    }

    private func receiveChunk(maximumLength: Int) async throws -> Data {
        guard let connection else {
            throw ADBError.disconnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: maximumLength
            ) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                    return
                }

                if isComplete {
                    continuation.resume(throwing: ADBError.disconnected)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}

private struct ADBMessage {
    let command: UInt32
    let arg0: UInt32
    let arg1: UInt32
    let payload: Data
}

private struct ADBStream {
    let localID: UInt32
    let remoteID: UInt32
}

// MARK: - ADB RSA Authentication

private final class ADBKeyStore {
    private let tag = Data("com.fks.b1remote.adb.rsa".utf8)

    func signADBToken(_ token: Data) throws -> Data {
        guard token.count == 20 else {
            throw ADBError.security("Unexpected AUTH token size: " + String(token.count))
        }

        let key = try privateKey()
        var error: Unmanaged<CFError>?

        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureDigestPKCS1v15SHA1,
            token as CFData,
            &error
        ) as Data? else {
            let message = error?.takeRetainedValue().localizedDescription ?? "RSA signing failed."
            throw ADBError.security(message)
        }

        return signature
    }

    func adbPublicKeyPayload() throws -> Data {
        let privateKey = try self.privateKey()

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw ADBError.security("Unable to derive RSA public key.")
        }

        var error: Unmanaged<CFError>?
        guard let external = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            let message = error?.takeRetainedValue().localizedDescription ?? "Unable to export RSA public key."
            throw ADBError.security(message)
        }

        let parsed = try parseRSAPublicKey(external)
        var modulus = parsed.modulus

        while modulus.first == 0 && modulus.count > 256 {
            modulus.removeFirst()
        }

        if modulus.count < 256 {
            modulus = Data(repeating: 0, count: 256 - modulus.count) + modulus
        }

        guard modulus.count == 256 else {
            throw ADBError.security("Expected a 2048-bit RSA modulus.")
        }

        let words = modulusWordsLittleEndian(modulus)
        let n0 = words[0]
        var inverse: UInt32 = 1

        for _ in 0..<5 {
            inverse = inverse &* (2 &- (n0 &* inverse))
        }

        let n0inv = UInt32(0) &- inverse

        var rr = [UInt32](repeating: 0, count: 64)
        rr[0] = 1
        for _ in 0..<4096 {
            doubleModulo(&rr, modulus: words)
        }

        var androidKey = Data()
        androidKey.appendUInt32LE(64)
        androidKey.appendUInt32LE(n0inv)

        for word in words {
            androidKey.appendUInt32LE(word)
        }

        for word in rr {
            androidKey.appendUInt32LE(word)
        }

        androidKey.appendUInt32LE(parsed.exponent)

        let encoded = androidKey.base64EncodedString() + " b1remote@iphone\0"
        return Data(encoded.utf8)
    }

    private func privateKey() throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let existingStatus = SecItemCopyMatching(query as CFDictionary, &item)

        if existingStatus == errSecSuccess, let key = item as! SecKey? {
            return key
        }

        if existingStatus != errSecItemNotFound {
            throw ADBError.security("Keychain lookup failed: " + String(existingStatus))
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let message = error?.takeRetainedValue().localizedDescription ?? "Unable to generate RSA key."
            throw ADBError.security(message)
        }

        return key
    }

    private func parseRSAPublicKey(_ der: Data) throws -> (modulus: Data, exponent: UInt32) {
        var index = 0

        guard readByte(der, &index) == 0x30 else {
            throw ADBError.security("RSA public key DER sequence missing.")
        }
        _ = try readDERLength(der, &index)

        guard readByte(der, &index) == 0x02 else {
            throw ADBError.security("RSA modulus missing.")
        }
        let modulusLength = try readDERLength(der, &index)

        guard index + modulusLength <= der.count else {
            throw ADBError.security("RSA modulus is truncated.")
        }
        let modulus = der.subdata(in: index..<(index + modulusLength))
        index += modulusLength

        guard readByte(der, &index) == 0x02 else {
            throw ADBError.security("RSA exponent missing.")
        }
        let exponentLength = try readDERLength(der, &index)

        guard exponentLength > 0, exponentLength <= 4, index + exponentLength <= der.count else {
            throw ADBError.security("Unsupported RSA exponent.")
        }

        var exponent: UInt32 = 0
        for byte in der[index..<(index + exponentLength)] {
            exponent = (exponent << 8) | UInt32(byte)
        }

        return (modulus, exponent)
    }

    private func readByte(_ data: Data, _ index: inout Int) -> UInt8 {
        guard index < data.count else { return 0 }
        defer { index += 1 }
        return data[index]
    }

    private func readDERLength(_ data: Data, _ index: inout Int) throws -> Int {
        guard index < data.count else {
            throw ADBError.security("Truncated DER length.")
        }

        let first = data[index]
        index += 1

        if first & 0x80 == 0 {
            return Int(first)
        }

        let count = Int(first & 0x7F)
        guard count > 0, count <= 4, index + count <= data.count else {
            throw ADBError.security("Invalid DER length.")
        }

        var length = 0
        for _ in 0..<count {
            length = (length << 8) | Int(data[index])
            index += 1
        }

        return length
    }

    private func modulusWordsLittleEndian(_ modulus: Data) -> [UInt32] {
        let bytes = [UInt8](modulus)
        var words = [UInt32]()
        words.reserveCapacity(64)

        for wordIndex in 0..<64 {
            let start = bytes.count - ((wordIndex + 1) * 4)
            let value =
                (UInt32(bytes[start]) << 24) |
                (UInt32(bytes[start + 1]) << 16) |
                (UInt32(bytes[start + 2]) << 8) |
                UInt32(bytes[start + 3])
            words.append(value)
        }

        return words
    }

    private func doubleModulo(_ value: inout [UInt32], modulus: [UInt32]) {
        var carry: UInt64 = 0

        for index in 0..<value.count {
            let doubled = (UInt64(value[index]) << 1) | carry
            value[index] = UInt32(truncatingIfNeeded: doubled)
            carry = doubled >> 32
        }

        if carry != 0 || greaterThanOrEqual(value, modulus) {
            subtract(&value, modulus)
        }
    }

    private func greaterThanOrEqual(_ lhs: [UInt32], _ rhs: [UInt32]) -> Bool {
        for index in stride(from: lhs.count - 1, through: 0, by: -1) {
            if lhs[index] > rhs[index] { return true }
            if lhs[index] < rhs[index] { return false }
        }
        return true
    }

    private func subtract(_ lhs: inout [UInt32], _ rhs: [UInt32]) {
        var borrow: UInt64 = 0

        for index in 0..<lhs.count {
            let left = UInt64(lhs[index])
            let right = UInt64(rhs[index]) + borrow

            if left >= right {
                lhs[index] = UInt32(left - right)
                borrow = 0
            } else {
                lhs[index] = UInt32((UInt64(1) << 32) + left - right)
                borrow = 1
            }
        }
    }
}

// MARK: - Data Helpers

private extension Data {
    mutating func appendUInt32LE(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { raw in
            append(contentsOf: raw)
        }
    }

    func uint32LE(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }

        return UInt32(self[offset]) |
            (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) |
            (UInt32(self[offset + 3]) << 24)
    }

    var adbChecksum: UInt32 {
        reduce(UInt32(0)) { partial, byte in
            partial &+ UInt32(byte)
        }
    }
}
