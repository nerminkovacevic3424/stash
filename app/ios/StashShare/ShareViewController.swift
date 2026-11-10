import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Principal class of the Share Extension. Hosts the SwiftUI sheet on a clear
/// background so Instagram/TikTok stay visible behind it.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        Task { @MainActor in
            let text = await sharedText()
            let model = ShareModel(sharedText: text) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
            let host = UIHostingController(rootView: ShareSheetView(model: model))
            host.view.backgroundColor = .clear
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
            await model.start()
        }
    }

    /// Instagram and TikTok share a URL item, plain text containing the link, or both.
    private func sharedText() async -> String? {
        var parts: [String] = []
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            if let text = item.attributedContentText?.string, !text.isEmpty { parts.append(text) }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                    let url = await load(provider, UTType.url.identifier) as? URL
                {
                    parts.append(url.absoluteString)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                    let text = await load(provider, UTType.plainText.identifier) as? String
                {
                    parts.append(text)
                }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func load(_ provider: NSItemProvider, _ type: String) async -> NSSecureCoding? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }
}
