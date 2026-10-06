import AppKit
import SwiftUI

enum DownloadRowMetrics {
    static let iconSize: CGFloat = 32
    static let progressHeight: CGFloat = 4
    static let cornerRadius: CGFloat = 10
    static let popoverWidth: CGFloat = 340
    static let popoverVisibleCount = 6
}

struct DownloadRow: View {
    @Bindable var item: DownloadItem
    @ViewState private var isHovering = false

    private var manager: DownloadManager { DownloadManager.shared }
    private var percent: Int { Int((item.fractionCompleted * 100).rounded()) }
    private var isUnavailable: Bool { item.state == .failed || item.state == .cancelled }

    private var status: String {
        switch item.state {
        case .inProgress: "Descargando · \(percent)%"
        case .paused: "En pausa · \(percent)%"
        case .finished: item.createdAt.formatted(.dateTime.hour().minute())
        case .failed: "Descarga interrumpida"
        case .cancelled: "Cancelada"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: item.fileIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: DownloadRowMetrics.iconSize, height: DownloadRowMetrics.iconSize)
                .opacity(isUnavailable ? 0.45 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isUnavailable ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.state.isActive {
                    DownloadProgressBar(progress: item.fractionCompleted, isPaused: item.state == .paused)
                }
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: DownloadRowMetrics.cornerRadius, style: .continuous).fill(Color.primary.opacity(isHovering ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { manager.open(item) }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 6) {
            switch item.state {
            case .inProgress:
                IconButton(symbolName: "pause.fill", label: "Pausar descarga") { manager.pause(item) }
                IconButton(symbolName: "xmark", label: "Cancelar descarga") { manager.cancel(item) }
            case .paused:
                IconButton(symbolName: "play.fill", label: "Reanudar descarga") { manager.resume(item) }
                IconButton(symbolName: "xmark", label: "Cancelar descarga") { manager.cancel(item) }
            case .finished:
                IconButton(symbolName: "magnifyingglass", label: "Mostrar en Finder") { manager.reveal(item) }
                    .opacity(isHovering ? 1 : 0)
                IconButton(symbolName: "trash", label: "Eliminar descarga") { manager.delete(item) }
                    .opacity(isHovering ? 1 : 0)
            case .failed, .cancelled:
                IconButton(symbolName: "trash", label: "Quitar de la lista") { manager.delete(item) }
                    .opacity(isHovering ? 1 : 0)
            }
        }
    }
}

struct DownloadProgressBar: View {
    let progress: Double
    let isPaused: Bool

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.primary.opacity(0.1))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(isPaused ? Color.secondary : Color.accentColor)
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
                }
        }
        .frame(height: DownloadRowMetrics.progressHeight)
        .animation(.easeOut(duration: 0.2), value: progress)
        .accessibilityElement()
        .accessibilityLabel("Progreso")
        .accessibilityValue("\(Int((progress * 100).rounded())) por ciento")
    }
}

struct DownloadsPopover: View {
    let onShowAll: () -> Void

    private var recentItems: [DownloadItem] { Array(DownloadManager.shared.items.prefix(DownloadRowMetrics.popoverVisibleCount)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Descargas").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Ver todas", action: onShowAll)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .clickable()
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            if recentItems.isEmpty {
                Text("Todavía no hay descargas")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                VStack(spacing: 2) {
                    ForEach(recentItems) { item in
                        DownloadRow(item: item)
                    }
                }
            }
        }
        .padding(8)
        .frame(width: DownloadRowMetrics.popoverWidth)
    }
}
