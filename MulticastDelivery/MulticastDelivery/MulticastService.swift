import Foundation
import Darwin

class MulticastService {
    private let id = UUID().uuidString
    private let group: String
    private let family: Int32
    private let peerManager: PeerManager
    private let networkInterface: NetworkInterface

    private var socketFD: Int32 = -1
    private var destination4 = sockaddr_in() //адрес назначения
    private var destination6 = sockaddr_in6()

    init(group: String, family: Int32, peerManager: PeerManager) throws {
        self.group = group
        self.family = family
        self.peerManager = peerManager
        self.networkInterface = try MulticastService.findInterface(family: family)

        socketFD = socket(family, SOCK_DGRAM, IPPROTO_UDP) //создаю датагнраммный UDP сокет
        try Utils.check(socketFD, "Создание UDP-сокета")

        do {
            var yes: Int32 = 1 //индикатор включения
            let size = socklen_t(MemoryLayout<Int32>.size) //размер индикатора
            try Utils.check(setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &yes, size), "SO_REUSEADDR") //настройка сокету разрешения на повторное использ адреса
            try Utils.check(setsockopt(socketFD, SOL_SOCKET, SO_REUSEPORT, &yes, size), "SO_REUSEPORT")

            if family == AF_INET { //настройка в зависимости от типа айпи
                try configureIPv4()
            } else {
                try configureIPv6()
            }

            let flags = fcntl(socketFD, F_GETFL, 0)
            try Utils.check(flags, "Чтение флагов сокета")
            try Utils.check(fcntl(socketFD, F_SETFL, flags | O_NONBLOCK), "Неблокирующий режим") //recvfrom не ждёт бесконечно, если сообщений нет
        } catch {
            close(socketFD)
            socketFD = -1
            throw error
        }
    }

    deinit {
        if socketFD >= 0 {
            close(socketFD)
        }
    }

    private func configureIPv4() throws {
        var groupAddress = in_addr()
        inet_pton(AF_INET, group, &groupAddress)

        var local = sockaddr_in() //локальный адрес сокета
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = Utils.port.bigEndian
        local.sin_addr.s_addr = INADDR_ANY //принимать UDP пакеты на порт пришедшие на любой локальный IPv4-адрес

        let bindResult = withUnsafePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                Darwin.bind(socketFD, address, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try Utils.check(bindResult, "Привязка к UDP-порту \(Utils.port)")

        var membership = ip_mreq() //системная структура запроса на вступление в IPv4 multicast-группу.
        membership.imr_multiaddr = groupAddress
        membership.imr_interface = networkInterface.ipv4Address //адрес лок интерфейса
        try Utils.check(setsockopt(socketFD, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership, socklen_t(MemoryLayout<ip_mreq>.size)), "Вступление в IPv4-группу")

        var interfaceAddress = networkInterface.ipv4Address
        try Utils.check(setsockopt(socketFD, IPPROTO_IP, IP_MULTICAST_IF, &interfaceAddress, socklen_t(MemoryLayout<in_addr>.size)), "Выбор IPv4-интерфейса") //для отправки пакетов

        var one: UInt8 = 1
        try Utils.check(setsockopt(socketFD, IPPROTO_IP, IP_MULTICAST_TTL, &one, 1), "IPv4 TTL") //установка Time to live пакета
        try Utils.check(setsockopt(socketFD, IPPROTO_IP, IP_MULTICAST_LOOP, &one, 1), "IPv4 loopback")

        destination4.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination4.sin_family = sa_family_t(AF_INET)
        destination4.sin_port = Utils.port.bigEndian
        destination4.sin_addr = groupAddress
    }

    private func configureIPv6() throws {
        var groupAddress = in6_addr()
        inet_pton(AF_INET6, group, &groupAddress)

        var local = sockaddr_in6()
        local.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        local.sin6_family = sa_family_t(AF_INET6)
        local.sin6_port = Utils.port.bigEndian

        let bindResult = withUnsafePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                Darwin.bind(socketFD, address, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        try Utils.check(bindResult, "Привязка к UDP-порту \(Utils.port)")

        var membership = ipv6_mreq()
        membership.ipv6mr_multiaddr = groupAddress
        membership.ipv6mr_interface = networkInterface.index
        try Utils.check(setsockopt(socketFD, IPPROTO_IPV6, IPV6_JOIN_GROUP, &membership, socklen_t(MemoryLayout<ipv6_mreq>.size)), "Вступление в IPv6-группу")

        var index = networkInterface.index
        try Utils.check(setsockopt(socketFD, IPPROTO_IPV6, IPV6_MULTICAST_IF, &index, socklen_t(MemoryLayout<UInt32>.size)), "Выбор IPv6-интерфейса") //выбираю интерфейс через индекс

        var hops: Int32 = 1
        var loop: UInt32 = 1
        try Utils.check(setsockopt(socketFD, IPPROTO_IPV6, IPV6_MULTICAST_HOPS, &hops, socklen_t(MemoryLayout<Int32>.size)), "IPv6 hop limit")
        try Utils.check(setsockopt(socketFD, IPPROTO_IPV6, IPV6_MULTICAST_LOOP, &loop, socklen_t(MemoryLayout<UInt32>.size)), "IPv6 loopback")

        destination6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        destination6.sin6_family = sa_family_t(AF_INET6)
        destination6.sin6_port = Utils.port.bigEndian
        destination6.sin6_addr = groupAddress
        destination6.sin6_scope_id = networkInterface.index
    }

    private func sendHeartbeat() throws {
        let bytes = Array("\(Utils.messagePrefix)|\(id)".utf8) //сообщение + UUID текущего запуска
        let sent: Int

        if family == AF_INET {
            sent = withUnsafePointer(to: &destination4) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    sendto(socketFD, bytes, bytes.count, 0, address, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        } else {
            sent = withUnsafePointer(to: &destination6) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    sendto(socketFD, bytes, bytes.count, 0, address, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            } //sendto - отправка датаграммы
        }

        if sent == -1 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
            throw AppError(message: "Ошибка отправки: \(String(cString: strerror(errno)))")
        }
    }

    private func receiveMessages() throws {
        for _ in 0..<32 { //обработка 32 пакетов за раз
            var buffer = [UInt8](repeating: 0, count: 512)
            var sender = sockaddr_storage()
            var senderLength = socklen_t(MemoryLayout<sockaddr_storage>.size)

            let count = withUnsafeMutablePointer(to: &sender) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    recvfrom(socketFD, &buffer, buffer.count, 0, address, &senderLength)
                }
            }

            if count == -1 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                if errno == EINTR { continue }
                throw AppError(message: "Ошибка приёма: \(String(cString: strerror(errno)))")
            }

            guard let message = String(bytes: buffer.prefix(count), encoding: .utf8) else { continue }
            let parts = message.components(separatedBy: "|")
            if parts.count != 2 || parts[0] != Utils.messagePrefix || parts[1] == id { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = withUnsafePointer(to: &sender) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    getnameinfo(address, senderLength, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) //получение IP
                }
            }

            if result == 0 {
                peerManager.updatePeer(id: parts[1], ip: String(cString: host))
            }
        }
    }

    func run() throws {
        print("Группа: \(group), порт: \(Utils.port)")
        print("Протокол: \(family == AF_INET ? "IPv4" : "IPv6")")
        print("Интерфейс: \(networkInterface.name)")
        print("Остановка: Ctrl+C или Stop в Xcode")
        peerManager.printPeers()

        var nextHeartbeat = 0.0

        while true {
            let now = ProcessInfo.processInfo.systemUptime
            if now >= nextHeartbeat {
                try sendHeartbeat()
                nextHeartbeat = now + Utils.heartbeatInterval
            }

            try receiveMessages()
            peerManager.removeExpiredPeers()

            var descriptor = pollfd(fd: socketFD, events: Int16(POLLIN), revents: 0)
            let result = poll(&descriptor, 1, 200)
            if result == -1 && errno != EINTR {
                try Utils.check(result, "Ожидание UDP-пакета")
            }
        }
    }

    private static func findInterface(family: Int32) throws -> NetworkInterface {
        var first: UnsafeMutablePointer<ifaddrs>?
        try Utils.check(getifaddrs(&first), "Получение сетевых интерфейсов")
        defer { freeifaddrs(first) }

        var current = first
        while let pointer = current {
            let item = pointer.pointee
            current = item.ifa_next
            guard let address = item.ifa_addr else { continue }

            let name = String(cString: item.ifa_name)
            if !name.hasPrefix("en") { continue }
            if Int32(address.pointee.sa_family) != family { continue }
            if item.ifa_flags & UInt32(IFF_UP) == 0 { continue }
            if item.ifa_flags & UInt32(IFF_MULTICAST) == 0 { continue }

            var ipv4Address = in_addr()
            if family == AF_INET {
                ipv4Address = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    return $0.pointee.sin_addr
                }
            }

            let index = if_nametoindex(item.ifa_name)
            if index != 0 {
                return NetworkInterface(name: name, index: index, ipv4Address: ipv4Address)
            }
        }

        throw AppError(message: "Не найден активный Wi-Fi/Ethernet-интерфейс с поддержкой multicast")
    }

}
