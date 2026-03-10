import SwiftUI

struct TradeConfirmationsView: View {
    @ObservedObject var tradeManager: SteamTradeManager
    let account: SteamAccount
    let cookies: [HTTPCookie]
    @Environment(\.presentationMode) var presentationMode
    @State private var showAcceptAll = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    if tradeManager.isLoading && tradeManager.confirmations.isEmpty {
                        loadingView
                    } else if tradeManager.confirmations.isEmpty {
                        emptyStateView
                    } else {
                        confirmationsList
                    }

                    if !tradeManager.statusMessage.isEmpty {
                        Text(tradeManager.statusMessage)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.vertical, 8)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .navigationTitle("Подтверждения")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Принять все \(tradeManager.confirmations.count) подтверждений?",
                isPresented: $showAcceptAll,
                titleVisibility: .visible
            ) {
                Button("Принять все", role: .destructive) {
                    tradeManager.acceptAll(account: account, cookies: cookies)
                }
                Button("Отмена", role: .cancel) {}
            }
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !tradeManager.confirmations.isEmpty {
                        Button("Принять все") {
                            showAcceptAll = true
                        }
                        .foregroundColor(.green)
                        .fontWeight(.bold)
                    }
                }
            }
        }
        .onAppear {
            tradeManager.fetchConfirmations(account: account, cookies: cookies)
        }
        .preferredColorScheme(.dark)
    }

    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.5)
            Text("Загрузка...").foregroundColor(.gray).font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptyStateView: some View {
        VStack(spacing: 15) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            Text("Нет подтверждений")
                .font(.headline)
            Text("Все обмены и продажи подтверждены")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(badgeColor.opacity(0.2))
                        .frame(width: 52, height: 52)
                    Image(systemName: confirmation.type.icon)
                        .font(.title2)
                        .foregroundColor(badgeColor)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(confirmation.type.displayName)
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(badgeColor)
                            .clipShape(Capsule())
                        Spacer()
                        Text(timeAgo)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }

                    Text(confirmation.displayTitle)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .lineLimit(2)

                    if !confirmation.displaySummary.isEmpty {
                        Text(confirmation.displaySummary)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(4)
                    }
                }
            }
            .padding(14)

            Divider().background(Color.white.opacity(0.1))

            HStack(spacing: 0) {
                Button(action: onDecline) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Отклонить")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.red)
                    .font(.subheadline.bold())
                }

                Divider().frame(height: 36)

                Button(action: onAccept) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Принять")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.green)
                    .font(.subheadline.bold())
                }
            }
            .disabled(isLoading)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
    }

    var badgeColor: Color {
        switch confirmation.type {
        case .trade:       return .blue
        case .market:      return .orange
        case .phoneChange: return .purple
        default:           return .gray
        }
    }

    var timeAgo: String {
        let diff = Int(Date().timeIntervalSince1970) - Int(confirmation.creationTime)
        if diff < 60    { return "только что" }
        if diff < 3600  { return "\(diff / 60)м назад" }
        if diff < 86400 { return "\(diff / 3600)ч назад" }
        return "\(diff / 86400)д назад"
    }
}
