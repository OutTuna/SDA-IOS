import SwiftUI
import Combine
import UniformTypeIdentifiers
import WebKit

struct ContentView: View {
    @StateObject private var accountManager = AccountManager()
    @StateObject private var tradeManager = SteamTradeManager()
    
    @State private var selectedAccount: SteamAccount?
    @State private var code: String = "---"
    @State private var progress: Float = 0.0
    @State private var isImporting = false
    @State private var showDeleteAlert = false
    
    @State private var showLoginSheet = false
    @State private var isLoggedIn = false
    @State private var cookies: [HTTPCookie] = []
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    if accountManager.accounts.isEmpty {
                        emptyStateView
                    } else {
                        accountPickerView
                    }
                    Spacer()
                    
                    if let account = selectedAccount {
                        codeDisplayView(account: account)
                    } else if !accountManager.accounts.isEmpty {
                        Text("Загрузка...").foregroundColor(.gray)
                    }
                    Spacer()
                }
            }
            .navigationTitle("Steam Guard")
            .toolbar {
                Button(action: { isImporting = true }) {
                    Image(systemName: "plus").font(.title2)
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                handleImport(result: result)
            }
            .sheet(isPresented: $showLoginSheet) {
                SteamLoginViewWrapper(isPresented: $showLoginSheet, isLoggedIn: $isLoggedIn, cookies: $cookies)
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
        .onReceive(timer) { _ in updateCode() }
        .onAppear {
            if let first = accountManager.accounts.first, selectedAccount == nil {
                selectedAccount = first
            }
        }
        .onChange(of: accountManager.accounts) { newAccounts in
            if selectedAccount != nil && !newAccounts.contains(selectedAccount!) { selectedAccount = nil }
            if selectedAccount == nil, let first = newAccounts.first { selectedAccount = first }
        }
    }
    
    var emptyStateView: some View {
        VStack(spacing: 15) {
            Image(systemName: "shield.checkerboard").font(.system(size: 60)).foregroundColor(.blue)
            Text("Нет аккаунтов").font(.headline)
        }
        .padding()
    }
    
    var accountPickerView: some View {
        HStack {
            Picker("", selection: $selectedAccount) {
                ForEach(accountManager.accounts, id: \.self) { account in
                    Text(account.account_name).tag(account as SteamAccount?)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
            
            if selectedAccount != nil {
                Button(action: { showDeleteAlert = true }) {
                    Image(systemName: "trash").foregroundColor(.red).padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(10)
                }
            }
        }
        .padding(.horizontal)
    }
    
    func codeDisplayView(account: SteamAccount) -> some View {
        VStack(spacing: 20) {
            Text(account.account_name).font(.title3).bold().foregroundColor(.white)
            
            Text(code)
                .font(.system(size: 64, weight: .bold, design: .monospaced))
                .foregroundColor(.blue)
                .shadow(color: .blue.opacity(0.5), radius: 10)
                .onTapGesture { UIPasteboard.general.string = code }
            
            ProgressView(value: 1.0 - progress)
                .padding(.horizontal, 50)
                .tint(progress > 0.8 ? .red : .blue)
            
            Text("Нажми на код для копирования").font(.caption2).foregroundColor(.gray)
            
            HStack(spacing: 20) {
                // Кнопка ВХОДА (Оставляем рабочей, пригодится)
                Button(action: { showLoginSheet = true }) {
                    Label(isLoggedIn ? "Перевойти" : "Войти", systemImage: "person.circle")
                        .padding().background(Color.gray.opacity(0.3)).cornerRadius(10)
                }
                
                // КНОПКА ЗАГЛУШКА (SOON)
                Button(action: {}) {
                    Label("Трейды (Soon)", systemImage: "arrow.left.arrow.right")
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.gray)
                        .cornerRadius(10)
                }
                .disabled(true)
            }
            .padding(.top, 10)
        }
    }
    
    func handleImport(result: Result<[URL], Error>) {
        do {
            guard let selectedFile: URL = try result.get().first else { return }
            if selectedFile.startAccessingSecurityScopedResource() {
                if let loaded = accountManager.importFile(at: selectedFile) {
                    DispatchQueue.main.async { self.selectedAccount = loaded }
                }
                selectedFile.stopAccessingSecurityScopedResource()
            }
        } catch { print("Error: \(error)") }
    }
    
    func updateCode() {
        guard let account = selectedAccount else { return }
        if let result = SteamCrypto.generateCode(sharedSecret: account.shared_secret) {
            self.code = result.code
            self.progress = result.progress
        }
    }
}

struct SteamLoginViewWrapper: View {
    @Binding var isPresented: Bool
    @Binding var isLoggedIn: Bool
    @Binding var cookies: [HTTPCookie]
    
    var body: some View {
        SteamWebView(
            url: URL(string: "https://steamcommunity.com/login/home/")!,
            isPresented: $isPresented,
            isLoginMode: true,
            cookiesCaptured: $isLoggedIn,
            capturedCookies: $cookies
        )
    }
}
