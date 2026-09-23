import Foundation
import Darwin

enum Application {
    static func run() {
        do {
            let config = try CommandLineParser.parse(CommandLine.arguments)

            let peerManager = PeerManager(
                timeout: Utils.peerTimeout
            )

            let service = try MulticastService(
                group: config.group,
                family: config.family,
                peerManager: peerManager
            )

            try service.run()

        } catch let error as AppError {
            print("Ошибка: \(error.message)")
            exit(1)

        } catch {
            print("Ошибка: \(error)")
            exit(1)
        }
    }
}
