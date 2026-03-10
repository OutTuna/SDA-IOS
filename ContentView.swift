import SwiftUI
import Combine
import UniformTypeIdentifiers
import WebKit

struct ContentView: View {
    @StateObject private var accountManager = AccountManager()
    @StateObject private var tradeManager  = SteamTradeManager()

    @State private var selectedAccount: SteamAccount?
    @State private var code: String = "-----"
    @State private var progress: Float = 0.0
    @State private var isImporting = false
    @State private var showDeleteAlert = false
    @State private var showLoginSheet = false
    @State private var isLoggedIn = false
    @State private var cookies: [HTTPCookie] = []
    @State private var showTradeConfirmations = false

    @State private var importMode: ImportMode = .none

    enum ImportMode {
        case none
        case encrypted(data: Data, filename: String, iv: Data, salt: Data)
        case error(String)
    }

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            NavigationView {
                ZStack {
                    Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
                    mainContent
                }
                .navigationTitle("Steam Guard")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { isImporting = true }) {
                            Image(systemName: "plus").font(.title2)
                        }
                    }
                }
                .fileImporter(
                    isPresented: $isImporting,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: true,
                    onCompletion: handleImport
                )
                .sheet(isPresented: $showLoginSheet) {
                    SteamLoginViewWrapper(isPresented: $showLoginSheet,
                                         isLoggedIn: $isLoggedIn, cookies: $cookies)
                }
                .sheet(isPresented: $showTradeConfirmations) {
                    if let account = selectedAccount {
                        TradeConfirmationsView(tradeManager: tradeManager,
                                              account: account, cookies: cookies)
                    }
                }
                .alert(isPresented: $showDeleteAlert) {
                    Alert(
                        title: Text("Удалить аккаунт?"),
                        primaryButton: .destructive(Text("Удалить")) {
                            if let acc = selectedAccount {
                                accountManager.deleteAccount(acc)
                                selectedAccount = nil
                            }
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
            .preferredColorScheme(.dark)

            if case .encrypted(let data, let filename, let iv, let salt) = importMode {
                PasswordOverlayView(
                    onSubmit: { password in
                        tryDecrypt(data: data, filename: filename, iv: iv, salt: salt, password: password)
                    },
                    onCancel: { importMode = .none }
                )
                .zIndex(999)
            }

            if case .error(let msg) = importMode {
                ErrorOverlayView(message: msg, onDismiss: { importMode = .none })
                    .zIndex(999)
            }
        }
        .onReceive(timer) { _ in updateCode() }
        .onAppear { selectedAccount = accountManager.accounts.first }
        .onChange(of: accountManager.accounts) { accounts in
            if let sel = selectedAccount, !accounts.contains(sel) { selectedAccount = nil }
            if selectedAccount == nil { selectedAccount = accounts.first }
        }
    }

    var mainContent: some View {
        VStack(spacing: 20) {
            if accountManager.accounts.isEmpty { emptyStateView } else { accountPickerView }
            Spacer()
            if let account = selectedAccount { codeDisplayView(account: account) }
            else if !accountManager.accounts.isEmpty { Text("Загрузка...").foregroundColor(.gray) }
            Spacer()
        }
    }

    var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.checkerboard").font(.system(size: 60)).foregroundColor(.blue)
            Text("Нет аккаунтов").font(.headline)
            Text("Нажми «+» и выбери папку SDA\n(где лежат .maFile и manifest.json)")
                .font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center)
        }.padding()
    }

    var accountPickerView: some View {
        HStack {
            Picker("", selection: $selectedAccount) {
                ForEach(accountManager.accounts, id: \.self) { acc in
                    Text(acc.account_name).tag(acc as SteamAccount?)
                }
            }
            .pickerStyle(MenuPickerStyle()).labelsHidden()
            .frame(maxWidth: .infinity).padding()
            .background(Color(UIColor.secondarySystemBackground)).cornerRadius(10)
            if selectedAccount != nil {
                Button { showDeleteAlert = true } label: {
                    Image(systemName: "trash").foregroundColor(.red).padding()
                        .background(Color(UIColor.secondarySystemBackground)).cornerRadius(10)
                }
            }
        }.padding(.horizontal)
    }

    func codeDisplayView(account: SteamAccount) -> some View {
        VStack(spacing: 20) {
            Text(account.account_name).font(.title3).bold().foregroundColor(.white)
            Text(code)
                .font(.system(size: 64, weight: .bold, design: .monospaced))
                .foregroundColor(.blue).shadow(color: .blue.opacity(0.5), radius: 10)
                .onTapGesture { UIPasteboard.general.string = code }
            ProgressView(value: 1.0 - progress).padding(.horizontal, 50)
                .tint(progress > 0.8 ? .red : .blue)
            Text("Нажми на код для копирования").font(.caption2).foregroundColor(.gray)
            HStack(spacing: 20) {
                Button { showLoginSheet = true } label: {
                    Label(isLoggedIn ? "Перевойти" : "Войти", systemImage: "person.circle")
                        .padding().background(Color.gray.opacity(0.3)).cornerRadius(10)
                }
                Button { showTradeConfirmations = true } label: {
                    Label("Трейды", systemImage: "arrow.left.arrow.right").padding()
                        .background(isLoggedIn ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                        .foregroundColor(isLoggedIn ? .blue : .gray).cornerRadius(10)
                }
                .disabled(!isLoggedIn)
            }.padding(.top, 10)
        }
    }

    func handleImport(result: Result<[URL], Error>) {
        guard let urls = try? result.get(), !urls.isEmpty else { return }

        urls.forEach { _ = $0.startAccessingSecurityScopedResource() }
        defer { urls.forEach { $0.stopAccessingSecurityScopedResource() } }

        var manifestData: Data?
        var maFiles: [(filename: String, data: Data)] = []

        for url in urls {
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            let name = url.lastPathComponent
            if name == "manifest.json" {
                manifestData = data
            } else if url.pathExtension == "maFile" {
                maFiles.append((name, data))
            }
        }

        guard !maFiles.isEmpty else {
            importMode = .error("Не найдено ни одного .maFile среди выбранных файлов")
            return
        }

        var firstLoaded: SteamAccount?

        for (filename, data) in maFiles {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["shared_secret"] != nil {
                if let loaded = accountManager.importPlainData(data, filename: filename) {
                    if firstLoaded == nil { firstLoaded = loaded }
                }
                continue
            }

            guard let manifest = manifestData else {
                importMode = .error("Файл зашифрован.\n\nВыбери оба файла сразу:\n• \(filename)\n• manifest.json\n\nЗажми первый файл, потом тапни второй.")
                return
            }

            do {
                let (iv, salt) = try EncryptedMaFileManager.readManifest(
                    data: manifest, forFilename: filename
                )
                importMode = .encrypted(data: data, filename: filename, iv: iv, salt: salt)
                return
            } catch {
                importMode = .error("Ошибка manifest: \(error.localizedDescription)")
                return
            }
        }

        if let first = firstLoaded { selectedAccount = first }
    }

    func tryDecrypt(data: Data, filename: String, iv: Data, salt: Data, password: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let decrypted = try EncryptedMaFileManager.decrypt(
                    encryptedData: data, iv: iv, salt: salt, password: password
                )
                DispatchQueue.main.async {
                    self.importMode = .none
                    if let loaded = self.accountManager.importPlainData(decrypted, filename: filename) {
                        self.selectedAccount = loaded
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .maFileDecryptFailed,
                        object: error.localizedDescription
                    )
                }
            }
        }
    }

    func updateCode() {
        guard let account = selectedAccount else { return }
        if let result = SteamCrypto.generateCode(sharedSecret: account.shared_secret) {
            code = result.code; progress = result.progress
        }
    }
}

extension Notification.Name {
    static let maFileDecryptFailed = Notification.Name("maFileDecryptFailed")
}

struct PasswordOverlayView: View {
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var password = ""
    @State private var errorMsg: String?
    @State private var isLoading = false
    @State private var showPassword = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 24) {
                HStack {
                    Button("Отмена") { onCancel() }.foregroundColor(.blue)
                    Spacer()
                    Text("Зашифрованный файл").font(.headline)
                    Spacer()
                    Text("Отмена").foregroundColor(.clear)
                }
                Image(systemName: "lock.doc.fill").font(.system(size: 52)).foregroundColor(.blue)
                Text("Введите пароль, которым\nзашифрован ваш maFile")
                    .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)

                HStack {
                    Group {
                        if showPassword {
                            TextField("Пароль", text: $password).focused($focused)
                        } else {
                            SecureField("Пароль", text: $password).focused($focused)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { submit() }
                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye").foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .background(Color(UIColor.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if let msg = errorMsg {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.caption)
                        Text(msg).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
                    }
                }

                Button(action: submit) {
                    HStack(spacing: 10) {
                        if isLoading {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.85)
                        } else {
                            Image(systemName: "lock.open.fill")
                        }
                        Text(isLoading ? "Расшифровка..." : "Расшифровать").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(password.isEmpty ? Color.blue.opacity(0.4) : Color.blue)
                    .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(password.isEmpty || isLoading)
            }
            .padding(24)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 20)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .maFileDecryptFailed)) { note in
            isLoading = false
            errorMsg = note.object as? String ?? "Неверный пароль"
        }
    }

    private func submit() {
        guard !password.isEmpty, !isLoading else { return }
        isLoading = true; errorMsg = nil
        onSubmit(password)
    }
}

struct ErrorOverlayView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48)).foregroundColor(.orange)
                Text("Не удалось импортировать").font(.title3.bold())
                Text(message).font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Закрыть") { onDismiss() }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.blue).foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(28)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 24)
        }
    }
}

struct SteamLoginViewWrapper: View {
    @Binding var isPresented: Bool
    @Binding var isLoggedIn: Bool
    @Binding var cookies: [HTTPCookie]
    var body: some View {
        SteamWebView(url: URL(string: "https://steamcommunity.com/login/home/")!,
                     isPresented: $isPresented, isLoginMode: true,
                     cookiesCaptured: $isLoggedIn, capturedCookies: $cookies)
    }
}
