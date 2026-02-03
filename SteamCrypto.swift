import Foundation
import CommonCrypto

struct SteamCodeResult {
    let code: String
    let progress: Float
}

class SteamCrypto {
    
    static func generateCode(sharedSecret: String, time: Int64 = Int64(Date().timeIntervalSince1970)) -> SteamCodeResult? {
        guard let secretData = Data(base64Encoded: sharedSecret) else { return nil }
        
        var timeInterval = time / 30
        let timeData = withUnsafeBytes(of: timeInterval.bigEndian) { Data($0) }
        
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        secretData.withUnsafeBytes { secretBytes in
            timeData.withUnsafeBytes { timeBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1), secretBytes.baseAddress, secretData.count, timeBytes.baseAddress, timeData.count, &hmac)
            }
        }
        
        let start = Int(hmac[19] & 0x0f)
        let b1 = UInt32(hmac[start] & 0x7f)
        let b2 = UInt32(hmac[start + 1])
        let b3 = UInt32(hmac[start + 2])
        let b4 = UInt32(hmac[start + 3])
        
        var fullCode = (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
        
        let chars = Array("23456789BCDFGHJKMNPQRTVWXY")
        var code = ""
        for _ in 0..<5 {
            code += String(chars[Int(fullCode) % chars.count])
            fullCode /= UInt32(chars.count)
        }
        
        let progress = Float(30 - (time % 30)) / 30.0
        return SteamCodeResult(code: code, progress: progress)
    }
    
    static func generateConfirmationHash(identitySecret: String, time: Int64, tag: String) -> String? {
        guard let secretData = Data(base64Encoded: identitySecret) else { return nil }
        var timeBigEndian = time.bigEndian
        let timeData = Data(bytes: &timeBigEndian, count: 8)
        guard let tagData = tag.data(using: .utf8) else { return nil }
        let dataToSign = timeData + tagData
        
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        secretData.withUnsafeBytes { sb in
            dataToSign.withUnsafeBytes { db in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1), sb.baseAddress, secretData.count, db.baseAddress, dataToSign.count, &hmac)
            }
        }
        return Data(hmac).base64EncodedString()
    }
}
