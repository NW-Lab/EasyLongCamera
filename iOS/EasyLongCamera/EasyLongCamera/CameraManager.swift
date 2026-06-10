import AVFoundation
import Photos
import Combine

class CameraManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var session = AVCaptureSession()
    @Published var isCapturing = false
    @Published var elapsedSeconds: Double = 0.0  // 露光中の経過時間表示用

    // MARK: - Private Properties
    private var device: AVCaptureDevice?
    private var photoOutput = AVCapturePhotoOutput()

    // バルブ撮影用タイマー
    private var exposureTimer: Timer?
    private var exposureStartTime: Date?

    // MARK: - Setup
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.setupCamera() }
                }
            }
        default:
            break
        }
    }

    private func setupCamera() {
        session.beginConfiguration()

        guard let videoDevice = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) else { return }
        self.device = videoDevice

        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        if session.canAddInput(videoInput) { session.addInput(videoInput) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

        session.commitConfiguration()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    // MARK: - Bulb Exposure Control

    /// BLEボタンが押された → 露光開始
    func startExposure() {
        guard !isCapturing else { return }

        DispatchQueue.main.async {
            self.isCapturing = true
            self.elapsedSeconds = 0.0
            self.exposureStartTime = Date()
        }

        // 経過時間を0.1秒ごとに更新するタイマー
        exposureTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.exposureStartTime else { return }
            DispatchQueue.main.async {
                self.elapsedSeconds = Date().timeIntervalSince(start)
            }
        }

        print("CameraManager: Exposure started")
    }

    /// BLEボタンが離された → 露光時間確定して撮影
    func stopExposureAndCapture() {
        guard isCapturing, let startTime = exposureStartTime else { return }

        exposureTimer?.invalidate()
        exposureTimer = nil

        let duration = Date().timeIntervalSince(startTime)
        print("CameraManager: Exposure stopped. Duration = \(String(format: "%.2f", duration))s")

        // 最低0.1秒は確保する
        let clampedDuration = max(duration, 0.1)
        captureWithExposure(seconds: clampedDuration)
    }

    private func captureWithExposure(seconds: Double) {
        guard let device = device else {
            DispatchQueue.main.async { self.isCapturing = false }
            return
        }

        do {
            try device.lockForConfiguration()

            if device.isExposureModeSupported(.custom) {
                let requestedDuration = CMTime(seconds: seconds, preferredTimescale: 1000)
                // デバイスの許容範囲内に収める
                let minDuration = device.activeFormat.minExposureDuration
                let maxDuration = device.activeFormat.maxExposureDuration
                let clampedDuration = min(max(requestedDuration, minDuration), maxDuration)

                // ISO最小値（ノイズ低減）
                let iso = device.activeFormat.minISO

                device.setExposureModeCustom(duration: clampedDuration, iso: iso) { [weak self] _ in
                    // 露光設定完了後に撮影
                    let settings = AVCapturePhotoSettings()
                    settings.photoQualityPrioritization = .quality
                    self?.photoOutput.capturePhoto(with: settings, delegate: self!)
                }
            }

            device.unlockForConfiguration()
        } catch {
            print("CameraManager: Error locking configuration: \(error)")
            DispatchQueue.main.async { self.isCapturing = false }
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        DispatchQueue.main.async {
            self.isCapturing = false
            self.elapsedSeconds = 0.0
        }

        guard let data = photo.fileDataRepresentation() else { return }

        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else { return }
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: data, options: nil)
            }) { success, error in
                if success {
                    print("CameraManager: Photo saved to library")
                } else if let error = error {
                    print("CameraManager: Error saving photo: \(error)")
                }
            }
        }
    }
}
