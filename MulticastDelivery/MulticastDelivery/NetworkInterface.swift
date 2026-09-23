import Darwin

struct NetworkInterface {
    let name: String
    let index: UInt32
    let ipv4Address: in_addr
}
