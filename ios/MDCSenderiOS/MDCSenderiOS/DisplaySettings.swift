import Foundation

struct DisplaySettings: Codable, Equatable {
    var host: String = ""
    var port: Int = 1515
    var displayID: Int = 0
    var pin: String = ""
    var mac: String = ""
    var localIP: String = ""
    var httpPort: Int = 8080
    var timeoutSeconds: Int = 120
    var waitForDownload: Bool = true
    var imageFit: ImageFit = .cover
    var canvasWidth: Int = 2560
    var canvasHeight: Int = 1440
    var cropX: Double = 0.5
    var cropY: Double = 0.65

    var isReady: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !pin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case host
        case port
        case displayID
        case pin
        case mac
        case localIP
        case httpPort
        case timeoutSeconds
        case waitForDownload
        case imageFit
        case canvasWidth
        case canvasHeight
        case cropX
        case cropY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 1515
        displayID = try container.decodeIfPresent(Int.self, forKey: .displayID) ?? 0
        pin = try container.decodeIfPresent(String.self, forKey: .pin) ?? ""
        mac = try container.decodeIfPresent(String.self, forKey: .mac) ?? ""
        localIP = try container.decodeIfPresent(String.self, forKey: .localIP) ?? ""
        httpPort = try container.decodeIfPresent(Int.self, forKey: .httpPort) ?? 8080
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 120
        waitForDownload = try container.decodeIfPresent(Bool.self, forKey: .waitForDownload) ?? true
        imageFit = try container.decodeIfPresent(ImageFit.self, forKey: .imageFit) ?? .cover
        canvasWidth = try container.decodeIfPresent(Int.self, forKey: .canvasWidth) ?? 2560
        canvasHeight = try container.decodeIfPresent(Int.self, forKey: .canvasHeight) ?? 1440
        cropX = try container.decodeIfPresent(Double.self, forKey: .cropX) ?? 0.5
        cropY = try container.decodeIfPresent(Double.self, forKey: .cropY) ?? 0.65
        normalize()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(displayID, forKey: .displayID)
        try container.encode(pin, forKey: .pin)
        try container.encode(mac, forKey: .mac)
        try container.encode(localIP, forKey: .localIP)
        try container.encode(httpPort, forKey: .httpPort)
        try container.encode(timeoutSeconds, forKey: .timeoutSeconds)
        try container.encode(waitForDownload, forKey: .waitForDownload)
        try container.encode(imageFit, forKey: .imageFit)
        try container.encode(canvasWidth, forKey: .canvasWidth)
        try container.encode(canvasHeight, forKey: .canvasHeight)
        try container.encode(cropX, forKey: .cropX)
        try container.encode(cropY, forKey: .cropY)
    }

    mutating func normalize() {
        if port <= 0 || port > 65535 {
            port = 1515
        }
        if httpPort < 0 || httpPort > 65535 {
            httpPort = 8080
        }
        displayID = min(max(displayID, 0), 253)
        if timeoutSeconds <= 0 {
            timeoutSeconds = 120
        }
        if canvasWidth <= 0 {
            canvasWidth = 2560
        }
        if canvasHeight <= 0 {
            canvasHeight = 1440
        }
        cropX = min(max(cropX, 0), 1)
        cropY = min(max(cropY, 0), 1)
    }
}

enum ImageFit: String, CaseIterable, Codable, Identifiable {
    case original
    case contain
    case cover
    case stretch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "Original"
        case .contain: "Contain"
        case .cover: "Cover"
        case .stretch: "Stretch"
        }
    }
}

enum SendPhase: Equatable {
    case idle
    case preparing
    case serving(URL)
    case waking
    case connecting
    case sending
    case waiting(URL)
    case manifestRequested
    case imageRequested
    case finished
    case failed(String)

    var title: String {
        switch self {
        case .idle: "Ready"
        case .preparing: "Preparing"
        case .serving: "Serving"
        case .waking: "Waking"
        case .connecting: "Connecting"
        case .sending: "Sending"
        case .waiting: "Downloading"
        case .manifestRequested: "Manifest"
        case .imageRequested: "Image"
        case .finished: "Sent"
        case .failed: "Failed"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            "Choose an image"
        case .preparing:
            "Rendering for panel"
        case .serving(let url):
            "HTTP \(url.port ?? 80)"
        case .waking:
            "Wake-on-LAN"
        case .connecting:
            "MDC session"
        case .sending:
            "Sending URL"
        case .waiting(let url):
            "Wait \(url.port ?? 80)"
        case .manifestRequested:
            "manifest ok"
        case .imageRequested:
            "image ok"
        case .finished:
            "Downloaded"
        case .failed(let message):
            message
        }
    }
}
