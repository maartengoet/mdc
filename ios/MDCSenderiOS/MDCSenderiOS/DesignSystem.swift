import SwiftUI

extension View {
    @ViewBuilder
    func mdcGlass<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
    }

    func glassCard(cornerRadius: CGFloat = 30) -> some View {
        padding(14)
            .mdcGlass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: true)
    }
}

struct PrimaryGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.blue.gradient)
                    .shadow(color: .blue.opacity(configuration.isPressed ? 0.1 : 0.32), radius: 20, y: 10)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct IconGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(width: 54, height: 54)
            .mdcGlass(Circle(), interactive: true)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct StatusPill: View {
    let phase: SendPhase

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(phase.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(phase.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .mdcGlass(Capsule(), interactive: false)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch phase {
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .idle:
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
        default:
            ProgressView()
                .controlSize(.mini)
        }
    }
}
