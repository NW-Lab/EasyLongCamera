import AVFoundation
import Photos

/// 撮影モード
enum ShootingMode {
    case bulb    // バルブ：押している間だけ露光
    case timer   // タイマー：指定した秒数で露光
}

class CameraManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var session = AVCaptureSession()
    @Published var isCapturing = false
    @Published var elapsedSeconds: Double = 0.0  // 露光中の経過時間表示用

    /// 現在の撮影モード
    @Published var shootingMode: ShootingMode = .bulb

    /// タイマーモード用：選択された露光時間（秒）
    @Published var selectedExposureSeconds: Double = 1.0

    // MARK: - Private Properties
    private var device: AVCaptureDevice?
    private var photoOutput = AVCapturePhotoOutput()

    // バルブ撮影用タイマー
    private var exposureTimer: Timer?
    private var exposureStartTime: Date?

    // タイマーモード用カウントダウンタイマー
    private var countdownTimer: Timer?

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

    // MARK: - Bulb Mode

    /// バルブ：ボタンが押された → 露光開始
    func startExposure() {
        guard !isCapturing else { return }
        DispatchQueue.main.async {
            self.isCapturing = true
            self.elapsedSeconds = 0.0
            self.exposureStartTime = Date()
        }
        exposureTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.exposureStartTime else { return }
            DispatchQueue.main.async {
                self.elapsedSeconds = Date().timeIntervalSince(start)
            }
        }
        print("CameraManager: [Bulb] Exposure started")
    }

    /// バルブ：ボタンが離された → 露光時間確定して撮影
    func stopExposureAndCapture() {
        guard isCapturing, let startTime = exposureStartTime else { return }
        exposureTimer?.invalidate()
        exposureTimer = nil
        let duration = max(Date().timeIntervalSince(startTime), 0.1)
        print("CameraManager: [Bulb] Exposure stopped. Duration = \(String(format: "%.2f", duration))s")
        captureWithExposure(seconds: duration)
    }

    // MARK: - Timer Mode

    /// タイマー：ボタンを押したら指定秒数で撮影開始
    func startTimerCapture() {
        guard !isCapturing else { return }
        DispatchQueue.main.async {
            self.isCapturing = true
            self.elapsedSeconds = 0.0
        }
        let target = selectedExposureSeconds
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.elapsedSeconds += 0.1
                if self.elapsedSeconds >= target {
                    self.countdownTimer?.invalidate()
                    self.countdownTimer = nil
                    self.captureWithExposure(seconds: target)
                }
            }
        }
        print("CameraManager: [Timer] Capture started. Target = \(target)s")
    }

    // MARK: - Common Capture

    private func captureWithExposure(seconds: Double) {
        guard let device = device else {
            DispatchQueue.main.async { self.isCapturing = false }
            return
        }

        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.custom) {
                let requested = CMTime(seconds: seconds, preferredTimescale: 1000)
                let minDur = device.activeFormat.minExposureDuration
                let maxDur = device.activeFormat.maxExposureDuration
                let clamped = min(max(requested, minDur), maxDur)
                let iso = device.activeFormat.minISO

                device.setExposureModeCustom(duration: clamped, iso: iso) { [weak self] _ in
                    guard let self = self else { return }
                    let settings = AVCapturePhotoSettings()
                    settings.photoQualityPrioritization = .quality
                    self.photoOutput.capturePhoto(with: settings, delegate: self)
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
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: data, options: nil)
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
