import UIKit

/// Presents UIKit controllers (site alerts, share sheets) above whatever SwiftUI is showing.
@MainActor
enum Presenter {
    static var top: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        var controller = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed {
            controller = presented
        }
        return controller
    }

    @discardableResult
    static func present(_ controller: UIViewController) -> Bool {
        guard let top else { return false }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 90, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
        return true
    }

    static func share(_ items: [Any]) {
        present(UIActivityViewController(activityItems: items, applicationActivities: nil))
    }

    // MARK: Page dialogs (alert / confirm / prompt)

    static func alert(title: String?, message: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in continuation.resume() })
            if !present(alert) { continuation.resume() }
        }
    }

    static func confirm(title: String?, message: String) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in continuation.resume(returning: true) })
            if !present(alert) { continuation.resume(returning: false) }
        }
    }

    static func prompt(title: String?, message: String, defaultText: String?) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in continuation.resume(returning: nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                continuation.resume(returning: alert?.textFields?.first?.text ?? "")
            })
            if !present(alert) { continuation.resume(returning: nil) }
        }
    }
}
