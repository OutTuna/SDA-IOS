import Foundation
import CommonCrypto
import SwiftUI

// manifest.json содержит:
//   entries[n].encryption_iv   — base64, IV для AES
//   entries[n].encryption_salt — base64, salt для PBKDF2
//   entries[n].filename        — имя .maFile
//
// .maFile содержит сырые зашифрованные байты (НЕ JSON-обёртку)
//
// Алгоритм:
//   Key = PBKDF2-HMAC-SHA1(password, salt, 10000 iter, 32 bytes)
//   Cipher = AES-256-CBC + PKCS7

struct SDAManifest: Decodable {
    let encrypted: Bool?
    let entries: [SDAManifestEntry]
}

struct SDAManifestEntry: Decodable {
    let filename: String
    let steamid: Int64?
    let encryption_iv: String?
    let encryption_salt: String?
}

enum MaFileError: LocalizedError {
    case manifestMissing
    case manifestInvalidJSON
    case noEncryptionDataInManifest
    case invalidBase64(String)
    case keyDerivationFailed
    case decryptionFailed(CCCryptorStatus)
    case wrongPassword

    var errorDescription: String? {
        switch self {
        case .manifestMissing:              return "Не найден manifest.json рядом с .maFile"
        case .manifestInvalidJSON:          return "manifest.json повреждён"
        case .noEncryptionDataInManifest:   return "В manifest.json нет IV/salt для этого файла"
        case .invalidBase64(let f):         return "Не удалось декодировать base64: \(f)"
        case .keyDerivationFailed:          return "Ошибка формирования ключа (PBKDF2)"
        case .decryptionFailed(let s):      return "Ошибка AES расшифровки (код \(s))"
        case .wrongPassword:               return "Неверный пароль"
        }
    }
}

struct EncryptedMaFileBundle {
    let maFileData: Data
    let filename: String
    let iv: Data
    let salt: Data
}

struct EncryptedMaFileManager {

    static func isEncrypted(_ data: Data) -> Bool {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["shared_secret"] != nil {
            return false
        }
        return true
    }

    static func readManifest(data: Data, forFilename filename: String) throws -> (iv: Data, salt: Data) {
        let manifest: SDAManifest
        do {
            manifest = try JSONDecoder().decode(SDAManifest.self, from: data)
        } catch {
            throw MaFileError.manifestInvalidJSON
        }

        guard let entry = manifest.entries.first(where: { $0.filename == filename }),
              let ivStr   = entry.encryption_iv,
              let saltStr = entry.encryption_salt
        else {
            throw MaFileError.noEncryptionDataInManifest
        }

        guard let iv   = decodeBase64(ivStr)   else { throw MaFileError.invalidBase64("encryption_iv") }
        guard let salt = decodeBase64(saltStr) else { throw MaFileError.invalidBase64("encryption_salt") }

        return (iv, salt)
    }

    static func decrypt(encryptedData: Data, iv: Data, salt: Data, password: String) throws -> Data {
        let key = try pbkdf2(password: password, salt: salt, iterations: 50000)
        let plain = try aesCBCDecrypt(cipher: encryptedData, key: key, iv: iv)
        guard (try? JSONSerialization.jsonObject(with: plain)) != nil else {
            throw MaFileError.wrongPassword
        }
        return plain
    }

    private static func pbkdf2(password: String, salt: Data, iterations: Int) throws -> Data {
        guard let passData = password.data(using: .utf8) else {
            throw MaFileError.keyDerivationFailed
        }
        var derived = [UInt8](repeating: 0, count: kCCKeySizeAES256)
        let status = passData.withUnsafeBytes { passPtr -> CCCryptorStatus in
            salt.withUnsafeBytes { saltPtr -> CCCryptorStatus in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passPtr.baseAddress?.assumingMemoryBound(to: Int8.self), passData.count,
                    saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    UInt32(iterations),
                    &derived, kCCKeySizeAES256
                )
            }
        }
        guard status == kCCSuccess else { throw MaFileError.keyDerivationFailed }
        return Data(derived)
    }

    private static func aesCBCDecrypt(cipher: Data, key: Data, iv: Data) throws -> Data {
        var output = [UInt8](repeating: 0, count: cipher.count + kCCBlockSizeAES128)
        var moved  = 0
        let status = cipher.withUnsafeBytes { cp -> CCCryptorStatus in
            key.withUnsafeBytes { kp -> CCCryptorStatus in
                iv.withUnsafeBytes { ip -> CCCryptorStatus in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            kp.baseAddress, key.count, ip.baseAddress,
                            cp.baseAddress, cipher.count,
                            &output, output.count, &moved)
                }
            }
        }
        guard status == kCCSuccess else { throw MaFileError.decryptionFailed(status) }
        return Data(output.prefix(moved))
    }

    static func decodeBase64(_ string: String) -> Data? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "-", with: "+")
             .replacingOccurrences(of: "_", with: "/")
        let rem = s.count % 4
        if rem != 0 { s += String(repeating: "=", count: 4 - rem) }
        return Data(base64Encoded: s, options: .ignoreUnknownCharacters)
    }
}
