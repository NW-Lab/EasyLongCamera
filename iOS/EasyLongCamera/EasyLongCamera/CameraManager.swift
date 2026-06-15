import AVFoundation
import CoreImage
import Photos
import UIKit

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
    @Published var isSavingPhoto = false
    @Published var captureNotice: String?

    /// 現在の撮影モード
    @Published var shootingMode: ShootingMode = .bulb

    /// タイマーモード用：選択された露光時間（秒）
    @Published var selectedExposureSeconds: Double = 1.0

    // MARK: - Private Properties
    private var device: AVCaptureDevice?
    private var photoOutput = AVCapturePhotoOutput()
    private var videoDataOutput = AVCaptureVideoDataOutput()

    // バルブ撮影用タイマー
    private var exposureTimer: Timer?
    private var exposureStartTime: Date?

    // 露光中の経過表示用タイマー
    private var progressTimer: Timer?

    // Bulb積算処理用
    private let videoOutputQueue = DispatchQueue(label: "camera.video.output.queue")
    private let stackQueue = DispatchQueue(label: "camera.bulb.stack.queue")
    private let ciContext = CIContext()
    private var bulbIsAccumulating = false
    private var bulbCompositeImage: CIImage?
    private var bulbFrameCount = 0
    private var bulbExtent: CGRect = .zero

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
        session.sessionPreset = .photo

        guard let videoDevice = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) else { return }
        self.device = videoDevice

        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        if session.canAddInput(videoInput) { session.addInput(videoInput) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            videoDataOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
            if let conn = videoDataOutput.connection(with: .video), conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
        }

        session.commitConfiguration()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    // MARK: - Bulb Mode

    /// バルブ：ボタンが押された → 露光開始
    func startExposure() {
        guard !isCapturing else { return }
        stackQueue.async {
            self.bulbIsAccumulating = true
            self.bulbCompositeImage = nil
            self.bulbFrameCount = 0
            self.bulbExtent = .zero
        }
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

    /// バルブ：ボタンが離された → 押下中に積算した画像を書き出し
    func stopExposureAndCapture() {
        guard isCapturing else { return }
        exposureTimer?.invalidate()
        exposureTimer = nil
        let duration = max(Date().timeIntervalSince(exposureStartTime ?? Date()), 0.1)
        print("CameraManager: [Bulb] Exposure stopped. Duration = \(String(format: "%.2f", duration))s")

        stackQueue.async {
            self.bulbIsAccumulating = false
            let frameCount = self.bulbFrameCount
            let composite = self.bulbCompositeImage
            let extent = self.bulbExtent

            self.bulbCompositeImage = nil
            self.bulbFrameCount = 0
            self.bulbExtent = .zero

            guard frameCount > 0, let composite, !extent.isEmpty else {
                DispatchQueue.main.async {
                    self.isCapturing = false
                    self.elapsedSeconds = 0.0
                    self.exposureStartTime = nil
                }
                self.postCaptureNotice("No image captured")
                print("CameraManager: [Bulb] No accumulated frames to save")
                return
            }

            let output = composite.cropped(to: extent)
            guard let cgImage = self.ciContext.createCGImage(output, from: extent) else {
                DispatchQueue.main.async {
                    self.isCapturing = false
                    self.elapsedSeconds = 0.0
                    self.exposureStartTime = nil
                }
                self.postCaptureNotice("Failed to render image")
                print("CameraManager: [Bulb] Failed to render accumulated image")
                return
            }

            guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.95) else {
                DispatchQueue.main.async {
                    self.isCapturing = false
                    self.elapsedSeconds = 0.0
                    self.exposureStartTime = nil
                }
                self.postCaptureNotice("Failed to encode image")
                print("CameraManager: [Bulb] Failed to encode JPEG")
                return
            }

            DispatchQueue.main.async {
                self.isSavingPhoto = true
            }
            self.savePhotoData(data) { success in
                DispatchQueue.main.async {
                    self.isSavingPhoto = false
                    self.isCapturing = false
                    self.elapsedSeconds = 0.0
                    self.exposureStartTime = nil
                }
                self.postCaptureNotice(success ? "Saved" : "Save failed")
            }
            print("CameraManager: [Bulb] Saved stacked image with \(frameCount) frames")
        }
    }

    // MARK: - Timer Mode

    /// タイマー：ボタン押下直後に露光を開始し、指定秒数で撮影完了
    func startTimerCapture() {
        guard !isCapturing else { return }
        DispatchQueue.main.async {
            self.isCapturing = true
            self.elapsedSeconds = 0.0
            self.exposureStartTime = Date()
        }
        let target = selectedExposureSeconds
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let start = self.exposureStartTime {
                    self.elapsedSeconds = min(Date().timeIntervalSince(start), target)
                }
                if self.elapsedSeconds >= target {
                    self.progressTimer?.invalidate()
                    self.progressTimer = nil
                }
            }
        }
        // 押下時点で即座に露光付き撮影を開始
        captureWithExposure(seconds: target)
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
                    // Respect device/output capability to avoid runtime exception.
                    settings.photoQualityPrioritization = self.photoOutput.maxPhotoQualityPrioritization
                    self.photoOutput.capturePhoto(with: settings, delegate: self)
                }
            }
            device.unlockForConfiguration()
        } catch {
            print("CameraManager: Error locking configuration: \(error)")
            DispatchQueue.main.async { self.isCapturing = false }
        }
    }

    private func savePhotoData(_ data: Data, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            guard status == .authorized || status == .limited else {
                print("CameraManager: Photo library access denied")
                completion(false)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: data, options: nil)
            }) { success, error in
                if success {
                    print("CameraManager: Photo saved to library")
                } else if let error = error {
                    print("CameraManager: Error saving photo: \(error)")
                }
                completion(success)
            }
        }
    }

    private func postCaptureNotice(_ message: String) {
        DispatchQueue.main.async {
            self.captureNotice = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                guard let self = self, self.captureNotice == message else { return }
                self.captureNotice = nil
            }
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        self.exposureTimer?.invalidate()
        self.exposureTimer = nil
        self.progressTimer?.invalidate()
        self.progressTimer = nil

        guard error == nil else {
            DispatchQueue.main.async {
                self.isCapturing = false
                self.elapsedSeconds = 0.0
                self.exposureStartTime = nil
                self.isSavingPhoto = false
            }
            postCaptureNotice("Capture failed")
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                self.isCapturing = false
                self.elapsedSeconds = 0.0
                self.exposureStartTime = nil
                self.isSavingPhoto = false
            }
            postCaptureNotice("Capture failed")
            return
        }

        DispatchQueue.main.async {
            self.isSavingPhoto = true
        }
        savePhotoData(data) { success in
            DispatchQueue.main.async {
                self.isSavingPhoto = false
                self.isCapturing = false
                self.elapsedSeconds = 0.0
                self.exposureStartTime = nil
            }
            self.postCaptureNotice(success ? "Saved" : "Save failed")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard shootingMode == .bulb else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let frameImage = CIImage(cvPixelBuffer: pixelBuffer)
        stackQueue.async {
            guard self.bulbIsAccumulating else { return }

            if self.bulbFrameCount == 0 {
                self.bulbCompositeImage = frameImage
                self.bulbExtent = frameImage.extent
            } else if let current = self.bulbCompositeImage {
                // Maximum compositing preserves bright trails from moving light sources.
                self.bulbCompositeImage = frameImage.applyingFilter(
                    "CIMaximumCompositing",
                    parameters: [kCIInputBackgroundImageKey: current]
                )
            }

            self.bulbFrameCount += 1
        }
    }
}
