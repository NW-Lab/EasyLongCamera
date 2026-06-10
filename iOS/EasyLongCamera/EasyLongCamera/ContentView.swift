import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var bleManager = BLEManager()

    var body: some View {
        ZStack {
            // カメラプレビュー
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()

            VStack {
                // BLE接続状態インジケーター（上部）
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

                Spacer()

                // 露光中の経過時間表示
                if cameraManager.isCapturing {
                    Text(String(format: "%.1f s", cameraManager.elapsedSeconds))
                        .font(.system(size: 60, weight: .thin, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 4)
                        .padding(.bottom, 20)
                }

                // 画面タップ用シャッターボタン（BLEリモコンの代替）
                VStack(spacing: 8) {
                    Text(cameraManager.isCapturing ? "Release to capture" : "Hold to expose")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))

                    Circle()
                        .fill(cameraManager.isCapturing ? Color.red.opacity(0.8) : Color.white.opacity(0.9))
                        .frame(width: 70, height: 70)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 80, height: 80)
                        )
                        .scaleEffect(cameraManager.isCapturing ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: cameraManager.isCapturing)
                        // 長押しジェスチャー（画面操作でも使えるように）
                        .gesture(
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
                        )
                }
                .padding(.bottom, 50)
            }

            // 露光中のオーバーレイ（画面周囲を赤く）
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

    // MARK: - BLE Callbacks
    private func setupBLECallbacks() {
        bleManager.onButtonPressed = {
            cameraManager.startExposure()
        }
        bleManager.onButtonReleased = {
            cameraManager.stopExposureAndCapture()
        }
    }

    // MARK: - BLE Status UI
    private var bleStatusColor: Color {
        switch bleManager.connectionState {
        case .connected:    return .green
        case .connecting:   return .yellow
        case .scanning:     return .orange
        case .disconnected: return .red
        }
    }

    private var bleStatusText: String {
        switch bleManager.connectionState {
        case .connected:    return "M5Atom Connected"
        case .connecting:   return "Connecting..."
        case .scanning:     return "Scanning..."
        case .disconnected: return "Disconnected"
        }
    }
}
