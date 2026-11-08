import Foundation

/// The self-hosted telesrv server this client is built for.
///
/// It runs a single backend: every datacenter id resolves to one address, and the server's
/// help.getConfig is the only source of further datacenter addresses.
enum TelesrvServer {
    static let address = "167.104.102.244"
    static let port: UInt16 = 2398

    /// Datacenter ids seeded with `address`. The server's canonical id is 2 (`TELESRV_DC`), but an
    /// account record, a migrate error or a test-environment account may name any of the ids the
    /// official network uses, and each of them must still reach this server.
    static let seedDatacenterIds: [Int] = [1, 2, 3, 4, 5]

    /// The datacenter a fresh, never-authorized account starts on.
    static let initialDatacenterId: Int = 2
}
