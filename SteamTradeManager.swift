import Foundation
import Combine
import UIKit
import CommonCrypto

// Steam API: 1=generic, 2=trade, 3=market, 5=phone_change
enum ConfirmationType: Int {
    case generic     = 1
    case trade       = 2
    case market      = 3
    case phoneChange = 5
    case unknown     = -1

    init(from raw: Int) {
        self = ConfirmationType(rawValue: raw) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .generic:     return "Подтверждение"
        case .trade:       return "Обмен"
        case .market:      return "Торговая площадка"
        case .phoneChange: return "Смена телефона"
        case .unknown:     return "Неизвестно"
        }
    }

    var icon: String {
        switch self {
        case .generic:     return "checkmark.circle"
        case .trade:       return "arrow.left.arrow.right"
        case .market:      return "cart"
        case .phoneChange: return "phone.badge.checkmark"
        case .unknown:     return "questionmark.circle"
        }
    }
}

struct SteamConfirmation: Identifiable {
    let id: String
    let key: String
    let type: ConfirmationType
    let headline: String
    let summary: [String]
    let typeName: String
    let iconURL: String?
    let creationTime: Int64

    var displayTitle: String {
        switch type {
        case .trade:
            return headline.isEmpty ? "Trade Offer" : headline
        case .market:
            if typeName.hasPrefix("Sell - ") {
                return String(typeName.dropFirst("Sell - ".count))
            }
            return typeName.isEmpty ? "Market Listing" : typeName
        case .generic:
            return headline.isEmpty ? typeName : headline
        case .phoneChange:
            return "Смена номера телефона"
        case .unknown:
            return typeName.isEmpty ? "Неизвестное подтверждение" : typeName
        }
    }

    var displaySummary: String {
        summary.joined(separator: "\n")
    }
}

class SteamTradeManager: ObservableObject {
    @Published var confirmations: [SteamConfirmation] = []
    @Published var isLoading = false
    @Published var statusMessage = ""

    private let baseURL = "https://steamcommunity.com/mobileconf"

    func fetchConfirmations(account: SteamAccount, cookies: [HTTPCookie]) {
        guard let identitySecret = account.identity_secret else {
            statusMessage = "Отсутствует identity_secret"; return
        }
        guard let steamId = account.steamid else {
            statusMessage = "Отсутствует steamid"; return
        }

        isLoading = true
        statusMessage = "Загрузка подтверждений..."

        let time = Int64(Date().timeIntervalSince1970)
        let tag  = "conf"

        guard let confirmationHash = SteamCrypto.generateConfirmationHash(
            identitySecret: identitySecret, time: time, tag: tag
        ) else {
            statusMessage = "Ошибка создания хеша"; isLoading = false; return
        }

        let deviceId = account.device_id ?? SteamTradeManager.generateDeviceID(steamID64: steamId)

        var urlComponents = URLComponents(string: "\(baseURL)/getlist")!
        urlComponents.queryItems = [
            URLQueryItem(name: "p",   value: deviceId),
            URLQueryItem(name: "a",   value: steamId),
            URLQueryItem(name: "k",   value: confirmationHash),
            URLQueryItem(name: "t",   value: String(time)),
            URLQueryItem(name: "m",   value: "android"),
            URLQueryItem(name: "tag", value: tag)
        ]

        guard let url = urlComponents.url else {
            statusMessage = "Некорректный URL"; isLoading = false; return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36",
                         forHTTPHeaderField: "User-Agent")
        HTTPCookie.requestHeaderFields(with: cookies)
            .forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.statusMessage = "Ошибка: \(error.localizedDescription)"; return
                }
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    self?.statusMessage = "HTTP \(http.statusCode) — проверьте Device ID / сессию"; return
                }
                guard let data = data else { self?.statusMessage = "Нет данных"; return }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let needAuth = json["needauth"] as? Bool, needAuth {
                            self?.statusMessage = "Сессия истекла. Войдите снова."; return
                        }
                        if let success = json["success"] as? Bool, success {
                            let arr = json["conf"] as? [[String: Any]] ?? []
                            self?.parseConfirmations(arr)
                            self?.statusMessage = arr.isEmpty
                                ? "Нет активных подтверждений"
                                : "Загружено: \(arr.count)"
                        } else {
                            self?.statusMessage = json["message"] as? String ?? "Steam вернул ошибку"
                        }
                    }
                } catch {
                    self?.statusMessage = "Ошибка парсинга: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func parseConfirmations(_ confArray: [[String: Any]]) {
        confirmations = confArray.compactMap { conf in
            guard
                let id  = conf["id"]    as? String,
                let key = conf["nonce"] as? String
            else { return nil }

            let typeInt      = conf["type"]          as? Int    ?? -1
            let type         = ConfirmationType(from: typeInt)
            let headline     = conf["headline"]      as? String ?? ""
            let typeName     = conf["type_name"]     as? String ?? ""
            let iconURL      = conf["icon"]          as? String
            let creationTime = conf["creation_time"] as? Int64
                            ?? Int64(Date().timeIntervalSince1970)
            let summary: [String]
            if let arr = conf["summary"] as? [String] {
                summary = arr
            } else {
                summary = []
            }

            return SteamConfirmation(
                id: id, key: key, type: type,
                headline: headline, summary: summary,
                typeName: typeName, iconURL: iconURL,
                creationTime: creationTime
            )
        }
    }
    func acceptConfirmation(_ conf: SteamConfirmation, account: SteamAccount, cookies: [HTTPCookie]) {
        performAction(conf, account: account, cookies: cookies, operation: "allow")
    }

    func declineConfirmation(_ conf: SteamConfirmation, account: SteamAccount, cookies: [HTTPCookie]) {
        performAction(conf, account: account, cookies: cookies, operation: "cancel")
    }

    private func performAction(_ conf: SteamConfirmation, account: SteamAccount,
                               cookies: [HTTPCookie], operation: String) {
        guard
            let identitySecret = account.identity_secret,
            let steamId        = account.steamid
        else { statusMessage = "Отсутствуют данные аккаунта"; return }

        isLoading = true
        let time = Int64(Date().timeIntervalSince1970)
        let tag = operation
        guard let confirmationHash = SteamCrypto.generateConfirmationHash(
            identitySecret: identitySecret, time: time, tag: tag
        ) else { statusMessage = "Ошибка создания хеша"; isLoading = false; return }

        let deviceId = account.device_id ?? SteamTradeManager.generateDeviceID(steamID64: steamId)

        var urlComponents = URLComponents(string: "\(baseURL)/ajaxop")!
        urlComponents.queryItems = [
            URLQueryItem(name: "op",  value: operation),
            URLQueryItem(name: "p",   value: deviceId),
            URLQueryItem(name: "a",   value: steamId),
            URLQueryItem(name: "k",   value: confirmationHash),
            URLQueryItem(name: "t",   value: String(time)),
            URLQueryItem(name: "m",   value: "android"),
            URLQueryItem(name: "tag", value: tag),
            URLQueryItem(name: "cid", value: conf.id),
            URLQueryItem(name: "ck",  value: conf.key)
        ]

        guard let url = urlComponents.url else {
            statusMessage = "Некорректный URL"; isLoading = false; return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36",
                         forHTTPHeaderField: "User-Agent")
        HTTPCookie.requestHeaderFields(with: cookies)
            .forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.statusMessage = "Ошибка: \(error.localizedDescription)"; return
                }
                guard let data = data else { return }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = json["success"] as? Bool, success {
                    self?.statusMessage = operation == "allow" ? "✅ Принято!" : "❌ Отклонено!"
                    self?.confirmations.removeAll { $0.id == conf.id }
                } else {
                    self?.statusMessage = "Не удалось выполнить действие"
                }
            }
        }.resume()
    }

    func acceptAll(account: SteamAccount, cookies: [HTTPCookie]) {
        guard
            let identitySecret = account.identity_secret,
            let steamId        = account.steamid
        else { return }

        isLoading = true
        let time = Int64(Date().timeIntervalSince1970)
        let tag  = "allow"

        guard let confirmationHash = SteamCrypto.generateConfirmationHash(
            identitySecret: identitySecret, time: time, tag: tag
        ) else { isLoading = false; return }

        let deviceId = account.device_id ?? SteamTradeManager.generateDeviceID(steamID64: steamId)

        var items: [URLQueryItem] = [
            URLQueryItem(name: "op",  value: "allow"),
            URLQueryItem(name: "p",   value: deviceId),
            URLQueryItem(name: "a",   value: steamId),
            URLQueryItem(name: "k",   value: confirmationHash),
            URLQueryItem(name: "t",   value: String(time)),
            URLQueryItem(name: "m",   value: "android"),
            URLQueryItem(name: "tag", value: tag),
        ]
        for conf in confirmations {
            items.append(URLQueryItem(name: "cid[]", value: conf.id))
            items.append(URLQueryItem(name: "ck[]",  value: conf.key))
        }

        var urlComponents = URLComponents(string: "\(baseURL)/multiajaxop")!
        urlComponents.queryItems = items

        guard let url = urlComponents.url else { isLoading = false; return }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36",
                         forHTTPHeaderField: "User-Agent")
        HTTPCookie.requestHeaderFields(with: cookies)
            .forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = json["success"] as? Bool, success {
                    self?.confirmations.removeAll()
                    self?.statusMessage = "✅ Все подтверждены"
                } else {
                    self?.statusMessage = "Ошибка при массовом подтверждении"
                }
            }
        }.resume()
    }
    // android:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    static func generateDeviceID(steamID64: String) -> String {
        let input = "SteamID: \(steamID64)"
        guard let data = input.data(using: .utf8) else {
            return "android:00000000-0000-0000-0000-000000000000"
        }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest) }
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let h   = Array(hex.prefix(32))
        return "android:\(String(h[0..<8]))-\(String(h[8..<12]))-\(String(h[12..<16]))-\(String(h[16..<20]))-\(String(h[20..<32]))"
    }
}
