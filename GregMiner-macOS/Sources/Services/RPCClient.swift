import Foundation

/// JSON-RPC client for communicating with gregcoind
actor RPCClient {
    private let url: URL
    private let auth: String
    private var requestID: Int = 0
    private let session: URLSession

    init(host: String, port: UInt16, user: String, password: String) {
        self.url = URL(string: "http://\(host):\(port)/")!
        let creds = Data("\(user):\(password)".utf8).base64EncodedString()
        self.auth = "Basic \(creds)"

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    func call<T: Decodable>(_ method: String, params: [Any] = []) async throws -> T {
        requestID += 1
        let body: [String: Any] = [
            "id": requestID,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(auth, forHTTPHeaderField: "Authorization")

        let (responseData, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RPCError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]

        if let error = json?["error"] as? [String: Any], error["code"] != nil {
            let code = error["code"] as? Int ?? -1
            let message = error["message"] as? String ?? "Unknown error"
            throw RPCError.rpcError(code: code, message: message)
        }

        guard httpResponse.statusCode == 200 || json?["result"] != nil else {
            throw RPCError.httpError(statusCode: httpResponse.statusCode)
        }

        // Handle null result
        if json?["result"] is NSNull {
            if let empty = Optional<String>.none as? T {
                return empty
            }
        }

        let resultData: Data
        if let result = json?["result"] {
            resultData = try JSONSerialization.data(withJSONObject: result)
        } else {
            throw RPCError.noResult
        }

        return try JSONDecoder().decode(T.self, from: resultData)
    }

    /// Convenience for calls that return raw JSON values
    func callRaw(_ method: String, params: [Any] = []) async throws -> Any {
        requestID += 1
        let body: [String: Any] = [
            "id": requestID,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(auth, forHTTPHeaderField: "Authorization")

        let (responseData, _) = try await session.data(for: request)
        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]

        if let error = json?["error"] as? [String: Any], error["code"] != nil {
            let code = error["code"] as? Int ?? -1
            let message = error["message"] as? String ?? "Unknown error"
            throw RPCError.rpcError(code: code, message: message)
        }

        guard let result = json?["result"] else {
            throw RPCError.noResult
        }

        return result
    }

    /// Fire-and-forget call (e.g., submitblock)
    func callVoid(_ method: String, params: [Any] = []) async throws {
        let _: String? = try? await call(method, params: params)
        // submitblock returns null on success
    }
}

enum RPCError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case rpcError(code: Int, message: String)
    case noResult

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from node"
        case .httpError(let code): return "HTTP error \(code)"
        case .rpcError(_, let message): return message
        case .noResult: return "No result in response"
        }
    }
}

// MARK: - RPC Response Models

struct BlockchainInfo: Codable {
    let chain: String
    let blocks: Int
    let headers: Int
    let bestblockhash: String
    let difficulty: Double
    let mediantime: Int?
    let verificationprogress: Double?
    let initialblockdownload: Bool?
    let chainwork: String?
    let warnings: String?
}

struct NetworkInfo: Codable {
    let version: Int
    let subversion: String
    let protocolversion: Int
    let connections: Int
    let connections_in: Int?
    let connections_out: Int?
    let networkactive: Bool?
    let warnings: String?
}

struct PeerInfo: Codable {
    let id: Int
    let addr: String
    let subver: String?
    let version: Int?
    let inbound: Bool
    let synced_headers: Int?
    let synced_blocks: Int?
}

struct MempoolInfo: Codable {
    let loaded: Bool?
    let size: Int
    let bytes: Int?
    let usage: Int?
}

struct WalletTransaction: Codable, Identifiable {
    let txid: String
    let category: String
    let amount: Double
    let confirmations: Int
    let time: Int?
    let address: String?
    let label: String?
    let fee: Double?
    let blockhash: String?

    var id: String { "\(txid)-\(category)-\(amount)" }

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(time ?? 0))
    }
}

struct BlockTemplate: Codable {
    let version: Int
    let previousblockhash: String
    let transactions: [BlockTemplateTx]
    let coinbasevalue: Int
    let target: String?
    let bits: String
    let height: Int
    let curtime: Int
    let default_witness_commitment: String? // present when segwit txs exist in mempool

    struct BlockTemplateTx: Codable {
        let data: String
        let txid: String
        let hash: String?
        let fee: Int?
        let sigops: Int?
    }
}
