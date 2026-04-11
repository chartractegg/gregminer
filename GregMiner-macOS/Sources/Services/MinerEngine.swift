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
        // Gregcoin uses bech32 segwit addresses (grc1q...) — build P2WPKH output script
        guard let addrScript = p2wpkhScript(address: miningAddress) else {
            DispatchQueue.main.async { [weak self] in
                self?.onLog?("ERROR: Invalid mining address (must be bech32 grc1q... address)")
            }
            return nil
        }

        let coinbase = buildCoinbase(
            height: tmpl.height,
            value: tmpl.coinbasevalue,
            scriptPubKey: addrScript,
            extraNonce: extraNonce,
            witnessCommitment: tmpl.default_witness_commitment
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
        let hashBytes = Array(hash.reversed())
        for i in 0..<32 {
            if hashBytes[i] < target[i] { return true }
            if hashBytes[i] > target[i] { return false }
        }
        return false
    }

    // MARK: - Address Scripts

    /// Build a P2WPKH scriptPubKey (OP_0 <20-byte-hash>) from a bech32 grc1q... address.
    private func p2wpkhScript(address: String) -> Data? {
        guard let (hrp, decoded) = bech32Decode(address),
              hrp == "grc",
              !decoded.isEmpty,
              decoded[0] == 0 // witness version 0 = P2WPKH / P2WSH
        else { return nil }

        // Convert remaining 5-bit groups → 8-bit bytes
        guard let program = convertBits(Array(decoded.dropFirst()), from: 5, to: 8, pad: false),
              program.count == 20 // P2WPKH requires exactly 20 bytes
        else { return nil }

        var script = Data()
        script.append(0x00) // OP_0
        script.append(0x14) // push 20 bytes
        script.append(contentsOf: program)
        return script
    }

    // MARK: - Bech32 Decoding

    private static let bech32Charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

    /// Decode a bech32 string into (hrp, 5-bit data values without checksum).
    private func bech32Decode(_ str: String) -> (hrp: String, data: [UInt8])? {
        let lower = str.lowercased()
        guard let sepIdx = lower.lastIndex(of: "1") else { return nil }
        let hrp = String(lower[lower.startIndex..<sepIdx])
        let dataPart = String(lower[lower.index(after: sepIdx)...])
        guard !hrp.isEmpty, dataPart.count >= 6 else { return nil }

        var values = [UInt8]()
        for ch in dataPart {
            guard let idx = MinerEngine.bech32Charset.firstIndex(of: ch) else { return nil }
            values.append(UInt8(idx))
        }

        guard bech32VerifyChecksum(hrp: hrp, data: values) else { return nil }

        return (hrp, Array(values.dropLast(6)))
    }

    private func bech32VerifyChecksum(hrp: String, data: [UInt8]) -> Bool {
        return bech32Polymod(bech32HRPExpand(hrp) + data) == 1
    }

    private func bech32HRPExpand(_ hrp: String) -> [UInt8] {
        var result = [UInt8]()
        for scalar in hrp.unicodeScalars { result.append(UInt8(scalar.value >> 5)) }
        result.append(0)
        for scalar in hrp.unicodeScalars { result.append(UInt8(scalar.value & 31)) }
        return result
    }

    private func bech32Polymod(_ values: [UInt8]) -> UInt32 {
        let gen: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk: UInt32 = 1
        for v in values {
            let b = chk >> 25
            chk = (chk & 0x1ffffff) << 5 ^ UInt32(v)
            for i in 0..<5 where (b >> i) & 1 == 1 {
                chk ^= gen[i]
            }
        }
        return chk
    }

    /// Convert between bit-group sizes (e.g. 5→8 for bech32 witness program decoding).
    private func convertBits(_ data: [UInt8], from fromBits: Int, to toBits: Int, pad: Bool) -> [UInt8]? {
        var acc = 0, bits = 0
        var result = [UInt8]()
        let maxv = (1 << toBits) - 1

        for value in data {
            acc = (acc << fromBits) | Int(value)
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }

        if pad {
            if bits > 0 { result.append(UInt8((acc << (toBits - bits)) & maxv)) }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            return nil // non-zero padding
        }

        return result
    }

    // MARK: - Coinbase Builder

    /// Build the coinbase transaction.
    /// When `witnessCommitment` is provided (GBT's `default_witness_commitment` hex scriptPubKey),
    /// a second zero-value output is added as required by BIP 141 for segwit blocks.
    private func buildCoinbase(height: Int, value: Int, scriptPubKey: Data,
                               extraNonce: UInt32, witnessCommitment: String? = nil) -> Data {
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
        // Previous outpoint (null — coinbase)
        tx.append(Data(repeating: 0, count: 32))
        tx.append(contentsOf: withUnsafeBytes(of: UInt32(0xFFFFFFFF).littleEndian) { Data($0) })
        // ScriptSig
        tx.append(varint(UInt64(scriptSig.count)))
        tx.append(scriptSig)
        // Sequence
        tx.append(contentsOf: withUnsafeBytes(of: UInt32(0xFFFFFFFF).littleEndian) { Data($0) })

        // Outputs
        let commitScript = witnessCommitment.flatMap { Data(hexString: $0) }
        tx.append(varint(commitScript != nil ? 2 : 1))

        // Output 0: mining reward → miner's address
        tx.append(contentsOf: withUnsafeBytes(of: Int64(value).littleEndian) { Data($0) })
        tx.append(varint(UInt64(scriptPubKey.count)))
        tx.append(scriptPubKey)

        // Output 1: segwit witness commitment (BIP 141) — zero value, OP_RETURN scriptPubKey
        if let cs = commitScript {
            tx.append(contentsOf: withUnsafeBytes(of: Int64(0).littleEndian) { Data($0) })
            tx.append(varint(UInt64(cs.count)))
            tx.append(cs)
        }

        // Locktime
        tx.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })

        return tx
    }

    // MARK: - Encoding Helpers

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
