import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LittleBrowserView: View {
    @Bindable var model: LittleWindowModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer().frame(width: 62)
                FaviconView(url: model.page.currentURL, size: 14)
                Text(model.page.title.isEmpty ? model.page.currentHost : model.page.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Button("Abrir en Parsec  ⌘O") {
                    (model.window as? LittleWindow)?.promoteToTabAction(nil)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(WindowDragArea())
            .background(.regularMaterial)
            ZStack(alignment: .top) {
                WebViewHost(webView: model.page.webView)
                LoadingLineView(page: model.page)
            }
        }
        .ignoresSafeArea()
    }
}
