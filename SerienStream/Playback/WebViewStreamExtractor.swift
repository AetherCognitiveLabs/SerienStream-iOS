import Foundation
import WebKit

/// Extrahiert Direct-Stream-URLs, indem die Hoster-Embed-Seite in einer echten WKWebView
/// ausgeführt wird und die geladenen Ressourcen (performance entries + video src) nach
/// .m3u8/.mp4 durchsucht werden. Hoster-agnostisch — funktioniert auch für verschleierte
/// Player wie VOE, deren Quellen erst zur Laufzeit zusammengebaut werden.
final class WebViewStreamExtractor {
    /// Sucht in einer bereits geladenen WebView nach Stream-URLs. Versucht Autoplay.
    static func scan(in webView: WKWebView, embedURL: URL) async -> StreamResult? {
        // Autoplay-Versuche: Play-Buttons klicken, video play()
        let autoplayJS = """
        (function() {
            try {
                var v = document.querySelector('video');
                if (v) { v.muted = true; v.play().catch(function(){}); }
                var buttons = document.querySelectorAll('.play, .play-button, #play, .vjs-big-play-button, [class*="play"]');
                for (var i = 0; i < Math.min(buttons.length, 3); i++) {
                    try { buttons[i].click(); } catch(e) {}
                }
            } catch(e) {}
            return 'ok';
        })();
        """
        _ = try? await webView.evaluateJavaScript(autoplayJS)

        // Mehrere Scan-Runden — manche Hoster laden das m3u8 erst nach Klick/Delay
        for attempt in 0..<12 {
            try? await Task.sleep(nanoseconds: UInt64(1.5 * Double(NSEC_PER_SEC)))
            let scanJS = """
            (function() {
                var found = [];
                try {
                    if (window.__ssStreamURLs && window.__ssStreamURLs.length) {
                        for (var k = 0; k < window.__ssStreamURLs.length; k++) found.push(window.__ssStreamURLs[k]);
                    }
                } catch(e) {}
                try {
                    var entries = performance.getEntriesByType('resource');
                    for (var i = 0; i < entries.length; i++) {
                        var n = entries[i].name;
                        var path = n.split('?')[0].split('#')[0].toLowerCase();
                        if (/\\.(m3u8|mp4)$/i.test(path) && !/jwpltx|doubleclick|googlesyndication|imasdk|tracking|analytics|ping\\./i.test(n)) found.push(n);
                    }
                } catch(e) {}
                try {
                    var v = document.querySelector('video');
                    if (v && v.src && v.src.startsWith('http') && !v.src.startsWith('blob')) found.push(v.src);
                    var sources = document.querySelectorAll('video source, source');
                    for (var j = 0; j < sources.length; j++) {
                        if (sources[j].src && sources[j].src.startsWith('http')) found.push(sources[j].src);
                    }
                } catch(e) {}
                return found;
            })();
            """
            guard let result = try? await webView.evaluateJavaScript(scanJS),
                  let urls = result as? [String], !urls.isEmpty else {
                // Nach ein paar Runden nochmal Autoplay versuchen
                if attempt == 3 {
                    _ = try? await webView.evaluateJavaScript(autoplayJS)
                }
                continue
            }
            // master.m3u8 (adaptive) zuerst, dann andere m3u8, dann mp4
            let sorted = urls.sorted { a, b in
                func rank(_ u: String) -> Int {
                    if u.contains("master") && u.contains(".m3u8") { return 0 }
                    if u.contains(".m3u8") { return 1 }
                    return 2
                }
                return rank(a) < rank(b)
            }
            for candidate in sorted {
                guard let url = URL(string: candidate),
                      let scheme = url.scheme, scheme.hasPrefix("http") else { continue }
                // Master-Playlist einer HLS-URL ist ideal; werbe-tracking URLs filtern
                if candidate.contains("ads") || candidate.contains("tracking") || candidate.contains("imasdk") {
                    continue
                }
                var headers: [String: String] = [
                    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
                ]
                if let eScheme = embedURL.scheme, let eHost = embedURL.host {
                    headers["Referer"] = "\(eScheme)://\(eHost)/"
                    headers["Origin"] = "\(eScheme)://\(eHost)"
                }
                DLog("Stream in WebView gefunden (Versuch \(attempt + 1)): \(candidate)", category: "extract")
                return StreamResult(streamURL: url, headers: headers)
            }
        }
        return nil
    }
}
