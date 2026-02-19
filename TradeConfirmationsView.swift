import SwiftUI

struct TradeConfirmationsView: View {
    @ObservedObject var tradeManager: SteamTradeManager
    let account: SteamAccount
    let cookies: [HTTPCookie]
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
                
                VStack {
                    if tradeManager.isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding()
                    } else if tradeManager.confirmations.isEmpty {
                        emptyStateView
                    } else {
                        confirmationsList
                    }
                    
                    if !tradeManager.statusMessage.isEmpty {
                        Text(tradeManager.statusMessage)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding()
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .navigationTitle("Подтверждения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Закрыть") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        tradeManager.fetchConfirmations(account: account, cookies: cookies)
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(tradeManager.isLoading)
                }
            }
        }
        .onAppear {
            tradeManager.fetchConfirmations(account: account, cookies: cookies)
        }
        .preferredColorScheme(.dark)
    }
    
    var emptyStateView: some View {
        VStack(spacing: 15) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.green)
            Text("Нет подтверждений")
                .font(.headline)
            Text("Все обмены и продажи подтверждены")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    var confirmationsList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(tradeManager.confirmations) { confirmation in
                    ConfirmationCard(
                        confirmation: confirmation,
                        onAccept: {
                            tradeManager.acceptConfirmation(confirmation, account: account, cookies: cookies)
                        },
                        onDecline: {
                            tradeManager.declineConfirmation(confirmation, account: account, cookies: cookies)
                        },
                        isLoading: tradeManager.isLoading
                    )
                }
            }
            .padding()
        }
    }
}

struct ConfirmationCard: View {
    let confirmation: SteamConfirmation
    let onAccept: () -> Void
    let onDecline: () -> Void
    let isLoading: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: confirmation.type.icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(confirmation.type.displayName)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(formattedTime)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            
            Text(confirmation.description)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 12) {
                Button(action: onAccept) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Принять")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isLoading)
                
                Button(action: onDecline) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Отклонить")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isLoading)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(15)
        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
    }
    
    var formattedTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(confirmation.time))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct TradeConfirmationsView_Previews: PreviewProvider {
    static var previews: some View {
        let manager = SteamTradeManager()
        manager.confirmations = [
            SteamConfirmation(
                id: "1",
                key: "key1",
                type: .trade,
                description: "Обмен с пользователем TestUser\nВы отдаете: AK-47 | Redline\nВы получаете: AWP | Dragon Lore",
                time: Int64(Date().timeIntervalSince1970)
            ),
            SteamConfirmation(
                id: "2",
                key: "key2",
                type: .market,
                description: "Продажа предмета на торговой площадке\nM4A4 | Howl за 500$",
                time: Int64(Date().timeIntervalSince1970 - 300)
            )
        ]
        
        return TradeConfirmationsView(
            tradeManager: manager,
            account: SteamAccount(
                shared_secret: "",
                identity_secret: "",
                account_name: "test",
                device_id: "",
                steamid: ""
            ),
            cookies: []
        )
    }
}
