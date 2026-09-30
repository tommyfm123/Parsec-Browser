import AppKit
import SwiftUI

struct ThemePreset: Identifiable {
    let name: String
    let colors: [ThemeColor]
    var id: String { name }

    static let all: [ThemePreset] = [
        ThemePreset(name: "Niebla", colors: [ThemeColor(red: 0.84, green: 0.85, blue: 0.88)]),
        ThemePreset(name: "Arena", colors: [ThemeColor(red: 0.94, green: 0.88, blue: 0.79), ThemeColor(red: 0.86, green: 0.76, blue: 0.66)]),
        ThemePreset(name: "Lavanda", colors: [ThemeColor(red: 0.79, green: 0.75, blue: 0.96), ThemeColor(red: 0.94, green: 0.81, blue: 0.91)]),
        ThemePreset(name: "Océano", colors: [ThemeColor(red: 0.56, green: 0.76, blue: 0.96), ThemeColor(red: 0.36, green: 0.5, blue: 0.86)]),
        ThemePreset(name: "Menta", colors: [ThemeColor(red: 0.72, green: 0.93, blue: 0.85), ThemeColor(red: 0.55, green: 0.8, blue: 0.8)]),
        ThemePreset(name: "Durazno", colors: [ThemeColor(red: 1, green: 0.82, blue: 0.72), ThemeColor(red: 0.98, green: 0.62, blue: 0.64)]),
        ThemePreset(name: "Aurora", colors: [ThemeColor(red: 0.36, green: 0.31, blue: 0.76), ThemeColor(red: 0.86, green: 0.46, blue: 0.7), ThemeColor(red: 1, green: 0.72, blue: 0.52)]),
        ThemePreset(name: "Bosque", colors: [ThemeColor(red: 0.2, green: 0.36, blue: 0.31), ThemeColor(red: 0.11, green: 0.2, blue: 0.2)]),
        ThemePreset(name: "Medianoche", colors: [ThemeColor(red: 0.13, green: 0.13, blue: 0.22), ThemeColor(red: 0.05, green: 0.05, blue: 0.1)]),
        ThemePreset(name: "Grafito", colors: [ThemeColor(red: 0.3, green: 0.3, blue: 0.33)]),
    ]
}

struct ThemeSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            content
        }
    }
}

struct ThemePreviewView: View {
    let theme: SpaceTheme
    let title: String

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 4) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { dotColor in
                        Circle().fill(dotColor.opacity(0.85)).frame(width: 7, height: 7)
                    }
                }
                .padding(.bottom, 4)
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(index == 1 ? 0.16 : 0.07))
                        .frame(height: 14)
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 130)
            .themedForeground(theme)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                .padding(8)
        }
        .frame(height: 150)
        .background(SpaceBackgroundView(theme: theme))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct NewSpaceView: View {
    @Bindable var model: WindowModel
    @Environment(\.dismiss) private var dismiss
    @ViewState private var title = ""
    @ViewState private var selectedProfileID: UUID?
    @ViewState private var isCreatingProfile = false
    @ViewState private var newProfileName = ""
    @ViewState private var presetName = ThemePreset.all[3].name

    private var store: BrowserStore { BrowserStore.shared }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }
    private var selectedPreset: ThemePreset { ThemePreset.all.first { $0.name == presetName } ?? ThemePreset.all[0] }
    private var previewTheme: SpaceTheme {
        var theme = SpaceTheme.standard
        theme.colors = selectedPreset.colors
        return theme
    }
    private var canCreate: Bool {
        !trimmedTitle.isEmpty && (!isCreatingProfile || !newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            BrandedSheetHeader(title: "Nuevo Space", subtitle: "Un espacio con sus propias pestañas, carpetas y colores.")
            ThemePreviewView(theme: previewTheme, title: trimmedTitle.isEmpty ? "Nuevo Space" : trimmedTitle)
            TextField("Nombre del Space", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Color.primary.opacity(0.05)))
            ThemeSection(title: "Perfil") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(store.profiles) { profile in
                            ProfileCard(
                                name: profile.name,
                                detail: Self.spaceCountLabel(store.spaceIDs(usingProfile: profile.id).count),
                                symbolName: nil,
                                isSelected: !isCreatingProfile && selectedProfileID == profile.id
                            ) {
                                isCreatingProfile = false
                                selectedProfileID = profile.id
                            }
                        }
                        ProfileCard(name: "Nuevo perfil", detail: "Logins separados", symbolName: "person.crop.circle.badge.plus", isSelected: isCreatingProfile) {
                            isCreatingProfile = true
                        }
                    }
                    .padding(3)
                }
                .scrollClipDisabled()
                if isCreatingProfile {
                    TextField("Nombre del perfil, por ejemplo Cliente A", text: $newProfileName)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Color.primary.opacity(0.05)))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            ThemeSection(title: "Estilo") {
                HStack(spacing: 10) {
                    ForEach(ThemePreset.all) { preset in
                        Button { presetName = preset.name } label: {
                            Circle()
                                .fill(LinearGradient(colors: preset.colors.count == 1 ? [preset.colors[0].color, preset.colors[0].color] : preset.colors.map(\.color), startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(Circle().strokeBorder(Color.primary.opacity(presetName == preset.name ? 0.8 : 0.12), lineWidth: presetName == preset.name ? 2 : 1))
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                        .accessibilityLabel("Estilo \(preset.name)")
                    }
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.sheetSecondary)
                Button("Crear Space") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.sheetPrimary)
                    .disabled(!canCreate)
            }
        }
        .padding(28)
        .frame(width: 520)
        .animation(.easeOut(duration: 0.2), value: isCreatingProfile)
        .onAppear { selectedProfileID = model.currentSpace.profileID }
    }

    private static func spaceCountLabel(_ count: Int) -> String {
        count == 1 ? "1 Space" : "\(count) Spaces"
    }

    private func create() {
        let profileID = isCreatingProfile ? store.addProfile(name: newProfileName.trimmingCharacters(in: .whitespaces)).id : selectedProfileID ?? model.currentSpace.profileID
        let space = store.addSpace(title: trimmedTitle, profileID: profileID, theme: previewTheme)
        model.switchToSpace(space)
        dismiss()
    }
}

struct BrandedSheetHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            BrandTile(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 18, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

struct BrandTile: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(white: 0.93)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(Color.black.opacity(0.08)))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            if let mark = BrandMark.image {
                Image(nsImage: mark)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color(white: 0.05))
                    .padding(size * 0.2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ProfileCard: View {
    let name: String
    let detail: String
    let symbolName: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let symbolName {
                        Image(systemName: symbolName).font(.system(size: 15, weight: .medium))
                    } else {
                        Text(String(name.prefix(1)).uppercased()).font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                }
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(12)
            .frame(width: 128, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.primary.opacity(isSelected ? 0.08 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SitePopoverView: View {
    @Bindable var model: WindowModel

    private var store: BrowserStore { BrowserStore.shared }
    private var host: String { model.activePage?.currentHost ?? "" }
    private var isSecure: Bool { model.activePage?.currentURL?.scheme == WebConstants.httpsScheme }

    private var blockerBinding: Binding<Bool> {
        Binding(
            get: { !store.isBlockerDisabled(host: host) },
            set: { isEnabled in
                store.setBlocker(enabled: isEnabled, host: host)
                model.reload()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: isSecure ? "lock.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isSecure ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(host).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(isSecure ? "Conexión segura" : "Conexión no cifrada").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Divider()
            Toggle("Bloquear anuncios y rastreadores", isOn: blockerBinding)
                .toggleStyle(.switch)
                .disabled(model.isPrivate && host.isEmpty)
            let permissions = store.permissions(profileID: model.profileID, host: host)
            if !permissions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(permissions, id: \.kind.rawValue) { permission in
                        Label("\(permission.kind.label.capitalized): \(permission.isGranted ? "permitido" : "bloqueado")", systemImage: permission.isGranted ? "checkmark.circle" : "xmark.circle")
                            .font(.system(size: 12))
                    }
                    Button("Restablecer permisos") { store.resetPermissions(profileID: model.profileID, host: host) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12))
                }
            }
            let credentialCount = PasswordVault.shared.credentials(forHost: host).count
            if credentialCount > 0 {
                Button("Rellenar contraseña (\(credentialCount))  ⌘\\") {
                    model.isSitePopoverPresented = false
                    model.fillPassword()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct DownloadsView: View {
    private var manager: DownloadManager { DownloadManager.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Descargas").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Limpiar") { manager.clearFinished() }.buttonStyle(.borderless).font(.system(size: 12))
            }
            if manager.items.isEmpty {
                Text("Todavía no hay descargas").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(manager.items) { item in
                DownloadRow(item: item)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

struct DownloadRow: View {
    let item: DownloadItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.state == .failed ? "exclamationmark.circle" : "doc")
                .foregroundStyle(item.state == .failed ? Color.red : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                if item.state == .inProgress {
                    ProgressView(value: item.fractionCompleted).controlSize(.small)
                }
            }
            Spacer()
            if item.state == .finished {
                Button { DownloadManager.shared.reveal(item) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help("Mostrar en Finder")
                    .accessibilityLabel("Mostrar en Finder")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { DownloadManager.shared.open(item) }
    }
}
