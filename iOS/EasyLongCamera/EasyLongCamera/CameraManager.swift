import AVFoundation
import SwiftUI
import Photos
import MediaPlayer

class CameraManager: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var isCapturing = false
    @Published var exposureDuration: Double = 1.0 {
        didSet {
            updateExposure()
        }
    }
    
    private var device: AVCaptureDevice?
    private var photoOutput = AVCapturePhotoOutput()
    private var volumeObservation: NSKeyValueObservation?
    
    override init() {
        super.init()
        setupVolumeListener()
    }
    
    deinit {
        volumeObservation?.invalidate()
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupCamera()
                    }
                }
            }
        default:
            break
        }
    }
    
    private func setupCamera() {
        session.beginConfiguration()
        
        // デバイスの取得
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        self.device = videoDevice
        
        // 入力の設定
        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }
        
        // 出力の設定
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        
        session.commitConfiguration()
        
        // プレビューの開始
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            self?.updateExposure()
        }
    }
    
    private func updateExposure() {
        guard let device = device else { return }
        
        do {
            try device.lockForConfiguration()
            
            // カスタム露光モードに設定
            if device.isExposureModeSupported(.custom) {
                // 露光時間（秒）をCMTimeに変換
                let duration = CMTime(seconds: exposureDuration, preferredTimescale: 1000)
                
                // デバイスの許容範囲内に収める
                let activeDuration = min(max(duration, device.activeFormat.minExposureDuration), device.activeFormat.maxExposureDuration)
                
                // ISOは最小値（ノイズを減らすため）
                let iso = device.activeFormat.minISO
                
                device.setExposureModeCustom(duration: activeDuration, iso: iso, completionHandler: nil)
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Error locking configuration: \(error)")
        }
    }
    
    func takePhoto() {
        guard !isCapturing else { return }
        
        DispatchQueue.main.async {
            self.isCapturing = true
        }
        
        let settings = AVCapturePhotoSettings()
        // 最高画質で撮影
        settings.photoQualityPrioritization = .quality
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    // BLE HIDリモコンからのVolume Upを検知する
    private func setupVolumeListener() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(true)
            volumeObservation = audioSession.observe(\.outputVolume) { [weak self] (session, change) in
                // 音量変更（Volume Up/Down）を検知したらシャッターを切る
                DispatchQueue.main.async {
                    self?.takePhoto()
                }
            }
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        DispatchQueue.main.async {
            self.isCapturing = false
        }
        
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        
        // 写真ライブラリに保存
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, error in
                    if let error = error {
                        print("Error saving photo: \(error)")
                    }
                }
            }
        }
    }
}
