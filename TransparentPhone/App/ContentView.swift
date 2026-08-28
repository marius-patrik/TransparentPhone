import SwiftUI

struct ContentView: View {
    @ObservedObject var model: TransparencyModel
    @State private var showControls = true

    var body: some View {
        ZStack {
            TransparencyView(pipeline: model.pipeline)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if showControls {
                    header
                    Spacer()
                    if !model.running {
                        startCard
                    } else {
                        controlBar
                    }
                }
            }

            if model.running && !showControls {
                VStack {
                    HStack {
                        statusPill
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 12)
                .padding(.leading, 12)
            }

            if model.calibrationProgress < 1 && model.running {
                calibrationOverlay
            }

            if let error = model.errorMessage {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.red.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
                        .padding()
                }
            }
        }
        .statusBarHidden(true)
        .onAppear { model.pipeline.prepare() }
        .onDisappear { model.stop() }
        .onTapGesture(count: 2) { showControls.toggle() }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.trackingQuality == .normal ? .green : .orange)
                .frame(width: 8, height: 8)
            Text(model.trackingQuality.rawValue)
                .font(.caption.monospaced())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.58), in: Capsule())
    }

    private var header: some View {
        HStack(spacing: 8) {
            statusPill
            Spacer()
            Button {
                model.debugOverlay.toggle()
                model.pipeline.debugOverlay = model.debugOverlay
            } label: {
                Image(systemName: "ladybug")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
    }

    private var startCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 44))
            Text("Transparent Phone")
                .font(.title2.bold())
            Text("The rear camera becomes a virtual window.\nMove your head after calibration to see depth-aware parallax.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Start") { model.start() }
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding()
    }

    private var controlBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                toggle("Parallax", icon: model.parallax ? "eye" : "eye.slash", value: model.parallax) {
                    model.parallax.toggle()
                    model.pipeline.setParallax(model.parallax)
                }
                toggle("Depth", icon: model.depthReprojection ? "square.3.layers.3d" : "square", value: model.depthReprojection) {
                    model.depthReprojection.toggle()
                    model.pipeline.setDepth(model.depthReprojection)
                }
                Button { model.calibrate() } label: {
                    Label("Calibrate", systemImage: "viewfinder")
                }
                .buttonStyle(.bordered)
                Button { model.stop() } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.borderedProminent)
            }

            HStack {
                Image(systemName: "circle.lefthalf.filled")
                Slider(value: Binding(get: { Double(model.strength) }, set: { model.setStrength(Float($0)) }), in: 0...2)
                Text(String(format: "%.1f×", model.strength))
                    .font(.caption.monospacedDigit())
                    .frame(width: 38)
            }
        }
        .padding(12)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
        .padding()
    }

    private func toggle(_ title: String, icon: String, value: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.bordered)
    }

    private var calibrationOverlay: some View {
        VStack(spacing: 12) {
            Text("Calibrating viewing position")
                .font(.headline)
            Text("Hold the phone naturally and look straight at the center of the display.")
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: model.calibrationProgress)
                .frame(width: 220)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
