import Darwin
import Foundation

private let tlsStartBanner = "MDCSTART<<TLS>>"
private let authPassBanner = "MDCAUTH<<PASS>>"
private let authFailPrefix = "MDCAUTH<<FAIL:"

private let mdcSSLNoErr: OSStatus = 0
private let mdcSSLWouldBlock: OSStatus = -9803
private let mdcSSLClosedGraceful: OSStatus = -9805
private let mdcSSLClosedAbort: OSStatus = -9806
private let mdcSSLPeerAuthCompleted: OSStatus = -9841
private let mdcSSLClientSide: Int32 = 1
private let mdcSSLStreamType: Int32 = 0
private let mdcSSLSessionOptionBreakOnServerAuth: Int32 = 0

private typealias MDCSSLContext = OpaquePointer
private typealias MDCSSLConnectionRef = UnsafeRawPointer
private typealias MDCSSLReadFunc = @convention(c) (MDCSSLConnectionRef, UnsafeMutableRawPointer, UnsafeMutablePointer<Int>) -> OSStatus
private typealias MDCSSLWriteFunc = @convention(c) (MDCSSLConnectionRef, UnsafeRawPointer, UnsafeMutablePointer<Int>) -> OSStatus

// Samsung MDC sends a plain banner, then upgrades that same socket to TLS.
// Network.framework cannot start TLS after bytes have already been exchanged.
@_silgen_name("SSLCreateContext")
private func MDCSSLCreateContext(_ allocator: CFAllocator?, _ protocolSide: Int32, _ connectionType: Int32) -> MDCSSLContext?

@_silgen_name("SSLSetIOFuncs")
private func MDCSSLSetIOFuncs(_ context: MDCSSLContext, _ readFunc: MDCSSLReadFunc, _ writeFunc: MDCSSLWriteFunc) -> OSStatus

@_silgen_name("SSLSetConnection")
private func MDCSSLSetConnection(_ context: MDCSSLContext, _ connection: MDCSSLConnectionRef?) -> OSStatus

@_silgen_name("SSLSetSessionOption")
private func MDCSSLSetSessionOption(_ context: MDCSSLContext, _ option: Int32, _ value: Bool) -> OSStatus

@_silgen_name("SSLSetPeerDomainName")
private func MDCSSLSetPeerDomainName(_ context: MDCSSLContext, _ peerName: UnsafePointer<CChar>?, _ peerNameLength: Int) -> OSStatus

@_silgen_name("SSLHandshake")
private func MDCSSLHandshake(_ context: MDCSSLContext) -> OSStatus

@_silgen_name("SSLWrite")
private func MDCSSLWrite(_ context: MDCSSLContext, _ data: UnsafeRawPointer?, _ dataLength: Int, _ processed: UnsafeMutablePointer<Int>) -> OSStatus

@_silgen_name("SSLRead")
private func MDCSSLRead(_ context: MDCSSLContext, _ data: UnsafeMutableRawPointer, _ dataLength: Int, _ processed: UnsafeMutablePointer<Int>) -> OSStatus

@_silgen_name("SSLClose")
private func MDCSSLClose(_ context: MDCSSLContext) -> OSStatus

final class MDCClient {
    private let host: String
    private let port: Int
    private let displayID: UInt8
    private let pin: String
    private let timeout: TimeInterval
    private var fileDescriptor: Int32 = -1
    private var sslContext: MDCSSLContext?

    init(host: String, port: Int, displayID: UInt8, pin: String, timeout: TimeInterval) {
        self.host = host
        self.port = port
        self.displayID = displayID
        self.pin = pin
        self.timeout = timeout
    }

    func connect() async throws {
        try await runBlocking {
            try self.connectSync()
        }
    }

    func setContentDownloadURL(_ url: String) async throws {
        try await runBlocking {
            guard url.utf8.count <= 255 else {
                throw MDCError.urlTooLong
            }
            var data = Data([0x53, 0x80, UInt8(url.utf8.count)])
            data.append(Data(url.utf8))
            _ = try self.sendCommand(command: 0xC7, data: data)
        }
    }

    func close() {
        if let sslContext {
            _ = MDCSSLClose(sslContext)
            Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(sslContext)).release()
        }
        sslContext = nil
        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
        }
        fileDescriptor = -1
    }

    private func connectSync() throws {
        guard fileDescriptor < 0 else { return }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw MDCError.socket(errno)
        }
        fileDescriptor = fd

        var receiveTimeout = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))
        var sendTimeout = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            throw MDCError.invalidHost(host)
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            throw MDCError.socket(errno)
        }

        let banner = try readPlain(count: tlsStartBanner.utf8.count)
        guard String(data: banner, encoding: .utf8) == tlsStartBanner else {
            throw MDCError.unexpectedBanner(String(data: banner, encoding: .utf8) ?? "<binary>")
        }

        let context = try makeTLSContext(fileDescriptor: fd)
        sslContext = context
        try handshake(context: context)
        try sslWrite(Data(pin.utf8))

        let auth = try sslRead(count: authPassBanner.utf8.count)
        let authText = String(data: auth, encoding: .utf8) ?? "<binary>"
        if authText == authPassBanner {
            return
        }
        if authText.hasPrefix(authFailPrefix) {
            let rest = try sslRead(count: 5)
            let restText = String(data: rest, encoding: .utf8) ?? ""
            throw MDCError.authenticationFailed(authText + restText)
        }
        throw MDCError.unexpectedAuth(authText)
    }

    private func sendCommand(command: UInt8, data: Data) throws -> Data {
        var frame = Data([0xAA, command, displayID, UInt8(data.count)])
        frame.append(data)
        frame.append(checksum(frame.dropFirst()))
        try sslWrite(frame)
        return try readResponse(expectedCommand: command)
    }

    private func readResponse(expectedCommand: UInt8) throws -> Data {
        let header = try sslRead(count: 4)
        guard header[0] == 0xAA, header[1] == 0xFF else {
            throw MDCError.invalidFrame
        }
        guard header[2] == displayID else {
            throw MDCError.invalidFrame
        }

        let length = Int(header[3])
        let body = try sslRead(count: length + 1)
        var frame = Data()
        frame.append(header)
        frame.append(body)

        guard frame.last == checksum(frame.dropFirst().dropLast()) else {
            throw MDCError.checksumMismatch
        }
        guard length >= 2 else {
            throw MDCError.invalidFrame
        }

        let ackOrNak = frame[4]
        let responseCommand = frame[5]
        guard responseCommand == expectedCommand else {
            throw MDCError.invalidFrame
        }

        let payload = frame.subdata(in: 6..<(frame.count - 1))
        switch ackOrNak {
        case 0x41:
            return payload
        case 0x4E:
            throw MDCError.negativeAcknowledgement(payload.first ?? 0)
        default:
            throw MDCError.invalidFrame
        }
    }

    private func readPlain(count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < count {
                let result = recv(fileDescriptor, base.advanced(by: offset), count - offset, 0)
                if result <= 0 {
                    throw MDCError.socket(errno)
                }
                offset += result
            }
        }
        return data
    }

    private func makeTLSContext(fileDescriptor: Int32) throws -> MDCSSLContext {
        guard let context = MDCSSLCreateContext(nil, mdcSSLClientSide, mdcSSLStreamType) else {
            throw MDCError.tls("Could not create TLS context")
        }

        var status = MDCSSLSetIOFuncs(context, sslReadCallback, sslWriteCallback)
        guard status == mdcSSLNoErr else {
            throw MDCError.osStatus(status)
        }

        status = MDCSSLSetConnection(context, UnsafeRawPointer(bitPattern: Int(fileDescriptor)))
        guard status == mdcSSLNoErr else {
            throw MDCError.osStatus(status)
        }

        status = MDCSSLSetSessionOption(context, mdcSSLSessionOptionBreakOnServerAuth, true)
        guard status == mdcSSLNoErr else {
            throw MDCError.osStatus(status)
        }

        status = host.withCString { pointer in
            MDCSSLSetPeerDomainName(context, pointer, strlen(pointer))
        }
        guard status == mdcSSLNoErr else {
            throw MDCError.osStatus(status)
        }
        return context
    }

    private func handshake(context: MDCSSLContext) throws {
        while true {
            let status = MDCSSLHandshake(context)
            switch status {
            case mdcSSLNoErr:
                return
            case mdcSSLWouldBlock:
                continue
            case mdcSSLPeerAuthCompleted:
                continue
            default:
                throw MDCError.osStatus(status)
            }
        }
    }

    private func sslWrite(_ data: Data) throws {
        guard let sslContext else {
            throw MDCError.notConnected
        }
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                var processed = 0
                let status = MDCSSLWrite(sslContext, base.advanced(by: offset), data.count - offset, &processed)
                guard status == mdcSSLNoErr || status == mdcSSLWouldBlock else {
                    throw MDCError.osStatus(status)
                }
                offset += processed
            }
        }
    }

    private func sslRead(count: Int) throws -> Data {
        guard let sslContext else {
            throw MDCError.notConnected
        }

        var data = Data(count: count)
        try data.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < count {
                var processed = 0
                let status = MDCSSLRead(sslContext, base.advanced(by: offset), count - offset, &processed)
                if status == mdcSSLNoErr || status == mdcSSLWouldBlock {
                    offset += processed
                    continue
                }
                throw MDCError.osStatus(status)
            }
        }
        return data
    }

    private func checksum(_ bytes: Data.SubSequence) -> UInt8 {
        bytes.reduce(UInt8(0)) { partial, byte in
            partial &+ byte
        }
    }
}

private let sslReadCallback: SSLReadFunc = { connection, data, dataLength in
    let fd = Int32(Int(bitPattern: connection))
    let requested = dataLength.pointee
    let result = recv(fd, data, requested, 0)
    if result > 0 {
        dataLength.pointee = result
        return mdcSSLNoErr
    }
    if result == 0 {
        dataLength.pointee = 0
        return mdcSSLClosedGraceful
    }
    if errno == EAGAIN || errno == EWOULDBLOCK {
        dataLength.pointee = 0
        return mdcSSLWouldBlock
    }
    dataLength.pointee = 0
    return mdcSSLClosedAbort
}

private let sslWriteCallback: SSLWriteFunc = { connection, data, dataLength in
    let fd = Int32(Int(bitPattern: connection))
    let requested = dataLength.pointee
    let result = send(fd, data, requested, 0)
    if result > 0 {
        dataLength.pointee = result
        return mdcSSLNoErr
    }
    if result == 0 {
        dataLength.pointee = 0
        return mdcSSLClosedGraceful
    }
    if errno == EAGAIN || errno == EWOULDBLOCK {
        dataLength.pointee = 0
        return mdcSSLWouldBlock
    }
    dataLength.pointee = 0
    return mdcSSLClosedAbort
}

private func runBlocking<T>(_ work: @escaping () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                continuation.resume(returning: try work())
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum MDCError: LocalizedError {
    case invalidHost(String)
    case socket(Int32)
    case tls(String)
    case osStatus(OSStatus)
    case unexpectedBanner(String)
    case unexpectedAuth(String)
    case authenticationFailed(String)
    case notConnected
    case urlTooLong
    case invalidFrame
    case checksumMismatch
    case negativeAcknowledgement(UInt8)

    var errorDescription: String? {
        switch self {
        case .invalidHost(let host):
            "Invalid host: \(host)"
        case .socket(let code):
            "Socket error: \(String(cString: strerror(code)))"
        case .tls(let message):
            message
        case .osStatus(let status):
            "TLS error: \(status)"
        case .unexpectedBanner(let banner):
            "Unexpected MDC banner: \(banner)"
        case .unexpectedAuth(let auth):
            "Unexpected auth response: \(auth)"
        case .authenticationFailed(let response):
            "Authentication failed: \(response)"
        case .notConnected:
            "Not connected"
        case .urlTooLong:
            "Content URL is too long"
        case .invalidFrame:
            "Invalid MDC response"
        case .checksumMismatch:
            "MDC checksum mismatch"
        case .negativeAcknowledgement(let code):
            "Display rejected command: 0x\(String(format: "%02X", code))"
        }
    }
}
