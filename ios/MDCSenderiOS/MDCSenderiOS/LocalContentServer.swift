import Foundation
import Network

enum LocalContentServerEvent {
    case serving(contentURL: URL, imageURL: URL, fileName: String, imageBytes: Int)
    case request(String)
    case manifestServed
    case progressPosted(String)
    case imageServed(String)
    case notFound(String)
    case connectionEnded
}

final class LocalContentServer {
    private let imageData: Data
    private let requestedPort: Int
    private var manifest: EpaperManifest?
    private var manifestData: Data?
    private var contentURL: URL?
    private var imageURL: URL?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "net.maarten.mdc-ios.http")
    private var imageContinuation: CheckedContinuation<Void, Error>?
    private var imageDownloaded = false
    var onEvent: ((LocalContentServerEvent) -> Void)?

    init(imageData: Data, requestedPort: Int) {
        self.imageData = imageData
        self.requestedPort = requestedPort
    }

    func start(host: String) async throws -> URL {
        let listenPort = requestedPort == 0 ? NWEndpoint.Port.any : (NWEndpoint.Port(rawValue: UInt16(requestedPort)) ?? .any)
        let listener = try NWListener(using: .tcp, on: listenPort)
        self.listener = listener

        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = listener.port,
                          let baseURL = URL(string: "http://\(host):\(port.rawValue)") else {
                        continuation.resume(throwing: HTTPServerError.invalidURL)
                        return
                    }
                    do {
                        let contentURL = baseURL.appendingPathComponent("content.json")
                        let manifest = EpaperManifest.make(imageBaseURL: baseURL, fileSize: self.imageData.count)
                        let imageURL = manifest.imageURL
                        self.manifest = manifest
                        self.manifestData = try manifest.jsonData()
                        self.contentURL = contentURL
                        self.imageURL = imageURL
                        self.onEvent?(.serving(
                            contentURL: contentURL,
                            imageURL: imageURL,
                            fileName: manifest.fileName,
                            imageBytes: self.imageData.count
                        ))
                        continuation.resume(returning: contentURL)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                case .failed(let error):
                    continuation.resume(throwing: error)
                    self.stop()
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection, host: host)
            }
            listener.start(queue: queue)
        }
    }

    func waitForImageDownload(timeout: TimeInterval) async throws {
        if imageDownloaded {
            return
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.imageContinuation = continuation
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw HTTPServerError.timeout
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection, host: String) {
        connection.stateUpdateHandler = { state in
            if case .failed = state {
                connection.cancel()
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, host: host)
    }

    private func receiveRequest(on connection: NWConnection, host: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.sendResponse(status: "500 Internal Server Error", body: Data(error.localizedDescription.utf8), contentType: "text/plain", on: connection)
                return
            }
            if (data == nil || data?.isEmpty == true), isComplete {
                self.onEvent?(.connectionEnded)
                connection.cancel()
                return
            }
            guard let data else {
                self.sendResponse(status: "400 Bad Request", body: Data(), contentType: "text/plain", on: connection)
                return
            }

            self.receiveRemainingRequest(data, on: connection, host: host)
        }
    }

    private func receiveRemainingRequest(_ data: Data, on connection: NWConnection, host: String) {
        let missingBytes = remainingBodyBytes(in: data)
        guard missingBytes > 0 else {
            handleRequest(data, on: connection, host: host)
            return
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: max(4096, missingBytes)) { [weak self] moreData, _, _, error in
            guard let self else { return }
            if let error {
                self.sendResponse(status: "500 Internal Server Error", body: Data(error.localizedDescription.utf8), contentType: "text/plain", on: connection)
                return
            }
            guard let moreData, !moreData.isEmpty else {
                self.handleRequest(data, on: connection, host: host)
                return
            }

            var combined = data
            combined.append(moreData)
            self.receiveRemainingRequest(combined, on: connection, host: host)
        }
    }

    private func handleRequest(_ data: Data, on connection: NWConnection, host: String) {
        guard let request = String(data: data, encoding: .utf8),
              let firstLine = request.split(separator: "\r\n").first else {
            sendResponse(status: "400 Bad Request", body: Data(), contentType: "text/plain", on: connection)
            return
        }

        let parts = firstLine.split(separator: " ")
        let path = parts.count > 1 ? self.path(from: String(parts[1])) : "/"
        self.onEvent?(.request(String(firstLine)))
        let bodyText = bodyText(from: data)

            switch path {
            case "/content.json":
                guard let body = manifestData else {
                    self.sendResponse(status: "500 Internal Server Error", body: Data("Manifest not ready".utf8), contentType: "text/plain", on: connection)
                    return
                }
                self.sendResponse(
                    status: "200 OK",
                    body: body,
                    contentType: "application/json",
                    on: connection,
                    closeAfterSend: false
                ) {
                    self.onEvent?(.manifestServed)
                    self.receiveRequest(on: connection, host: host)
                }
            case "/content-transfer-progress":
                self.sendResponse(status: "200 OK", body: Data("{}".utf8), contentType: "application/json", on: connection) {
                    self.onEvent?(.progressPosted(bodyText))
                }
            case "/image":
                self.sendImage(path: path, on: connection)
            default:
                if self.isImageFallbackPath(path) {
                    self.sendImage(path: path, on: connection)
                } else {
                    self.onEvent?(.notFound(path))
                    self.sendResponse(status: "404 Not Found", body: Data(), contentType: "text/plain", on: connection)
                }
            }
    }

    private func sendImage(path: String, on connection: NWConnection) {
        sendResponse(status: "200 OK", body: imageData, contentType: "image/jpeg", on: connection) {
            self.onEvent?(.imageServed(path))
            self.markImageDownloaded()
        }
    }

    private func isImageFallbackPath(_ path: String) -> Bool {
        guard path != "/" && path != "/content.json" else { return false }

        if let fileName = manifest?.fileName,
           path == fileName || path == "/\(fileName)" || path.hasSuffix("/\(fileName)") {
            return true
        }

        let lowercased = path.lowercased()
        return lowercased.hasSuffix(".jpg") ||
            lowercased.hasSuffix(".jpeg") ||
            lowercased.hasSuffix(".png") ||
            lowercased.hasSuffix(".webp")
    }

    private func path(from requestTarget: String) -> String {
        if let components = URLComponents(string: requestTarget), !components.path.isEmpty {
            return components.path
        }
        return requestTarget.split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
    }

    private func bodyText(from requestData: Data) -> String {
        guard let headerEnd = requestData.range(of: Data("\r\n\r\n".utf8))?.upperBound,
              headerEnd < requestData.count else {
            return ""
        }

        let body = requestData[headerEnd...]
        return String(decoding: body, as: UTF8.self)
    }

    private func remainingBodyBytes(in requestData: Data) -> Int {
        guard let headerRange = requestData.range(of: Data("\r\n\r\n".utf8)) else {
            return 0
        }

        let headerText = String(decoding: requestData[..<headerRange.lowerBound], as: UTF8.self)
        let contentLength = headerText
            .split(separator: "\r\n")
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length" else {
                    return nil
                }
                return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .first ?? 0

        let receivedBodyBytes = requestData.count - headerRange.upperBound
        return max(contentLength - receivedBodyBytes, 0)
    }

    private func sendResponse(
        status: String,
        body: Data,
        contentType: String,
        on connection: NWConnection,
        closeAfterSend: Bool = true,
        onComplete: (() -> Void)? = nil
    ) {
        let connectionHeader = closeAfterSend ? "close" : "keep-alive"
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: \(connectionHeader)\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)

        connection.send(content: response, isComplete: closeAfterSend, completion: .contentProcessed { _ in
            onComplete?()
            if closeAfterSend {
                connection.cancel()
            }
        })
    }

    private func markImageDownloaded() {
        guard !imageDownloaded else { return }
        imageDownloaded = true
        imageContinuation?.resume()
        imageContinuation = nil
    }
}

enum HTTPServerError: LocalizedError {
    case invalidURL
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Could not create content URL"
        case .timeout:
            "Timed out waiting for display download"
        }
    }
}
