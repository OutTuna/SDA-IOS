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
        case shared_secret
        case identity_secret
        case account_name
        case device_id
        case Session
        case steamid
    }
    
    struct SessionData: Decodable {
        let SteamID: UInt64?
    }
    
    init(shared_secret: String, identity_secret: String?, account_name: String, device_id: String?, steamid: String?, filename: String? = nil) {
        self.shared_secret = shared_secret
        self.identity_secret = identity_secret
        self.account_name = account_name
        self.device_id = device_id
        self.steamid = steamid
        self.filename = filename
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        shared_secret = try container.decode(String.self, forKey: .shared_secret)
        identity_secret = try container.decodeIfPresent(String.self, forKey: .identity_secret)
        account_name = try container.decode(String.self, forKey: .account_name)
        device_id = try container.decodeIfPresent(String.self, forKey: .device_id)
        
        if let session = try? container.decodeIfPresent(SessionData.self, forKey: .Session), let sid = session.SteamID {
            steamid = String(sid)
        } else if let sidLong = try? container.decodeIfPresent(UInt64.self, forKey: .steamid) {
            steamid = String(sidLong)
        } else if let sidStr = try? container.decodeIfPresent(String.self, forKey: .steamid) {
            steamid = sidStr
        } else {
            steamid = nil
        }
    }
    
    static func == (lhs: SteamAccount, rhs: SteamAccount) -> Bool {
        return lhs.account_name == rhs.account_name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(account_name)
    }
}

class AccountManager: ObservableObject {
    @Published var accounts: [SteamAccount] = []
    
    init() {
        loadAccounts()
    }
    
    func loadAccounts() {
        self.accounts = []
        let fileManager = FileManager.default
        
        if let documentURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: documentURL, includingPropertiesForKeys: nil)
                for url in fileURLs {
                    parseFile(at: url, isFromBundle: false)
                }
            } catch { print("Ошибка чтения: \(error)") }
        }
        
        if let bundleURLs = Bundle.main.urls(forResourcesWithExtension: "maFile", subdirectory: nil) {
            for url in bundleURLs {
                parseFile(at: url, isFromBundle: true)
            }
        }
    }
    
    private func parseFile(at url: URL, isFromBundle: Bool) {
        do {
            if !isFromBundle { _ = url.startAccessingSecurityScopedResource() }
            
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            var account = try decoder.decode(SteamAccount.self, from: data)
            account.filename = url.lastPathComponent
            
            if let index = self.accounts.firstIndex(where: { $0.account_name == account.account_name }) {
                self.accounts[index] = account
            } else {
                self.accounts.append(account)
            }
            
            if !isFromBundle { url.stopAccessingSecurityScopedResource() }
        } catch { }
    }
    
    func importFile(at url: URL) -> SteamAccount? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let destinationURL = documentsURL.appendingPathComponent(url.lastPathComponent)
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: url, to: destinationURL)
            loadAccounts()
            return accounts.first(where: { $0.filename == url.lastPathComponent })
        } catch {
            print("Ошибка: \(error)")
            return nil
        }
    }
    
    func deleteAccount(_ account: SteamAccount) {
        if let index = accounts.firstIndex(of: account) {
            accounts.remove(at: index)
        }
        guard let filename = account.filename,
              let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        let fileURL = documentsURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
    }
}
