import Darwin
import Foundation

enum LocalNetwork {
    static func wifiIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        var pointer = interfaces
        while pointer != nil {
            guard let interface = pointer?.pointee else {
                pointer = pointer?.pointee.ifa_next
                continue
            }

            let name = String(cString: interface.ifa_name)
            let family = interface.ifa_addr.pointee.sa_family
            if name == "en0", family == UInt8(AF_INET) {
                var address = interface.ifa_addr.pointee
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    &address,
                    socklen_t(interface.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                return String(cString: hostname)
            }

            pointer = interface.ifa_next
        }

        return nil
    }
}
