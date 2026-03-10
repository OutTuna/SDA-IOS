import SwiftUI
import Combine
import LocalAuthentication

@MainActor
class BiometricAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var authError: String?
    @Published var isAuthenticating = false

    private let timeoutSecs: TimeInterval = 300
    private let lastAuthKey = "sda_lastAuth"

    init() {}

    var biometryType: LABiometryType {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            return .none
        }
        return ctx.biometryType
    }

    var biometryName: String {
        switch biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        default:       return "Пасскод"
        }
    }

    var biometryIcon: String {
        switch biometryType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        default:       return "lock.fill"
        }
    }

    func authenticate() async {
        guard !isAuthenticating else { return }
        let ctx = LAContext()
        var nsErr: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &nsErr) else {
            markAuthenticated()
            return
        }

        isAuthenticating = true
        authError = nil

        do {
            let ok = try await ctx.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Подтвердите личность для доступа к Steam Guard"
            )
            if ok { markAuthenticated() }
        } catch let e as LAError {
            switch e.code {
            case .userCancel, .appCancel, .systemCancel:
                break
            case .biometryLockout:
                authError = "Биометрия заблокирована. Нажмите «Разблокировать» и введите пасскод."
            default:
                authError = e.localizedDescription
            }
        } catch {
            authError = error.localizedDescription
        }

        isAuthenticating = false
    }
    func handleAppForeground() {
        guard isAuthenticated else {
            return
        }
        let lastAuth = UserDefaults.standard.double(forKey: lastAuthKey)
        let elapsed  = Date().timeIntervalSince1970 - lastAuth
        if elapsed > timeoutSecs {
            isAuthenticated = false
            Task { await authenticate() }
        }    }

    private func markAuthenticated() {
        isAuthenticated = true
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastAuthKey)
    }
}

struct BiometricGateView<Content: View>: View {
    @StateObject private var auth = BiometricAuthManager()
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ZStack {
            if auth.isAuthenticated {
                content
            } else {
                LockScreenView(auth: auth)
            }
        }
        .task {
            let lastAuth = UserDefaults.standard.double(forKey: "sda_lastAuth")
            let elapsed  = Date().timeIntervalSince1970 - lastAuth
            if lastAuth > 0 && elapsed < 300 {
                auth.isAuthenticated = true
            } else {
                await auth.authenticate()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            auth.handleAppForeground()
        }
    }
}

struct LockScreenView: View {
    @ObservedObject var auth: BiometricAuthManager

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 110, height: 110)
                    Image(systemName: auth.biometryIcon)
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.blue)
                }

                VStack(spacing: 8) {
                    Text("Steam Guard")
                        .font(.largeTitle.bold())
                    Text("Войдите с помощью \(auth.biometryName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let error = auth.authError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 40)
                    .transition(.opacity.combined(with: .scale))
                }

                Spacer()

                Button(action: { Task { await auth.authenticate() } }) {
                    HStack(spacing: 10) {
                        if auth.isAuthenticating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: auth.biometryIcon)
                        }
                        Text(auth.isAuthenticating ? "Проверка..." : "Разблокировать")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 40)
                }
                .disabled(auth.isAuthenticating)

                Spacer().frame(height: 40)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: auth.authError)
        .animation(.easeInOut(duration: 0.2), value: auth.isAuthenticating)
    }
}
