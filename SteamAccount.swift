import Foundation
import SwiftUI
import Combine

struct SteamAccount: Identifiable, Decodable, Hashable {
    let id = UUID()
    let shared_secret: String
    let identity_secret: String?
    let account_name: String
    let device_id: String?
    var filename: String?
    let steamid: String?

    enum CodingKeys: String, CodingKey {
        case shared_secret, identity_secret, account_name, device_id, Session, steamid
    }

    struct SessionData: Decodable { let SteamID: UInt64? }

    init(shared_secret: String, identity_secret: String?, account_name: String,
         device_id: String?, steamid: String?, filename: String? = nil) {
        self.shared_secret   = shared_secret
        self.identity_secret = identity_secret
        self.account_name    = account_name
        self.device_id       = device_id
        self.steamid         = steamid
        self.filename        = filename
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shared_secret   = try c.decode(String.self, forKey: .shared_secret)
        identity_secret = try c.decodeIfPresent(String.self, forKey: .identity_secret)
        account_name    = try c.decode(String.self, forKey: .account_name)
        device_id       = try c.decodeIfPresent(String.self, forKey: .device_id)

        if let session = try? c.decodeIfPresent(SessionData.self, forKey: .Session),
           let sid = session.SteamID {
            steamid = String(sid)
        } else if let sidLong = try? c.decodeIfPresent(UInt64.self, forKey: .steamid) {
            steamid = String(sidLong)
        } else {
            steamid = try c.decodeIfPresent(String.self, forKey: .steamid)
        }
    }

    static func == (lhs: SteamAccount, rhs: SteamAccount) -> Bool { lhs.account_name == rhs.account_name }
    func hash(into hasher: inout Hasher) { hasher.combine(account_name) }
}

class AccountManager: ObservableObject {
    @Published var accounts: [SteamAccount] = []

    init() { loadAccounts() }

    func loadAccounts() {
        accounts = []
        let fm = FileManager.default

        if let docURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
           let urls = try? fm.contentsOfDirectory(at: docURL, includingPropertiesForKeys: nil) {
            for url in urls { parsePlainFile(at: url) }
        }

        if let bundleURLs = Bundle.main.urls(forResourcesWithExtension: "maFile", subdirectory: nil) {
            for url in bundleURLs { parsePlainFile(at: url, isBundle: true) }
        }
    }

    private func parsePlainFile(at url: URL, isBundle: Bool = false) {
        if !isBundle { _ = url.startAccessingSecurityScopedResource() }
        defer { if !isBundle { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { return }
        if EncryptedMaFileManager.isEncrypted(data) { return }

        if var account = try? JSONDecoder().decode(SteamAccount.self, from: data) {
            account.filename = url.lastPathComponent
            upsert(account)
        }
    }

    @discardableResult
    func importPlainData(_ data: Data, filename: String) -> SteamAccount? {
        guard let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dest = docURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: dest)
        try? data.write(to: dest)
        loadAccounts()
        return accounts.first { $0.filename == filename }
    }

    func deleteAccount(_ account: SteamAccount) {
        accounts.removeAll { $0 == account }
        if let fn = account.filename,
           let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(at: docURL.appendingPathComponent(fn))
        }
    }

    private func upsert(_ account: SteamAccount) {
        if let i = accounts.firstIndex(where: { $0.account_name == account.account_name }) {
            accounts[i] = account
        } else {
            accounts.append(account)
        }
    }
}
