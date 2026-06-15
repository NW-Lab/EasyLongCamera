import SwiftUI

// タイマーモードで選べるプリセット露光時間（秒）
private let exposurePresets: [Double] = [
    0.5, 1, 2, 4, 8, 15, 30
]

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var bleManager = BLEManager()

    var body: some View {
        ZStack {
            // カメラプレビュー
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── 上部：BLE接続状態 ──
                HStack {
                    Circle()
                        .fill(bleStatusColor)
                        .frame(width: 10, height: 10)
                    Text(bleStatusText)
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(8)
                .background(Color.black.opacity(0.5))
                .cornerRadius(20)
                .padding(.top, 50)

                if let notice = cameraManager.captureNotice {
                    Text(notice)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.55))
                        .cornerRadius(12)
                        .padding(.top, 8)
                }

                Spacer()

                // ── 中央：露光中の経過時間 ──
                if cameraManager.isCapturing {
                    VStack(spacing: 4) {
                        Text(String(format: "%.1f s", cameraManager.elapsedSeconds))
                            .font(.system(size: 64, weight: .thin, design: .monospaced))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 4)
                        if cameraManager.shootingMode == .timer {
                            Text("/ \(formatSeconds(cameraManager.selectedExposureSeconds))")
                                .font(.system(size: 20, weight: .light, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.bottom, 20)
                }

                Spacer()

                // ── 下部コントロールパネル ──
                VStack(spacing: 16) {

                    // モード切替セグメント
                    Picker("Mode", selection: $cameraManager.shootingMode) {
                        Text("Bulb").tag(ShootingMode.bulb)
                        Text("Timer").tag(ShootingMode.timer)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 40)
                    .disabled(cameraManager.isCapturing)

                    // タイマーモード：露光時間プリセット選択
                    if cameraManager.shootingMode == .timer {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(exposurePresets, id: \.self) { preset in
                                    Button(action: {
                                        cameraManager.selectedExposureSeconds = preset
                                    }) {
                                        Text(formatSeconds(preset))
                                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                                            .foregroundColor(
                                                cameraManager.selectedExposureSeconds == preset
                                                ? .black : .white
                                            )
                                            .frame(width: 52, height: 36)
                                            .background(
                                                cameraManager.selectedExposureSeconds == preset
                                                ? Color.white : Color.white.opacity(0.2)
                                            )
                                            .cornerRadius(8)
                                    }
                                    .disabled(cameraManager.isCapturing)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // シャッターボタン
                    VStack(spacing: 6) {
                        Text(shutterHintText)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))

                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 80, height: 80)

                            Circle()
                                .fill(cameraManager.isCapturing ? Color.red.opacity(0.85) : Color.white.opacity(0.9))
                                .frame(width: 68, height: 68)
                                .scaleEffect(cameraManager.isCapturing ? 1.08 : 1.0)
                                .animation(.easeInOut(duration: 0.15), value: cameraManager.isCapturing)
                        }
                        .gesture(shutterGesture)
                    }
                    .padding(.bottom, 50)
                }
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            // 露光中：画面周囲を赤枠で強調
            if cameraManager.isCapturing {
                Rectangle()
                    .fill(Color.clear)
                    .border(Color.red.opacity(0.7), width: 6)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            cameraManager.checkPermissions()
            setupBLECallbacks()
        }
    }

    // MARK: - Shutter Gesture

    private var shutterGesture: AnyGesture<()> {
        switch cameraManager.shootingMode {
        case .bulb:
            // バルブ：長押しで露光開始、離したら撮影
            return AnyGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !cameraManager.isCapturing {
                            cameraManager.startExposure()
                        }
                    }
                    .onEnded { _ in
                        if cameraManager.isCapturing {
                            cameraManager.stopExposureAndCapture()
                        }
                    }
                    .map { _ in () }
            )
        case .timer:
            // タイマー：タップで撮影開始（指定秒数後に自動撮影）
            return AnyGesture(
                TapGesture()
                    .onEnded {
                        if !cameraManager.isCapturing {
                            cameraManager.startTimerCapture()
                        }
                    }
                    .map { _ in () }
            )
        }
    }

    // MARK: - Helpers

    private var shutterHintText: String {
        switch cameraManager.shootingMode {
        case .bulb:
            return cameraManager.isCapturing ? "Release to capture" : "Hold to expose"
        case .timer:
            return cameraManager.isCapturing
                ? "Exposing..."
                : "Tap to shoot (\(formatSeconds(cameraManager.selectedExposureSeconds)))"
        }
    }

    private func formatSeconds(_ s: Double) -> String {
        if s < 1.0 {
            return String(format: "%.1fs", s)
        } else if s == s.rounded() {
            return "\(Int(s))s"
        } else {
            return String(format: "%.1fs", s)
        }
    }

    // MARK: - BLE Callbacks
    private func setupBLECallbacks() {
        bleManager.onButtonPressed = {
            switch cameraManager.shootingMode {
            case .bulb:
                cameraManager.startExposure()
            case .timer:
                cameraManager.startTimerCapture()
            }
        }
        bleManager.onButtonReleased = {
            if cameraManager.shootingMode == .bulb {
                cameraManager.stopExposureAndCapture()
            }
            // タイマーモードではリリースは無視（指定秒数後に自動撮影）
        }
    }

    // MARK: - BLE Status UI
    private var bleStatusColor: Color {
        if cameraManager.isSavingPhoto {
            return .blue
        }
        if cameraManager.isCapturing {
            return .red
        }
        switch bleManager.connectionState {
        case .connected:    return .green
        case .connecting:   return .yellow
        case .scanning:     return .orange
        case .disconnected: return .red
        }
    }

    private var bleStatusText: String {
        if cameraManager.isSavingPhoto {
            return "Saving Photo..."
        }
        if cameraManager.isCapturing {
            switch cameraManager.shootingMode {
            case .bulb:
                return "Bulb Capturing..."
            case .timer:
                return "Timer Capturing..."
            }
        }

        switch bleManager.connectionState {
        case .connected:    return "M5Atom Connected"
        case .connecting:   return "Connecting..."
        case .scanning:     return "BLE Scanning..."
        case .disconnected: return "Disconnected"
        }
    }
}
