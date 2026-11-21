import SwiftUI
import WebKit

/// Renders Markdown with $...$ / $$...$$ LaTeX using bundled KaTeX + marked (works offline).
/// By default sizes itself to its content height and ignores touches (the page around it scrolls).
/// With `maxHeight`, it never grows past that and scrolls its own content (also a backstop if the measured height
/// is ever short). With `fill`, it takes all available space and scrolls itself (for full-screen solutions).
struct MathText: View {
    let markdown: String
    var fontSize: CGFloat = 20
    var maxHeight: CGFloat? = nil
    var fill = false
    @State private var height: CGFloat = 40

    var body: some View {
        let scrolls = fill || maxHeight != nil
        let web = MathWebView(markdown: markdown, fontSize: fontSize, scrolls: scrolls, height: $height)
        if fill {
            web
        } else if let maxHeight {
            web.frame(height: min(height, maxHeight))
        } else {
            web.frame(height: height)
        }
    }

    /// Cheap plain-text preview for long lists (no web view).
    static func plainPreview(_ markdown: String) -> String {
        markdown.replacingOccurrences(of: "$$", with: " ")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

private struct MathWebView: UIViewRepresentable {
    let markdown: String
    let fontSize: CGFloat
    let scrolls: Bool
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "height")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = scrolls
        view.scrollView.bounces = scrolls
        view.scrollView.showsVerticalScrollIndicator = scrolls
        // Display-only text lets every touch (finger or Pencil) fall through to the scrolling page around it, so
        // WebKit's text-selection gestures can never swallow a scroll. Self-scrolling text takes touches itself.
        view.isUserInteractionEnabled = scrolls
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let key = "\(fontSize)|\(markdown)"
        guard context.coordinator.loadedKey != key else { return }
        context.coordinator.loadedKey = key
        let html = Self.html(markdown: markdown, fontSize: fontSize)
        context.coordinator.lastHTML = html
        view.loadHTMLString(html, baseURL: Self.baseURL)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "height")
    }

    static let baseURL: URL? = Bundle.main.url(forResource: "katex", withExtension: nil)

    static func html(markdown: String, fontSize: CGFloat) -> String {
        let json = (try? String(data: JSONSerialization.data(withJSONObject: [markdown]), encoding: .utf8)) ?? "[\"\"]"
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <link rel="stylesheet" href="katex.min.css">
        <script src="katex.min.js"></script>
        <script src="marked.min.js"></script>
        <style>
          :root { color-scheme: light dark; }
          body { margin: 0; padding: 0 0 2px 0; font: -apple-system-body; font-family: -apple-system, sans-serif;
                 font-size: \(Int(fontSize))px; line-height: 1.45; color: #1c1c1e; background: transparent;
                 -webkit-text-size-adjust: none; overflow-wrap: anywhere; }
          @media (prefers-color-scheme: dark) { body { color: #f2f2f7; } }
          #c { display: flow-root; } /* keep children's margins inside the measured height */
          p { margin: 0 0 0.5em 0; } p:last-child { margin-bottom: 0; }
          ol, ul { margin: 0.2em 0 0.5em 0; padding-left: 2.4em; } li { margin: 0.15em 0; }
          #c > :last-child { margin-bottom: 0; }
          table { border-collapse: collapse; } td, th { border: 1px solid #8e8e93; padding: 4px 10px; }
          .katex-display { margin: 0.4em 0; overflow-x: auto; overflow-y: hidden; }
        </style></head><body><div id="c"></div>
        <script>
          const src = \(json)[0];
          const math = [];
          // Pull math out first so Markdown doesn't mangle underscores/asterisks inside LaTeX.
          let s = src.replace(/\\\\\\$/g, '@@D@@').replace(/\\$\\$([\\s\\S]+?)\\$\\$/g, (_, m) => { math.push([m, true]); return '@@M' + (math.length - 1) + '@@'; })
                     .replace(/\\$([^$\\n]+?)\\$/g, (_, m) => { math.push([m, false]); return '@@M' + (math.length - 1) + '@@'; });
          let html = marked.parse(s, { breaks: true });
          html = html.replace(/@@M(\\d+)@@/g, (_, i) => {
            const [m, display] = math[+i];
            try { return katex.renderToString(m, { displayMode: display, throwOnError: false }); }
            catch (e) { return m; }
          }).replace(/@@D@@/g, '$');
          document.getElementById('c').innerHTML = html;
          function report() { window.webkit.messageHandlers.height.postMessage(document.getElementById('c').scrollHeight + 4); }
          report(); new ResizeObserver(report).observe(document.getElementById('c'));
          document.fonts && document.fonts.ready.then(report);
        </script></body></html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        /// iPadOS can terminate a web view's content process under memory pressure, leaving it blank. Redraw.
        var lastHTML: String?
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if let lastHTML { webView.loadHTMLString(lastHTML, baseURL: MathWebView.baseURL) }
        }

        var height: Binding<CGFloat>
        var loadedKey: String?
        init(height: Binding<CGFloat>) { self.height = height }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let h = message.body as? Double, h > 0 else { return }
            DispatchQueue.main.async { self.height.wrappedValue = CGFloat(h) }
        }
    }
}
