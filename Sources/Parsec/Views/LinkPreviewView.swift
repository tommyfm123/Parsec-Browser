import SwiftUI

struct LinkPreviewLayer: View {
    @Bindable var model: WindowModel

    var body: some View {
        GeometryReader { geometry in
            if let preview = model.linkPreview, preview.isVisible {
                let cardSize = model.store.settings.linkPreviewSize.cardSize
                let origin = LinkPreviewPlacement.origin(cardSize: cardSize, anchor: preview.anchorFrame, container: geometry.size)
                LinkPreviewCard(preview: preview, size: cardSize)
                    .id(preview.id)
                    .offset(x: origin.x, y: origin.y)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
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
    let preview: LinkPreviewState
    let size: CGSize

    private var displayHost: String {
        preview.url.host()?.replacingOccurrences(of: WebConstants.wwwPrefix, with: "") ?? preview.url.absoluteString
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            content
        }
        .frame(width: size.width, height: size.height)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: LinkPreviewMetrics.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LinkPreviewMetrics.cornerRadius, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vista previa de \(displayHost)")
    }

    @ViewBuilder
    private var content: some View {
        switch preview.phase {
        case .ready(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        case .failed:
            Label("No se pudo cargar la vista previa", systemImage: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            Color.clear
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            FaviconView(url: preview.url, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(preview.title.isEmpty ? displayHost : preview.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(displayHost)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: LinkPreviewMetrics.headerHeight)
    }
}
