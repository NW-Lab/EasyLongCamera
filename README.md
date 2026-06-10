# EasyLongCamera

EasyLongCamera is a "Bulb mode" (long exposure) camera application for iPhone, paired with an M5Atom Lite acting as a custom BLE remote shutter.

## Features

- **True Bulb Mode Experience**: Press and hold the button on the M5Atom Lite to start the exposure. Release the button to stop the exposure and capture the photo.
- **Custom GATT Service**: Uses a custom BLE GATT service to accurately detect both "button pressed" and "button released" events, overcoming the limitations of standard BLE HID keyboards.
- **Visual Feedback**: The iPhone app displays the elapsed exposure time in real-time, and the M5Atom Lite's LED changes color based on connection and button states.

## Project Structure

- `/iOS/` : Swift source code for the iPhone camera app using SwiftUI, AVFoundation, and CoreBluetooth.
- `/M5AtomLite/` : Arduino sketch for the M5Atom Lite BLE remote shutter.

## Hardware Requirements

- **iPhone**: iOS 15.0 or later (for SwiftUI and AVFoundation support).
- **M5Atom Lite**: ESP32-based microcontroller.

## Setup Instructions

### 1. M5Atom Lite (Remote Shutter)

1. Open `/M5AtomLite/M5AtomLite.ino` in the Arduino IDE.
2. Install the required library:
   - `M5Atom`
3. Select `M5Atom` as the board and upload the sketch.
4. **LED Status Guide**:
   - 🔴 Red: Disconnected / Advertising
   - 🟢 Green: Connected to iPhone
   - 🔵 Blue: Button is being pressed (Exposure active)

### 2. iPhone App

1. Open `/iOS/EasyLongCamera/EasyLongCamera.xcodeproj` in Xcode.
2. Select your iPhone as the build target.
3. Add the following keys to your `Info.plist` to request necessary permissions:
   - `NSCameraUsageDescription` : "Used to capture long exposure photos."
   - `NSPhotoLibraryAddUsageDescription` : "Used to save captured photos to your library."
   - `NSBluetoothAlwaysUsageDescription` : "Used to connect to the M5Atom Lite remote shutter."
4. Build and run the app on your iPhone.
5. The app will automatically scan and connect to the "M5Atom Shutter" device. No manual pairing in iOS Settings is required!

## How it Works

1. **BLE Connection**: The iOS app uses `CoreBluetooth` to scan for a specific Service UUID (`12345678-1234-1234-1234-123456789012`). Once found, it connects and subscribes to notifications on the Characteristic UUID.
2. **Event Detection**: The M5Atom Lite sends a notification with value `0x01` when the button is pressed, and `0x00` when released.
3. **Exposure Control**: 
   - On `0x01` (Press): The app starts a timer and updates the UI.
   - On `0x00` (Release): The app stops the timer, calculates the exact duration the button was held, and uses `AVCaptureDevice.setExposureModeCustom` to capture the photo with that exact exposure time.

## License

This project is open-source and available under the MIT License.
