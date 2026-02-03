import SwiftUI
import WebKit

struct SteamWebView: UIViewRepresentable {
    let url: URL
    @Binding var isPresented: Bool
    var isLoginMode: Bool
    @Binding var cookiesCaptured: Bool
    
    var capturedCookies: Binding<[HTTPCookie]>? = nil
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: SteamWebView
        
        init(parent: SteamWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if parent.isLoginMode {
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    if cookies.contains(where: { $0.name == "steamLoginSecure" }) {
                        print("Ура! Мы залогинились.")
                        
                        self.parent.cookiesCaptured = true
                        self.parent.capturedCookies?.wrappedValue = cookies
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.parent.isPresented = false
                        }
                    }
                }
            }
        }
    }
}
