import Foundation

enum JWTDecode {
    static func base64UrlToData(_ s: String) -> Data? {
        var str = s.replacingOccurrences(of: "-", with: "+")
                    .replacingOccurrences(of: "_", with: "/")
        let pad = 4 - str.count % 4
        if pad < 4 { str += String(repeating: "=", count: pad) }
        return Data(base64Encoded: str)
    }

    static func decodePayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2,
              let data = base64UrlToData(String(parts[1])),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }
}

