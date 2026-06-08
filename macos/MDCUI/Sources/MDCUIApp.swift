import Foundation
import SwiftUI
import UniformTypeIdentifiers

@main
struct MDCSenderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, idealWidth: 1120, minHeight: 640, idealHeight: 720)
        }
        .defaultSize(width: 1120, height: 720)
        .windowStyle(.titleBar)
    }
}

struct ContentView: View {
    @State private var host = ""
    @State private var port = 1515
    @State private var mac = ""
    @State private var localIP = ""
    @State private var pin = ""
    @State private var displayID = 0
    @State private var timeout = 120
    @State private var waitForDownload = true
    @State private var imageFit = "original"
    @State private var canvasWidth = 2560
    @State private var canvasHeight = 1440
    @State private var cropX = 0.5
    @State private var cropY = 0.5
    @State private var imageURL: URL?
    @State private var log = ""
    @State private var isSending = false
    @State private var showImporter = false
    @State private var isLoadingConfig = true

    var body: some View {
        NavigationSplitView {
            Form {
                Section("Display") {
                    TextField("IP address", text: $host)
                    SecureField("PIN", text: $pin)
                    Stepper(value: $displayID, in: 0...253) {
                        Text("Display ID: \(displayID)")
                    }
                    Stepper(value: $port, in: 1...65535) {
                        Text("Port: \(port)")
                    }
                    TextField("MAC for Wake-on-LAN", text: $mac)
                    TextField("Local IP override", text: $localIP)
                }

                Section("Transfer") {
                    Stepper(value: $timeout, in: 10...600, step: 10) {
                        Text("Timeout: \(timeout)s")
                    }
                    Toggle("Wait for image download", isOn: $waitForDownload)
                }

                Section("Image") {
                    Picker("Fit", selection: $imageFit) {
                        Text("Original").tag("original")
                        Text("Contain").tag("contain")
                        Text("Cover").tag("cover")
                        Text("Stretch").tag("stretch")
                    }
                    .pickerStyle(.segmented)

                    Stepper(value: $canvasWidth, in: 320...8192, step: 10) {
                        Text("Width: \(canvasWidth)")
                    }
                    Stepper(value: $canvasHeight, in: 240...8192, step: 10) {
                        Text("Height: \(canvasHeight)")
                    }
                    Slider(value: $cropX, in: 0...1) {
                        Text("Horizontal focus")
                    }
                    Slider(value: $cropY, in: 0...1) {
                        Text("Vertical focus")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
            .navigationTitle("MDC Sender")
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Choose Image", systemImage: "photo")
                    }

                    Button {
                        sendImage()
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSend || isSending)

                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                imagePreview

                Text("Log")
                    .font(.headline)
                ScrollView {
                    Text(log.isEmpty ? "No activity yet." : log)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(20)
            .navigationSplitViewColumnWidth(min: 680, ideal: 800)
            .navigationTitle("Image")
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.jpeg, .png, .bmp],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                imageURL = urls.first
            case .failure(let error):
                appendLog("Image selection failed: \(error.localizedDescription)")
            }
        }
        .onAppear(perform: loadConfig)
        .onChange(of: configSnapshot) { _ in
            saveConfig()
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let imageURL, let image = NSImage(contentsOf: imageURL) {
            VStack(alignment: .leading, spacing: 8) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 280)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(imageURL.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("No image selected")
                    .foregroundStyle(.secondary)
            }
                .frame(maxWidth: .infinity, minHeight: 280)
        }
    }

    private var canSend: Bool {
        !host.isEmpty && !pin.isEmpty && imageURL != nil
    }

    private var configSnapshot: MDCConfig {
        MDCConfig(
            host: host,
            port: port,
            displayID: displayID,
            pin: pin,
            mac: mac,
            localIP: localIP,
            timeoutSeconds: timeout,
            waitForDownload: waitForDownload,
            imageFit: imageFit,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            cropX: cropX,
            cropY: cropY
        )
    }

    private func loadConfig() {
        guard isLoadingConfig else { return }
        do {
            let config = try MDCConfig.load()
            host = config.host
            port = config.port
            displayID = config.displayID
            pin = config.pin
            mac = config.mac
            localIP = config.localIP
            timeout = config.timeoutSeconds
            waitForDownload = config.waitForDownload
            imageFit = config.imageFit
            canvasWidth = config.canvasWidth
            canvasHeight = config.canvasHeight
            cropX = config.cropX
            cropY = config.cropY
        } catch {
            appendLog("Could not load config: \(error.localizedDescription)")
        }
        isLoadingConfig = false
    }

    private func saveConfig() {
        guard !isLoadingConfig else { return }
        do {
            try configSnapshot.save()
        } catch {
            appendLog("Could not save config: \(error.localizedDescription)")
        }
    }

    private func sendImage() {
        guard let imageURL else { return }
        saveConfig()

        let command = CLICommand(
            host: host,
            port: port,
            pin: pin,
            displayID: displayID,
            mac: mac,
            localIP: localIP,
            timeout: timeout,
            waitForDownload: waitForDownload,
            imageFit: imageFit,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            cropX: cropX,
            cropY: cropY,
            imageURL: imageURL
        )
        isSending = true
        log = ""
        appendLog("Starting transfer")

        Task.detached {
            do {
                let output = try command.run()
                await MainActor.run {
                    appendLog(output)
                    appendLog("Done")
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    appendLog("Failed: \(error.localizedDescription)")
                    isSending = false
                }
            }
        }
    }

    @MainActor
    private func appendLog(_ text: String) {
        if !log.isEmpty {
            log += "\n"
        }
        log += text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MDCConfig: Codable, Equatable {
    var host: String
    var port: Int
    var displayID: Int
    var pin: String
    var mac: String
    var localIP: String
    var timeoutSeconds: Int
    var waitForDownload: Bool
    var imageFit: String
    var canvasWidth: Int
    var canvasHeight: Int
    var cropX: Double
    var cropY: Double

    enum CodingKeys: String, CodingKey {
        case host
        case port
        case displayID = "display_id"
        case pin
        case mac
        case localIP = "local_ip"
        case timeoutSeconds = "timeout_seconds"
        case waitForDownload = "wait_for_download"
        case imageFit = "image_fit"
        case canvasWidth = "canvas_width"
        case canvasHeight = "canvas_height"
        case cropX = "crop_x"
        case cropY = "crop_y"
    }

    init(
        host: String = "",
        port: Int = 1515,
        displayID: Int = 0,
        pin: String = "",
        mac: String = "",
        localIP: String = "",
        timeoutSeconds: Int = 120,
        waitForDownload: Bool = true,
        imageFit: String = "original",
        canvasWidth: Int = 2560,
        canvasHeight: Int = 1440,
        cropX: Double = 0.5,
        cropY: Double = 0.5
    ) {
        self.host = host
        self.port = port
        self.displayID = displayID
        self.pin = pin
        self.mac = mac
        self.localIP = localIP
        self.timeoutSeconds = timeoutSeconds
        self.waitForDownload = waitForDownload
        self.imageFit = imageFit
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.cropX = cropX
        self.cropY = cropY
        normalize()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 1515
        displayID = try container.decodeIfPresent(Int.self, forKey: .displayID) ?? 0
        pin = try container.decodeIfPresent(String.self, forKey: .pin) ?? ""
        mac = try container.decodeIfPresent(String.self, forKey: .mac) ?? ""
        localIP = try container.decodeIfPresent(String.self, forKey: .localIP) ?? ""
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 120
        waitForDownload = try container.decodeIfPresent(Bool.self, forKey: .waitForDownload) ?? true
        imageFit = try container.decodeIfPresent(String.self, forKey: .imageFit) ?? "original"
        canvasWidth = try container.decodeIfPresent(Int.self, forKey: .canvasWidth) ?? 2560
        canvasHeight = try container.decodeIfPresent(Int.self, forKey: .canvasHeight) ?? 1440
        cropX = try container.decodeIfPresent(Double.self, forKey: .cropX) ?? 0.5
        cropY = try container.decodeIfPresent(Double.self, forKey: .cropY) ?? 0.5
        normalize()
    }

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mdc")
            .appendingPathComponent("config.json")
    }

    static func load() throws -> MDCConfig {
        let url = Self.url
        guard FileManager.default.fileExists(atPath: url.path) else {
            return MDCConfig()
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MDCConfig.self, from: data)
    }

    func save() throws {
        let url = Self.url
        let directoryURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private mutating func normalize() {
        if port == 0 {
            port = 1515
        }
        if displayID < 0 {
            displayID = 0
        }
        if displayID > 253 {
            displayID = 253
        }
        if timeoutSeconds == 0 {
            timeoutSeconds = 120
        }
        if imageFit.isEmpty {
            imageFit = "original"
        }
        if canvasWidth == 0 {
            canvasWidth = 2560
        }
        if canvasHeight == 0 {
            canvasHeight = 1440
        }
        cropX = min(max(cropX, 0), 1)
        cropY = min(max(cropY, 0), 1)
    }
}

struct CLICommand: Sendable {
    let host: String
    let port: Int
    let pin: String
    let displayID: Int
    let mac: String
    let localIP: String
    let timeout: Int
    let waitForDownload: Bool
    let imageFit: String
    let canvasWidth: Int
    let canvasHeight: Int
    let cropX: Double
    let cropY: Double
    let imageURL: URL

    func run() throws -> String {
        let cliURL = try findCLI()
        let process = Process()
        process.executableURL = cliURL

        var arguments = [
            "show-image",
            "--host", host,
            "--port", String(port),
            "--pin", pin,
            "--display", String(displayID),
            "--image", imageURL.path,
            "--timeout", "\(timeout)s",
            "--fit", imageFit,
            "--canvas-width", String(canvasWidth),
            "--canvas-height", String(canvasHeight),
            "--crop-x", String(cropX),
            "--crop-y", String(cropY)
        ]
        if !mac.isEmpty {
            arguments += ["--mac", mac]
        }
        if !localIP.isEmpty {
            arguments += ["--local-ip", localIP]
        }
        if !waitForDownload {
            arguments.append("--no-wait")
        }
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "MDCUI",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "CLI exited with status \(process.terminationStatus)" : output]
            )
        }
        return output
    }

    private func findCLI() throws -> URL {
        if let resourceURL = Bundle.main.url(forResource: "mdc", withExtension: nil) {
            return resourceURL
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["mdc"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let path, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        throw NSError(
            domain: "MDCUI",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not find the mdc CLI in the app bundle or PATH."]
        )
    }
}
