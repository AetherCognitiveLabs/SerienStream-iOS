import Foundation
import WebKit

/// Löst das SerienStream-Redirect-Gate (Turnstile/ALTCHA) über eine echte WKWebView
/// und fängt die finale Hoster-Embed-URL ab.
final class StreamResolver: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case loadingPage
        case waitingForGate      // Turnstile/ALTCHA läuft — ggf. User-Interaktion nötig
        case resolvingEmbed
        case extractingStream
        case done(URL)           // Embed-URL gefunden
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var webView: WKWebView?

    private var episodePath: String = ""
    private var linkId: String = ""
    private var baseURL: String = ""
    private var completion: ((Result<URL, Error>) -> Void)?
    private var timeoutTask: Task<Void, Never>?
    private var autoSubmitInjected = false

    private static let allowedHosts = ["serienstream.to", "serienstream.cx", "186.2.175.5"]

    func resolve(episodePath: String, link: EpisodeLink, baseURL: String) async throws -> URL {
        self.episodePath = episodePath
        self.linkId = link.linkId
        self.baseURL = baseURL
        return try await withCheckedThrowingContinuation { cont in
            self.completion = { result in
                cont.resume(with: result)
            }
            DispatchQueue.main.async {
                self.state = .loadingPage
                self.startWebView()
            }
        }
    }

    func cancel() {
        timeoutTask?.cancel()
        finish(.failure(AppError.resolutionFailed("Abgebrochen")))
    }

    private func startWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        self.webView = wv

        guard let url = URL(string: baseURL + episodePath) else {
            finish(.failure(AppError.resolutionFailed("Ungültige URL")))
            return
        }
        DLog("Lade Episodenseite: \(url.absoluteString)", category: "resolver")
        wv.load(URLRequest(url: url))

        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            if !Task.isCancelled {
                DispatchQueue.main.async {
                    if case .done = self.state {} else {
                        self.finish(.failure(AppError.resolutionFailed("Zeitüberschreitung beim Laden des Streams")))
                    }
                }
            }
        }
    }

    private func clickHosterButton() {
        guard !autoSubmitInjected else { return }
        autoSubmitInjected = true
        let js = """
        (function() {
            var btn = document.querySelector('.link-box[data-link-id="\(linkId)"]');
            if (btn) { btn.click(); }
            // Auto-submit sobald Turnstile gelöst ist
            var tries = 0;
            var timer = setInterval(function() {
                tries++;
                var response = document.querySelector('[name="cf-turnstile-response"]');
                var form = document.getElementById('player-prepare-form');
                if (response && response.value && response.value.length > 10 && form) {
                    clearInterval(timer);
                    form.requestSubmit ? form.requestSubmit() : form.submit();
                }
                if (tries > 120) clearInterval(timer);
            }, 500);
            return btn ? 'clicked' : 'missing';
        })();
        """
        webView?.evaluateJavaScript(js) { result, error in
            if let error {
                DLog("Hoster-Klick JS-Fehler: \(error.localizedDescription)", category: "resolver")
            } else {
                DLog("Hoster-Klick: \(result ?? "nil")", category: "resolver")
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        timeoutTask?.cancel()
        guard let completion else { return }
        self.completion = nil
        switch result {
        case .success(let url):
            state = .done(url)
        case .failure(let error):
            state = .failed(error.localizedDescription)
        }
        completion(result)
    }

    private func isAllowedHost(_ host: String?) -> Bool {
        guard let host else { return true }
        return Self.allowedHosts.contains(host) || host.hasSuffix("challenges.cloudflare.com")
    }
}

extension StreamResolver: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.clickHosterButton()
            self.state = .waitingForGate
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let host = url.host else {
            decisionHandler(.allow)
            return
        }
        // Challenge-Iframes (Turnstile/ALTCHA) müssen durchgelassen werden
        if host.contains("challenges.cloudflare.com") || host.contains("cloudflare") {
            decisionHandler(.allow)
            return
        }
        // Navigationen weg von serienstream → das ist die Hoster-Embed-URL
        let isSS = Self.allowedHosts.contains(host)
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true

        if !isSS {
            // about:blank, data:, blob: etc. ignorieren
            if url.scheme == "about" || url.scheme == "data" || url.scheme == "blob" {
                decisionHandler(.allow)
                return
            }
            // Erfolg nur bei echten http(s)-Navigationen zu externen Hosts
            if url.scheme == "http" || url.scheme == "https" {
                DLog("Embed-URL abgefangen: \(url.absoluteString)", category: "resolver")
                state = .resolvingEmbed
                finish(.success(url))
                decisionHandler(.cancel)
                return
            }
        }
        _ = isMainFrame
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Nicht jeder Fehler ist fatal (iframe-Abbrüche etc.)
    }
}

extension StreamResolver: WKUIDelegate {
    // Popups/Popunder blockieren, aber echte Hoster-Redirects abfangen
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, !isAllowedHost(url.host) {
            finish(.success(url))
        }
        return nil
    }
}
