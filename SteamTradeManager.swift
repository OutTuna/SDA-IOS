import Foundation
import Combine
import UIKit

enum ConfirmationType: Int {
    case generic = 0, trade = 1, market = 2, unknown = 3
    
    var displayName: String {
        switch self {
        case .generic: return "Подтверждение"
        case .trade: return "Обмен"
        case .market: return "Торговая площадка"
        case .unknown: return "Неизвестно"
        }
    }
    
    var icon: String {
        switch self {
        case .generic: return "checkmark.circle"
        case .trade: return "arrow.left.arrow.right"
        case .market: return "cart"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct SteamConfirmation: Identifiable {
    let id: String
    let key: String
    let type: ConfirmationType
    let description: String
    let time: Int64
}

class SteamTradeManager: ObservableObject {
    @Published var confirmations: [SteamConfirmation] = []
    @Published var isLoading = false
    @Published var statusMessage = ""
    
    private let baseURL = "https://steamcommunity.com/mobileconf"
    
    func fetchConfirmations(account: SteamAccount, cookies: [HTTPCookie]) {
        guard let identitySecret = account.identity_secret else {
            statusMessage = "Отсутствует identity_secret"
            return
        }
        
        isLoading = true
        statusMessage = "Загрузка подтверждений..."
        
        let time = Int64(Date().timeIntervalSince1970)
        let tag = "conf"
        
        guard let deviceId = account.device_id,
              let steamId = account.steamid,
              let confirmationHash = SteamCrypto.generateConfirmationHash(identitySecret: identitySecret, time: time, tag: tag) else {
            statusMessage = "Ошибка создания хеша"
            isLoading = false
            return
        }
        
        var urlComponents = URLComponents(string: "\(baseURL)/getlist")!
        urlComponents.queryItems = [
            URLQueryItem(name: "p", value: deviceId),
            URLQueryItem(name: "a", value: steamId),
            URLQueryItem(name: "k", value: confirmationHash),
            URLQueryItem(name: "t", value: String(time)),
            URLQueryItem(name: "m", value: "ios"),
            URLQueryItem(name: "tag", value: tag)
        ]
        
        guard let url = urlComponents.url else {
            statusMessage = "Некорректный URL"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)
        cookieHeader.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.statusMessage = "Ошибка: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self?.statusMessage = "Нет данных"
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let success = json["success"] as? Bool, success {
                            if let confArray = json["conf"] as? [[String: Any]] {
                                self?.parseConfirmations(confArray, time: time)
                                self?.statusMessage = "Загружено: \(confArray.count) подтверждений"
                            } else {
                                self?.confirmations = []
                                self?.statusMessage = "Нет активных подтверждений"
                            }
                        } else {
                            self?.statusMessage = "Steam вернул неудачу"
                        }
                    }
                } catch {
                    self?.statusMessage = "Ошибка парсинга: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    private func parseConfirmations(_ confArray: [[String: Any]], time: Int64) {
        var parsed: [SteamConfirmation] = []
        
        for conf in confArray {
            guard let id = conf["id"] as? String,
                  let key = conf["nonce"] as? String else { continue }
            
            let typeInt = conf["type"] as? Int ?? 3
            let type = ConfirmationType(rawValue: typeInt) ?? .unknown
            
            let headline = conf["headline"] as? String ?? ""
            let summary = conf["summary"] as? [[String: String]] ?? []
            
            var description = headline
            if !summary.isEmpty {
                let summaryText = summary.compactMap { $0["0"] }.joined(separator: "\n")
                description += "\n" + summaryText
            }
            
            let confirmation = SteamConfirmation(
                id: id,
                key: key,
                type: type,
                description: description,
                time: time
            )
            
            parsed.append(confirmation)
        }
        
        self.confirmations = parsed
    }
    
    func acceptConfirmation(_ conf: SteamConfirmation, account: SteamAccount, cookies: [HTTPCookie]) {
        performConfirmationAction(conf, account: account, cookies: cookies, operation: "allow")
    }
    
    func declineConfirmation(_ conf: SteamConfirmation, account: SteamAccount, cookies: [HTTPCookie]) {
        performConfirmationAction(conf, account: account, cookies: cookies, operation: "cancel")
    }
    
    private func performConfirmationAction(_ conf: SteamConfirmation, account: SteamAccount, cookies: [HTTPCookie], operation: String) {
        guard let identitySecret = account.identity_secret else {
            statusMessage = "Отсутствует identity_secret"
            return
        }
        
        isLoading = true
        let time = Int64(Date().timeIntervalSince1970)
        let tag = "conf"
        
        guard let deviceId = account.device_id,
              let steamId = account.steamid,
              let confirmationHash = SteamCrypto.generateConfirmationHash(identitySecret: identitySecret, time: time, tag: tag) else {
            statusMessage = "Ошибка создания хеша"
            isLoading = false
            return
        }
        
        var urlComponents = URLComponents(string: "\(baseURL)/ajaxop")!
        urlComponents.queryItems = [
            URLQueryItem(name: "op", value: operation),
            URLQueryItem(name: "p", value: deviceId),
            URLQueryItem(name: "a", value: steamId),
            URLQueryItem(name: "k", value: confirmationHash),
            URLQueryItem(name: "t", value: String(time)),
            URLQueryItem(name: "m", value: "ios"),
            URLQueryItem(name: "tag", value: tag),
            URLQueryItem(name: "cid", value: conf.id),
            URLQueryItem(name: "ck", value: conf.key)
        ]
        
        guard let url = urlComponents.url else {
            statusMessage = "Некорректный URL"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)
        cookieHeader.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.statusMessage = "Ошибка: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self?.statusMessage = "Нет данных"
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let success = json["success"] as? Bool, success {
                            self?.statusMessage = operation == "allow" ? "Принято!" : "Отклонено!"
                            self?.confirmations.removeAll { $0.id == conf.id }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self?.fetchConfirmations(account: account, cookies: cookies)
                            }
                        } else {
                            self?.statusMessage = "Не удалось выполнить действие"
                        }
                    }
                } catch {
                    self?.statusMessage = "Ошибка: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}
