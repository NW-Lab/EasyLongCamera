import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    
    var body: some View {
        ZStack {
            // カメラプレビュー
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                // コントロールパネル
                VStack(spacing: 20) {
                    // 露光時間表示
                    Text(String(format: "Exposure: %.1f sec", cameraManager.exposureDuration))
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    
                    // 露光時間スライダー
                    Slider(value: $cameraManager.exposureDuration, in: 0.1...30.0, step: 0.1)
                        .padding(.horizontal, 40)
                        .accentColor(.yellow)
                    
                    // シャッターボタン（画面上のタップでも撮影可能）
                    Button(action: {
                        cameraManager.takePhoto()
                    }) {
                        Circle()
                            .fill(cameraManager.isCapturing ? Color.gray : Color.white)
                            .frame(width: 70, height: 70)
                            .overlay(
                                Circle()
                                    .stroke(Color.black, lineWidth: 2)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 80, height: 80)
                            )
                    }
                    .disabled(cameraManager.isCapturing)
                    .padding(.bottom, 30)
                }
                .padding(.bottom, 20)
            }
            
            // 撮影中のインジケーター
            if cameraManager.isCapturing {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(2.0)
                    Text("Capturing...")
                        .foregroundColor(.white)
                        .padding(.top, 20)
                }
            }
        }
        .onAppear {
            cameraManager.checkPermissions()
        }
    }
}
