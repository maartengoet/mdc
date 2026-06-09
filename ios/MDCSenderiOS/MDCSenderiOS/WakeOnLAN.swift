import Darwin
import Foundation

enum WakeOnLAN {
    static func send(mac: String) throws {
        let bytes = try parse(mac: mac)
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: bytes)
        }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw WakeOnLANError.socket(errno)
        }
        defer { Darwin.close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(9).bigEndian
        inet_pton(AF_INET, "255.255.255.255", &address.sin_addr)

        let sent = packet.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buffer.baseAddress, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else {
            throw WakeOnLANError.socket(errno)
        }
    }

    private static func parse(mac: String) throws -> [UInt8] {
        let cleaned = mac
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count == 12 else {
            throw WakeOnLANError.invalidMAC
        }

        var bytes: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
                throw WakeOnLANError.invalidMAC
            }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}

enum WakeOnLANError: LocalizedError {
    case invalidMAC
    case socket(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidMAC:
            "Invalid MAC address"
        case .socket(let code):
            "Wake-on-LAN socket error: \(String(cString: strerror(code)))"
        }
    }
}
