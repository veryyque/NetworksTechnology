import Foundation

class PeerManager {
    private var peers: [String: Peer] = [:] //UUID копии приложения/структура хранения
    private let timeout: Double

    init(timeout: Double) {
        self.timeout = timeout
    }

    //добавление/обновление копии
    func updatePeer(id: String, ip: String) {
        let oldPeer = peers[id]
        peers[id] = Peer(ip: ip, lastSeen: currentTime())

        if oldPeer == nil {
            print("\nПоявилась копия: \(ip)")
            printPeers()
        } else if oldPeer?.ip != ip {
            print("\nУ копии изменился IP: \(ip)")
            printPeers()
        }
    }

    //удаление копии
    func removeExpiredPeers() {
        var expiredIDs: [String] = []
        let now = currentTime()

        for (id, peer) in peers {
            if now - peer.lastSeen >= timeout {
                expiredIDs.append(id)
            }
        }

        for id in expiredIDs {
            if let peer = peers.removeValue(forKey: id) {
                print("\nИсчезла копия: \(peer.ip)")
            }
        }

        if !expiredIDs.isEmpty {
            printPeers()
        }
    }

    func printPeers() {
        print("Живые копии: \(peers.count)")

        if peers.isEmpty {
            print("  Других копий пока нет.")
            return
        }

        for peer in peers.values {
            print("  \(peer.ip)")
        }
    }

    private func currentTime() -> Double {
        return ProcessInfo.processInfo.systemUptime
    }
}
