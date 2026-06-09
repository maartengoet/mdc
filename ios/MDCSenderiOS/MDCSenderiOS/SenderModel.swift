import PhotosUI
import SwiftUI

@MainActor
final class SenderModel: ObservableObject {
    @Published var settings: DisplaySettings
    @Published var selectedImage: UIImage?
    @Published var selectedImageName = ""
    @Published var phase: SendPhase = .idle
    @Published var isSending = false
    @Published var showSettings = false
    @Published var transferLog: [String] = []

    private let settingsKey = "display-settings-v1"

    init() {
        settings = Self.loadSettings(key: settingsKey)
        showSettings = !settings.isReady
    }

    func saveSettings() {
        var normalized = settings
        normalized.normalize()
        settings = normalized
        if let data = try? JSONEncoder().encode(normalized) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                phase = .failed("Could not load image")
                return
            }
            selectedImage = image
            selectedImageName = item.itemIdentifier ?? "Photo"
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func sendSelectedImage() async {
        guard let selectedImage else {
            phase = .failed("No image selected")
            return
        }
        guard settings.isReady else {
            showSettings = true
            phase = .failed("Missing display settings")
            return
        }

        saveSettings()
        transferLog = []
        isSending = true
        defer { isSending = false }

        do {
            phase = .preparing
            let imageData = try ImageRenderer.renderJPEG(image: selectedImage, settings: settings)
            let localIP = settings.localIP.isEmpty ? (LocalNetwork.wifiIPv4Address() ?? "") : settings.localIP
            guard !localIP.isEmpty else {
                throw SenderError.localIPUnavailable
            }

            let server = LocalContentServer(imageData: imageData, requestedPort: settings.httpPort)
            server.onEvent = { [weak self] event in
                Task { @MainActor in
                    switch event {
                    case .serving(let contentURL, let imageURL, let fileName, let imageBytes):
                        self?.appendLog("Serving \(contentURL.absoluteString)")
                        self?.appendLog("Image URL \(imageURL.absoluteString)")
                        self?.appendLog("\(fileName), \(imageBytes) bytes")
                    case .request(let request):
                        self?.appendLog("HTTP \(request)")
                    case .manifestServed:
                        self?.appendLog("Served content.json")
                        self?.phase = .manifestRequested
                    case .progressPosted(let body):
                        if body.isEmpty {
                            self?.appendLog("Accepted transfer progress")
                        } else {
                            self?.appendLog("Progress \(body)")
                        }
                    case .imageServed(let path):
                        self?.appendLog("Served image at \(path)")
                        self?.phase = .imageRequested
                    case .notFound(let path):
                        self?.appendLog("404 \(path)")
                    case .connectionEnded:
                        self?.appendLog("HTTP connection ended")
                    }
                }
            }
            let contentURL = try await server.start(host: localIP)
            defer { server.stop() }
            phase = .serving(contentURL)

            if !settings.mac.isEmpty {
                phase = .waking
                try WakeOnLAN.send(mac: settings.mac)
                try await Task.sleep(nanoseconds: 900_000_000)
            }

            phase = .connecting
            let client = MDCClient(
                host: settings.host,
                port: settings.port,
                displayID: UInt8(settings.displayID),
                pin: settings.pin,
                timeout: TimeInterval(settings.timeoutSeconds)
            )
            try await client.connect()

            phase = .sending
            try await client.setContentDownloadURL(contentURL.absoluteString)
            client.close()

            guard settings.waitForDownload else {
                phase = .finished
                server.stop()
                return
            }

            phase = .waiting(contentURL)
            try await server.waitForImageDownload(timeout: TimeInterval(settings.timeoutSeconds))
            phase = .finished
        } catch {
            phase = .failed(error.localizedDescription)
            appendLog("Error: \(error.localizedDescription)")
        }
    }

    private func appendLog(_ message: String) {
        transferLog.append(message)
        if transferLog.count > 40 {
            transferLog.removeFirst(transferLog.count - 40)
        }
    }

    private static func loadSettings(key: String) -> DisplaySettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              var decoded = try? JSONDecoder().decode(DisplaySettings.self, from: data) else {
            return DisplaySettings()
        }
        decoded.normalize()
        return decoded
    }
}

enum SenderError: LocalizedError {
    case localIPUnavailable

    var errorDescription: String? {
        switch self {
        case .localIPUnavailable:
            "Local Wi-Fi IP unavailable"
        }
    }
}
