import Foundation

enum GregcoinParams {
    static let ticker = "GRC"
    static let name = "Gregcoin"
    static let totalSupply: UInt64 = 42_000_000
    static let blockReward: Double = 100.0
    static let halvingInterval: UInt64 = 210_000
    static let blockTimeSeconds: Int = 150 // 2.5 minutes
    static let addressPrefix = "G"
    static let mainnetPort: UInt16 = 8444
    static let rpcPort: UInt16 = 8445
    static let networkMagic: [UInt8] = [0xd7, 0xc6, 0xb5, 0xa4]

    static let defaultDataDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Gregcoin")
    }()

    static let defaultConfFile: URL = {
        defaultDataDir.appendingPathComponent("gregcoin.conf")
    }()
}
