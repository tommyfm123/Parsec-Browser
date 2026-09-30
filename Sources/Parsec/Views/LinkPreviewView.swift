import SwiftUI

struct LinkPreviewLayer: View {
    @Bindable var model: WindowModel

    var body: some View {
        GeometryReader { geometry in
            if let preview = model.linkPreview {
                let cardSize = model.store.settings.linkPreviewSize.cardSize
                let origin = LinkPreviewPlacement.origin(cardSize: cardSize, anchor: preview.anchorFrame, container: geometry.size)
                LinkPreviewCard(model: model, preview: preview, size: cardSize)
                    .id(preview.id)
                    .offset(x: origin.x, y: origin.y)
                    .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }
        }
    }
}

enum LinkPreviewPlacement {
    static func origin(cardSize: CGSize, anchor: CGRect, container: CGSize) -> CGPoint {
        let margin = LinkPreviewMetrics.screenMargin
        let belowY = anchor.maxY + LinkPreviewMetrics.anchorGap
        let aboveY = anchor.minY - LinkPreviewMetrics.anchorGap - cardSize.height
        let fitsBelow = belowY + cardSize.height <= container.height - margin
        let preferredY = fitsBelow ? belowY : aboveY
        let maximumX = max(container.width - cardSize.width - margin, margin)
        let maximumY = max(container.height - cardSize.height - margin, margin)
        return CGPoint(x: min(max(anchor.minX, margin), maximumX), y: min(max(preferredY, margin), maximumY))
    }
}

struct LinkPreviewCard: View {
    @Bindable var model: WindowModel
    @Bindable var preview: LinkPreviewState
    let size: CGSize

    private var page: WebPage { preview.page }
    private var displayHost: String {
        (page.currentURL ?? preview.url).host()?.replacingOccurrences(of: WebConstants.wwwPrefix, with: "") ?? preview.url.absoluteString
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ZStack {
                WebViewHost(webView: page.webView)
                    .allowsHitTesting(false)
                if page.isLoading && !page.hasCommittedNavigation {
                    ProgressView().controlSize(.small)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: LinkPreviewMetrics.cornerRadius, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LinkPreviewMetrics.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
        .contentShape(Rectangle())
        .clickable()
        .onHover { model.setLinkPreviewHovered($0) }
        .onTapGesture { model.openLinkPreviewInTab() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Vista previa de \(displayHost). Abrir en una pestaña")
    }

    private var header: some View {
        HStack(spacing: 8) {
            FaviconView(url: page.currentURL ?? preview.url, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title.isEmpty ? displayHost : page.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(displayHost)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.forward.square")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: LinkPreviewMetrics.headerHeight)
    }
}
