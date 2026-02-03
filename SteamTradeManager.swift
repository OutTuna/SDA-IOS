import Foundation
import Combine
import UIKit

enum ConfirmationType: Int {
    case generic = 0, trade = 1, market = 2, unknown = 3
}

struct SteamConfirmation: Identifiable {
    let id: String
    let key: String
    let type: ConfirmationType
    let description: String
}

class SteamTradeManager: ObservableObject {
    @Published var confirmations: [SteamConfirmation] = []
    @Published var isLoading = false
    @Published var statusMessage = ""
    
    // Пустые методы, чтобы пройти ContentView, а так же закос на будущее для трейдов
    func fetchConfirmations(account: SteamAccount, cookies: [HTTPCookie]) {
    }
    
    func acceptConfirmation(_ conf: SteamConfirmation, account: SteamAccount, cookies: [HTTPCookie]) {
    }
}
