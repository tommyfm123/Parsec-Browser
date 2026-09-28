import AVFoundation
import SwiftUI

struct WelcomeView: View {
    private enum Phase: Int, Comparable {
        case idle
        case streaks
        case mark
        case wordmark
        case tagline
        case ready

        static func < (lhs: Phase, rhs: Phase) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private static let schedule: [(Phase, Duration)] = [
        (.streaks, .milliseconds(150)),
        (.mark, .milliseconds(450)),
        (.wordmark, .milliseconds(700)),
        (.tagline, .milliseconds(550)),
        (.ready, .milliseconds(800)),
    ]
    private static let markWidth: CGFloat = 120

    let onFinish: () -> Void
    @ViewState private var phase = Phase.idle
    @ViewState private var isLeaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white).ignoresSafeArea()
            if !reduceMotion {
                SpeedStreaks(isActive: phase >= .streaks)
            }
            VStack(spacing: 22) {
                mark
                VStack(spacing: 10) {
                    Text("Parsec")
                        .font(.system(size: 56, weight: .semibold, design: .default))
                        .tracking(-1.2)
                        .opacity(phase >= .wordmark ? 1 : 0)
                        .offset(y: phase >= .wordmark || reduceMotion ? 0 : 10)
                    VStack(spacing: 4) {
                        Text("El navegador ultraliviano.")
                            .font(.system(size: 22, weight: .medium))
                        Text("Rápido desde el primer clic.")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                    }
                    .opacity(phase >= .tagline ? 1 : 0)
                    .offset(y: phase >= .tagline || reduceMotion ? 0 : 8)
                }
                Button("Comenzar", action: leave)
                    .buttonStyle(BrandCapsuleButtonStyle())
                    .keyboardShortcut(.defaultAction)
                .opacity(phase >= .ready ? 1 : 0)
                .padding(.top, 18)
            }
        }
        .opacity(isLeaving ? 0 : 1)
        .scaleEffect(isLeaving && !reduceMotion ? 1.03 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if phase >= .ready { leave() } }
        .onExitCommand(perform: leave)
        .task { await play() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bienvenida a Parsec")
    }

    private var mark: some View {
        Group {
            if let image = BrandMark.image {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: Self.markWidth)
        .foregroundStyle(.primary)
        .mask(alignment: .leading) {
            Rectangle().frame(width: phase >= .mark ? Self.markWidth * 1.2 : 0)
        }
        .offset(x: phase >= .mark || reduceMotion ? 0 : -60)
        .blur(radius: phase >= .mark || reduceMotion ? 0 : 8)
    }

    private func play() async {
        if !reduceMotion && BrowserStore.shared.settings.playsSounds { WelcomeSound.shared.play() }
        for (nextPhase, delay) in Self.schedule {
            try? await Task.sleep(for: reduceMotion ? .milliseconds(120) : delay)
            withAnimation(animation(for: nextPhase)) { phase = nextPhase }
        }
    }

    private func animation(for nextPhase: Phase) -> Animation {
        guard !reduceMotion else { return .easeOut(duration: 0.3) }
        switch nextPhase {
        case .mark: return .spring(response: 0.55, dampingFraction: 0.82)
        case .streaks: return .easeOut(duration: 0.2)
        default: return .easeOut(duration: 0.6)
        }
    }

    private func leave() {
        guard !isLeaving else { return }
        withAnimation(.easeInOut(duration: 0.45)) { isLeaving = true }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            onFinish()
        }
    }
}

struct BrandCapsuleButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .padding(.horizontal, 34)
            .frame(height: 44)
            .background(Capsule().fill(colorScheme == .dark ? Color.white : Color.black))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct SpeedStreaks: View {
    private struct Streak: Identifiable {
        let id: Int
        let verticalPosition: CGFloat
        let length: CGFloat
        let thickness: CGFloat
        let delay: Double
    }

    private static let streaks = [
        Streak(id: 0, verticalPosition: 0.34, length: 0.42, thickness: 2, delay: 0),
        Streak(id: 1, verticalPosition: 0.42, length: 0.6, thickness: 3, delay: 0.05),
        Streak(id: 2, verticalPosition: 0.47, length: 0.35, thickness: 1.5, delay: 0.12),
        Streak(id: 3, verticalPosition: 0.53, length: 0.5, thickness: 2.5, delay: 0.08),
        Streak(id: 4, verticalPosition: 0.58, length: 0.3, thickness: 1.5, delay: 0.16),
        Streak(id: 5, verticalPosition: 0.66, length: 0.45, thickness: 2, delay: 0.1),
    ]

    let isActive: Bool

    var body: some View {
        GeometryReader { geometry in
            ForEach(Self.streaks) { streak in
                Capsule()
                    .fill(LinearGradient(colors: [.primary.opacity(0), .primary.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width * streak.length, height: streak.thickness)
                    .position(
                        x: isActive ? geometry.size.width * 1.4 : -geometry.size.width * streak.length,
                        y: geometry.size.height * streak.verticalPosition
                    )
                    .animation(.easeIn(duration: 0.7).delay(streak.delay), value: isActive)
            }
        }
        .allowsHitTesting(false)
    }
}

@MainActor
final class WelcomeSound {
    static let shared = WelcomeSound()
    private static let sampleRate = 44100
    private static let duration = 2.6
    private static let volume: Float = 0.8
    private static let whooshStart = 0.1
    private static let whooshLength = 0.6
    private static let airStart = 1.05
    private static let airLength = 0.9
    private static let chimeStart = 0.62
    private static let padFrequencies = [164.81, 246.94]
    private static let chimeFrequencies: [(frequency: Double, gain: Double, delay: Double)] = [
        (659.25, 0.22, 0), (987.77, 0.14, 0.04), (1318.5, 0.07, 0.09), (1975.5, 0.03, 0.12),
    ]

    private var player: AVAudioPlayer?

    func play() {
        guard let player = try? AVAudioPlayer(data: WaveFile.data(samples: samples(), sampleRate: Self.sampleRate)) else { return }
        player.volume = Self.volume
        player.play()
        self.player = player
    }

    private func samples() -> [Int16] {
        let frameCount = Int(Double(Self.sampleRate) * Self.duration)
        var generator = SystemRandomNumberGenerator()
        var filteredNoise = 0.0
        var previousRawNoise = 0.0
        return (0..<frameCount).map { frame in
            let time = Double(frame) / Double(Self.sampleRate)
            let rawNoise = Double.random(in: -1...1, using: &generator)
            filteredNoise += 0.08 * (rawNoise - filteredNoise)
            let airyNoise = (rawNoise - previousRawNoise) * 0.5
            previousRawNoise = rawNoise
            let sample = whoosh(at: time, noise: filteredNoise) + air(at: time, noise: airyNoise) + pad(at: time) + chime(at: time)
            return Int16(max(min(sample, 1), -1) * Double(Int16.max))
        }
    }

    private func whoosh(at time: Double, noise: Double) -> Double {
        let progress = (time - Self.whooshStart) / Self.whooshLength
        guard progress > 0, progress < 1 else { return 0 }
        return noise * sin(progress * .pi) * 0.35
    }

    private func air(at time: Double, noise: Double) -> Double {
        let progress = (time - Self.airStart) / Self.airLength
        guard progress > 0, progress < 1 else { return 0 }
        return noise * pow(sin(progress * .pi), 2) * 0.08
    }

    private func pad(at time: Double) -> Double {
        let localTime = time - Self.chimeStart
        guard localTime > 0 else { return 0 }
        let envelope = min(localTime / 0.25, 1) * exp(-localTime * 1.4)
        return Self.padFrequencies.reduce(0) { total, frequency in total + sin(2 * .pi * frequency * localTime) * 0.06 * envelope }
    }

    private func chime(at time: Double) -> Double {
        Self.chimeFrequencies.reduce(0) { total, partial in
            let localTime = time - Self.chimeStart - partial.delay
            guard localTime > 0 else { return total }
            let envelope = min(localTime / 0.008, 1) * exp(-localTime * 2.6)
            return total + sin(2 * .pi * partial.frequency * localTime) * partial.gain * envelope
        }
    }
}

enum WaveFile {
    private static let bitsPerSample: UInt16 = 16
    private static let channelCount: UInt16 = 1
    private static let pcmFormat: UInt16 = 1
    private static let formatChunkSize: UInt32 = 16

    static func data(samples: [Int16], sampleRate: Int) -> Data {
        let bytesPerSample = Int(bitsPerSample / 8)
        let dataSize = UInt32(samples.count * bytesPerSample)
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize, to: &data)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(formatChunkSize, to: &data)
        append(pcmFormat, to: &data)
        append(channelCount, to: &data)
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * bytesPerSample * Int(channelCount)), to: &data)
        append(UInt16(bytesPerSample) * channelCount, to: &data)
        append(bitsPerSample, to: &data)
        data.append(contentsOf: Array("data".utf8))
        append(dataSize, to: &data)
        samples.forEach { append($0, to: &data) }
        return data
    }

    private static func append<Value: FixedWidthInteger>(_ value: Value, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
