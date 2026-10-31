import SwiftUI
import WebKit

/// Hosts a tab's long-lived WKWebView. The web view moves between hosts as tabs change.
struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .clear
        attach(to: host)
        return host
    }

    func updateUIView(_ host: UIView, context: Context) {
        if webView.superview !== host { attach(to: host) }
    }

    private func attach(to host: UIView) {
        host.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            webView.topAnchor.constraint(equalTo: host.topAnchor),
            webView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
    }
}
