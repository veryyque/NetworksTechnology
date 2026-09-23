import Darwin

struct AppError: Error {
    let message: String
}

final class Utils {
    static let port: UInt16 = 50000
    static let heartbeatInterval = 2.0
    static let peerTimeout = 6.0
    static let messagePrefix = "MULTICAST_DISCOVERY"

    private init() {}

    static func check(_ result: Int32, _ operation: String) throws {
        if result == -1 {
            throw AppError(message: "\(operation): \(String(cString: strerror(errno)))")
        }
    }
}
