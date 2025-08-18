import SwiftUI

struct BreathingBadge: View {
    @State private var rotation: Double = 0       // slow rotation
    @State private var breathe: Bool = false      // core “breathing” pulse
    @State private var ripple: Bool = false       // outward halo

    var body: some View {
        // Outer container reserves extra room so inner scale never clips.
        ZStack {
            // Expanding halo ring (stays inside the reserved container)
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color.orange.opacity(0.55),
                            Color.orange.opacity(0.15),
                            Color.orange.opacity(0.55)
                        ]),
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: 28, height: 28)
                .scaleEffect(ripple ? 1.3 : 0.92)
                .opacity(ripple ? 0.0 : 0.45)
                .blur(radius: 0.8)

            // Core rotating angular gradient
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color.orange,
                            Color(red: 1.0, green: 0.60, blue: 0.20),
                            Color.orange
                        ]),
                        center: .center
                    )
                )
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(rotation))

            // Inner breathing glow
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [Color.white.opacity(0.28), .clear]),
                        center: .center,
                        startRadius: 0, endRadius: 18
                    )
                )
                .frame(width: 28, height: 28)
                .opacity(breathe ? 0.7 : 0.35)
                .blendMode(.overlay)

            // WHITE edge so it blends with your window
            Circle()
                .stroke(Color.white.opacity(0.95), lineWidth: 1.4)
                .frame(width: 28, height: 28)
        }
        // Outer frame gives “air” so inner scale won’t cut off
        .frame(width: 32, height: 32)
        .scaleEffect(breathe ? 1.08 : 0.96) // the pulse (now clearly visible)
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                ripple.toggle()
            }
        }
        .accessibilityHidden(true)
        .drawingGroup() // smoother gradients on macOS
    }
}
