import Darwin

struct AppConfiguration {
    let group: String
    let family: Int32
}

final class CommandLineParser {
    private init() {}

    static func parse(_ arguments: [String]) throws -> AppConfiguration {
        if arguments.count != 2 {
            throw AppError(
                message: "Использование: MulticastDelivery <multicast-адрес>\n" +
                         "IPv4: MulticastDelivery 239.255.0.1\n" +
                         "IPv6: MulticastDelivery ff12::4242"
            )
        }

        let group = arguments[1]
        var address4 = in_addr()
        var address6 = in6_addr()

        if inet_pton(AF_INET, group, &address4) == 1 { //перевод айпи в биты
            let firstByte = UInt32(bigEndian: address4.s_addr) >> 24
            if firstByte < 224 || firstByte > 239 {
                throw AppError(message: "IPv4 multicast должен начинаться с числа от 224 до 239")
            }
            return AppConfiguration(group: group, family: AF_INET)
        }

        if inet_pton(AF_INET6, group, &address6) == 1 {
            let firstByte = withUnsafeBytes(of: address6) { bytes in
                return bytes[0]
            }
            if firstByte != 0xff {
                throw AppError(message: "IPv6 multicast-адрес должен начинаться с ff")
            }
            return AppConfiguration(group: group, family: AF_INET6)
        }

        throw AppError(message: "Передан некорректный IP-адрес")
    }
}
