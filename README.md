# EasyLongCamera

EasyLongCamera is a long exposure camera application for iPhone, paired with an M5Atom Lite acting as a BLE (Bluetooth Low Energy) remote shutter.

## Features

- **Long Exposure Control**: Adjust exposure duration from 0.1 to 30.0 seconds (subject to iPhone hardware limits) using the AVFoundation custom exposure API.
- **BLE Remote Shutter**: Use an M5Atom Lite as a wireless remote shutter button.
- **No Extra Apps Needed for Remote**: The M5Atom Lite acts as a standard BLE HID keyboard and triggers the shutter by sending the `Volume Up` command.

## Project Structure

- `/iOS/` : Swift source code for the iPhone camera app using SwiftUI and AVFoundation.
- `/M5AtomLite/` : Arduino sketch for the M5Atom Lite BLE remote shutter.

## Hardware Requirements

- **iPhone**: iOS 15.0 or later (for SwiftUI and AVFoundation support).
- **M5Atom Lite**: ESP32-based microcontroller.

## Setup Instructions

### 1. M5Atom Lite (Remote Shutter)

1. Open `/M5AtomLite/M5AtomLite.ino` in the Arduino IDE.
2. Install the required libraries:
   - `M5Atom`
   - `ESP32 BLE Keyboard` (by T-vK)
3. Select `M5Atom` as the board and upload the sketch.
4. On your iPhone, go to **Settings > Bluetooth** and pair with the device named **"M5Atom Shutter"**.

### 2. iPhone App

1. Open `/iOS/EasyLongCamera/EasyLongCamera.xcodeproj` in Xcode.
2. Select your iPhone as the build target.
3. Make sure to set up your Apple Developer signing certificate.
4. Add the following keys to your `Info.plist` to request necessary permissions:
   - `NSCameraUsageDescription` : "Used to capture long exposure photos."
   - `NSPhotoLibraryAddUsageDescription` : "Used to save captured photos to your library."
5. Build and run the app on your iPhone.

## How it Works

1. **Exposure Control**: The iOS app uses `AVCaptureDevice.setExposureModeCustom` to lock the ISO and set a specific exposure duration.
2. **Shutter Trigger**: The iOS app listens for system volume changes using `AVAudioSession.observe(\.outputVolume)`. When the M5Atom Lite sends a `Volume Up` HID command, the system volume changes, triggering the `takePhoto()` function in the app.

## License

This project is open-source and available under the MIT License.
