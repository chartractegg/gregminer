import Foundation
import CommonCrypto

/// CPU mining engine — ports the Python mining logic to Swift
class MinerEngine: ObservableObject {
    @Published var isRunning = false
    @Published var hashrate: Double = 0
    @Published var blocksFound: Int = 0
    @Published var uptime: TimeInterval = 0
    @Published var lastError: String?

    private var rpcClient: RPCClient?
    private var miningAddress: String = ""
    private var shouldStop = false
    private var startTime: Date?
    private var uptimeTimer: Timer?
    private var extraNonce: UInt32 = 0
    private let miningQueue = DispatchQueue(label: "mining", qos: .utility)

    var onBlockFound: ((String) -> Void)?
    var onLog: ((String) -> Void)?

    func start(rpc: RPCClient, address: String) {
        guard !isRunning else { return }
        rpcClient = rpc
        miningAddress = address
        shouldStop = false
        isRunning = true
        blocksFound = 0
        hashrate = 0
        startTime = Date()
        lastError = nil

        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            if let start = self?.startTime {
                self?.uptime = Date().timeIntervalSince(start)
            }
        }

        miningQueue.async { [weak self] in
            self?.miningLoop()
        }
    }

    func stop() {
        shouldStop = true
        isRunning = false
        uptimeTimer?.invalidate()
        uptimeTimer = nil
    }

    // MARK: - Mining Loop

    private func miningLoop() {
        while !shouldStop {
            guard let rpc = rpcClient else { break }

            // Get block template
            var template: BlockTemplate?
            let sem = DispatchSemaphore(value: 0)
            Task {
                do {
                    template = try await rpc.call("getblocktemplate", params: [["rules": ["segwit"]]])
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        self?.lastError = error.localizedDescription
                        self?.onLog?("ERROR: \(error.localizedDescription)")
                    }
                }
                sem.signal()
            }
            sem.wait()

            guard let tmpl = template, !shouldStop else {
                if !shouldStop { Thread.sleep(forTimeInterval: 5) }
                continue
            }

            extraNonce += 1

            // Build block
            guard let (header76, beforeHex, afterHex) = buildBlock(template: tmpl) else {
                Thread.sleep(forTimeInterval: 2)
                continue
            }

            // Mine
            let target = bitsToTarget(tmpl.bits)
            let found = mineRange(header76: header76, target: target, bits: tmpl.bits)

            if let (nonce, blockHash) = found {
                let blockHex = beforeHex + nonceHex(nonce) + afterHex

                // Submit block
                let submitSem = DispatchSemaphore(value: 0)
                Task {
                    do {
                        try await rpc.callVoid("submitblock", params: [blockHex])
                        DispatchQueue.main.async { [weak self] in
                            self?.blocksFound += 1
                            self?.onBlockFound?(blockHash)
                            self?.onLog?("BLOCK FOUND! \(blockHash.prefix(20))...")
                        }
                    } catch {
                        DispatchQueue.main.async { [weak self] in
                            self?.onLog?("Submit error: \(error.localizedDescription)")
                        }
                    }
                    submitSem.signal()
                }
                submitSem.wait()
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
        }
    }

    // MARK: - Block Building

    private func buildBlock(template tmpl: BlockTemplate) -> (Data, String, String)? {
        let addressScript = p2pkhScript(address: miningAddress)
        guard let addrScript = addressScript else {
            DispatchQueue.main.async { [weak self] in
                self?.onLog?("ERROR: Invalid mining address")
            }
            return nil
        }

        let coinbase = buildCoinbase(
            height: tmpl.height,
            value: tmpl.coinbasevalue,
            scriptPubKey: addrScript,
            extraNonce: extraNonce
        )

        var txids: [Data] = [sha256d(coinbase)]
        var txdata: [Data] = [coinbase]

        for tx in tmpl.transactions {
            txdata.append(Data(hexString: tx.data)!)
            txids.append(Data(hexString: tx.txid)!.reversed())
        }

        let mr = merkleRoot(txids)
        let prev = Data(Data(hexString: tmpl.previousblockhash)!.reversed())
        let bitsBytes = Data(Data(hexString: tmpl.bits)!.reversed())

        var header76 = Data()
        header76.append(contentsOf: withUnsafeBytes(of: UInt32(tmpl.version).littleEndian) { Data($0) })
        header76.append(prev)
        header76.append(mr)
        header76.append(contentsOf: withUnsafeBytes(of: UInt32(tmpl.curtime).littleEndian) { Data($0) })
        header76.append(bitsBytes)

        assert(header76.count == 76)

        var suffix = Data()
        suffix.append(varint(UInt64(txdata.count)))
        for tx in txdata {
            suffix.append(tx)
        }

        return (header76, header76.hexString, suffix.hexString)
    }

    // MARK: - Mining Core

    private func mineRange(header76: Data, target: [UInt8], bits: String) -> (UInt32, String)? {
        var header = header76 + Data(repeating: 0, count: 4) // 80 bytes
        var hashCount: UInt64 = 0
        let reportInterval: UInt64 = 50_000
        var lastReport = DispatchTime.now()

        var nonce: UInt32 = 0
        while nonce < UInt32.max && !shouldStop {
            // Set nonce at offset 76
            header.withUnsafeMutableBytes { buf in
                buf.storeBytes(of: nonce.littleEndian, toByteOffset: 76, as: UInt32.self)
            }

            let hash = sha256d(header)
            // Compare hash (reversed) against target
            if hashLessThanTarget(hash: hash, target: target) {
                let blockHash = Data(hash.reversed()).hexString
                return (nonce, blockHash)
            }

            nonce += 1
            hashCount += 1

            if hashCount % reportInterval == 0 {
                let now = DispatchTime.now()
                let elapsed = Double(now.uptimeNanoseconds - lastReport.uptimeNanoseconds) / 1_000_000_000
                if elapsed > 0 {
                    let rate = Double(reportInterval) / elapsed
                    DispatchQueue.main.async { [weak self] in
                        self?.hashrate = rate
                    }
                }
                lastReport = now
            }
        }

        return nil
    }

    // MARK: - Crypto Helpers

    private func sha256d(_ data: Data) -> Data {
        var firstHash = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        var secondHash = Data(count: Int(CC_SHA256_DIGEST_LENGTH))

        data.withUnsafeBytes { buf in
            firstHash.withUnsafeMutableBytes { out in
                CC_SHA256(buf.baseAddress, CC_LONG(data.count), out.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        firstHash.withUnsafeBytes { buf in
            secondHash.withUnsafeMutableBytes { out in
                CC_SHA256(buf.baseAddress, CC_LONG(firstHash.count), out.bindMemory(to: UInt8.self).baseAddress)
            }
        }

        return secondHash
    }

    private func merkleRoot(_ txids: [Data]) -> Data {
        if txids.isEmpty { return Data(repeating: 0, count: 32) }
        var layer = txids
        while layer.count > 1 {
            if layer.count % 2 == 1 {
                layer.append(layer.last!)
            }
            var next: [Data] = []
            for i in stride(from: 0, to: layer.count, by: 2) {
                next.append(sha256d(layer[i] + layer[i + 1]))
            }
            layer = next
        }
        return layer[0]
    }

    private func bitsToTarget(_ bitsHex: String) -> [UInt8] {
        let nbits = UInt32(bitsHex, radix: 16)!
        let exp = Int((nbits >> 24) & 0xFF)
        let mant = nbits & 0x007FFFFF

        // Build 32-byte target
        var target = [UInt8](repeating: 0, count: 32)
        let mantBytes = [
            UInt8((mant >> 16) & 0xFF),
            UInt8((mant >> 8) & 0xFF),
            UInt8(mant & 0xFF)
        ]

        let startIdx = 32 - exp
        for i in 0..<3 {
            let idx = startIdx + i
            if idx >= 0 && idx < 32 {
                target[idx] = mantBytes[i]
            }
        }

        return target
    }

    private func hashLessThanTarget(hash: Data, target: [UInt8]) -> Bool {
        // Hash is in internal byte order; compare reversed (big-endian)
        let hashBytes = Array(hash.reversed())
        for i in 0..<32 {
            if hashBytes[i] < target[i] { return true }
            if hashBytes[i] > target[i] { return false }
        }
        return false
    }

    private func p2pkhScript(address: String) -> Data? {
        let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        var n = BigUInt.zero
        for ch in address {
            guard let idx = alphabet.firstIndex(of: ch) else { return nil }
            n = n * 58 + BigUInt(alphabet.distance(from: alphabet.startIndex, to: idx))
        }

        // Convert to 25 bytes
        var raw = [UInt8](repeating: 0, count: 25)
        var temp = n
        for i in stride(from: 24, through: 0, by: -1) {
            raw[i] = UInt8(temp % 256)
            temp = temp / 256
        }

        let hash160 = Data(raw[1..<21])
        var script = Data()
        script.append(0x76) // OP_DUP
        script.append(0xa9) // OP_HASH160
        script.append(0x14) // Push 20 bytes
        script.append(hash160)
        script.append(0x88) // OP_EQUALVERIFY
        script.append(0xac) // OP_CHECKSIG
        return script
    }

    private func buildCoinbase(height: Int, value: Int, scriptPubKey: Data, extraNonce: UInt32) -> Data {
        let heightBytes: Data = {
            var h = height
            var bytes = Data()
            while h > 0 {
                bytes.append(UInt8(h & 0xFF))
                h >>= 8
            }
            if bytes.isEmpty { bytes.append(0) }
            return bytes
        }()

        var scriptSig = Data()
        scriptSig.append(UInt8(heightBytes.count))
        scriptSig.append(heightBytes)
        let en = withUnsafeBytes(of: extraNonce.littleEndian) { Data($0) }
        scriptSig.append(UInt8(en.count))
        scriptSig.append(en)

        var tx = Data()
        // Version
        tx.append(contentsOf: withUnsafeBytes(of: Int32(1).littleEndian) { Data($0) })
        // Input count
        tx.append(varint(1))
        // Previous outpoint (null)
        tx.append(Data(repeating: 0, count: 32))
        tx.append(contentsOf: withUnsafeBytes(of: UInt32(0xFFFFFFFF).littleEndian) { Data($0) })
        // Script sig
        tx.append(varint(UInt64(scriptSig.count)))
        tx.append(scriptSig)
        // Sequence
        tx.append(contentsOf: withUnsafeBytes(of: UInt32(0xFFFFFFFF).littleEndian) { Data($0) })
        // Output count
        tx.append(varint(1))
        // Value
        tx.append(contentsOf: withUnsafeBytes(of: Int64(value).littleEndian) { Data($0) })
        // Script pubkey
        tx.append(varint(UInt64(scriptPubKey.count)))
        tx.append(scriptPubKey)
        // Locktime
        tx.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })

        return tx
    }

    private func varint(_ n: UInt64) -> Data {
        if n < 0xfd {
            return Data([UInt8(n)])
        } else if n <= 0xFFFF {
            var d = Data([0xfd])
            d.append(contentsOf: withUnsafeBytes(of: UInt16(n).littleEndian) { Data($0) })
            return d
        } else if n <= 0xFFFFFFFF {
            var d = Data([0xfe])
            d.append(contentsOf: withUnsafeBytes(of: UInt32(n).littleEndian) { Data($0) })
            return d
        } else {
            var d = Data([0xff])
            d.append(contentsOf: withUnsafeBytes(of: n.littleEndian) { Data($0) })
            return d
        }
    }

    private func nonceHex(_ nonce: UInt32) -> String {
        withUnsafeBytes(of: nonce.littleEndian) { Data($0) }.hexString
    }
}

// MARK: - Minimal BigUInt for base58 decoding

struct BigUInt {
    private var digits: [UInt32] // Base 2^32 digits, least significant first

    static let zero = BigUInt(digits: [0])

    init(_ value: Int) {
        digits = [UInt32(value)]
    }

    private init(digits: [UInt32]) {
        self.digits = digits
    }

    static func * (lhs: BigUInt, rhs: Int) -> BigUInt {
        var carry: UInt64 = 0
        var result: [UInt32] = []
        for d in lhs.digits {
            let prod = UInt64(d) * UInt64(rhs) + carry
            result.append(UInt32(prod & 0xFFFFFFFF))
            carry = prod >> 32
        }
        while carry > 0 {
            result.append(UInt32(carry & 0xFFFFFFFF))
            carry >>= 32
        }
        return BigUInt(digits: result)
    }

    static func + (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        let maxLen = max(lhs.digits.count, rhs.digits.count)
        var carry: UInt64 = 0
        var result: [UInt32] = []
        for i in 0..<maxLen {
            let a = i < lhs.digits.count ? UInt64(lhs.digits[i]) : 0
            let b = i < rhs.digits.count ? UInt64(rhs.digits[i]) : 0
            let sum = a + b + carry
            result.append(UInt32(sum & 0xFFFFFFFF))
            carry = sum >> 32
        }
        if carry > 0 { result.append(UInt32(carry)) }
        return BigUInt(digits: result)
    }

    static func % (lhs: BigUInt, rhs: Int) -> Int {
        var remainder: UInt64 = 0
        for d in lhs.digits.reversed() {
            remainder = (remainder << 32 + UInt64(d)) % UInt64(rhs)
        }
        return Int(remainder)
    }

    static func / (lhs: BigUInt, rhs: Int) -> BigUInt {
        var remainder: UInt64 = 0
        var result = [UInt32](repeating: 0, count: lhs.digits.count)
        for i in (0..<lhs.digits.count).reversed() {
            let cur = remainder << 32 + UInt64(lhs.digits[i])
            result[i] = UInt32(cur / UInt64(rhs))
            remainder = cur % UInt64(rhs)
        }
        // Remove leading zeros
        while result.count > 1 && result.last == 0 {
            result.removeLast()
        }
        return BigUInt(digits: result)
    }
}

// MARK: - Data Hex Extensions

extension Data {
    init?(hexString: String) {
        let hex = hexString.dropFirst(hexString.hasPrefix("0x") ? 2 : 0)
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    func reversed() -> Data {
        Data(Array(self).reversed())
    }
}
