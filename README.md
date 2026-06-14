# EasyLongCamera

EasyLongCamera is a long exposure camera application for iPhone, paired with an M5Atom Lite acting as a custom BLE remote shutter.

## Features

- **Bulb Mode**: Press and hold the button on the M5Atom Lite (or the on-screen button) to start the exposure. Release to stop and capture. Ideal for capturing the exact moment a phenomenon begins and ends.
- **Timer Mode**: Select a preset exposure time (0.5s / 1s / 2s / 4s / 8s / 15s / 30s) and press the button once to start. The app automatically captures after the specified duration. Ideal for consistent, repeatable shots.
- **Custom GATT Service**: Uses a custom BLE GATT service to accurately detect both "button pressed" and "button released" events, overcoming the limitations of standard BLE HID keyboards.
- **Visual Feedback**: The iPhone app displays the elapsed exposure time in real-time, and the M5Atom Lite's LED changes color based on connection and button states.

## Project Structure

- `/iOS/` : Swift source code for the iPhone camera app using SwiftUI, AVFoundation, and CoreBluetooth.
- `/M5AtomLite/` : Arduino sketch for the M5Atom Lite BLE remote shutter.

## Hardware Requirements

- **iPhone**: iOS 15.0 or later.
- **M5Atom Lite**: ESP32-based microcontroller.

## Shooting Modes

| Mode | How to Shoot | Best For |
|---|---|---|
| **Bulb** | Hold button → Release to capture | Capturing phenomena with unknown duration |
| **Timer** | Select duration → Tap once to shoot | Consistent, repeatable long exposures |

## Setup Instructions

### 1. M5Atom Lite (Remote Shutter)

1. Open `/M5AtomLite/M5AtomLite.ino` in the Arduino IDE.
2. Install the required library:
   - `M5Atom`
3. Select `M5Atom` as the board and upload the sketch.
4. **LED Status Guide**:
   - 🔴 Red: Disconnected / Advertising
   - 🟢 Green: Connected to iPhone (standby)
   - 🔵 Blue: Button is being pressed (Exposure active)

### 2. iPhone App

1. Open `/iOS/EasyLongCamera/EasyLongCamera.xcodeproj` in Xcode.
2. Select your iPhone as the build target.
3. Add the following keys to your `Info.plist` to request necessary permissions:
   - `NSCameraUsageDescription` : "Used to capture long exposure photos."
   - `NSPhotoLibraryAddUsageDescription` : "Used to save captured photos to your library."
   - `NSBluetoothAlwaysUsageDescription` : "Used to connect to the M5Atom Lite remote shutter."
4. Build and run the app on your iPhone.
5. The app will automatically scan and connect to the "M5Atom Shutter" device. No manual pairing in iOS Settings is required.

## How it Works

1. **BLE Connection**: The iOS app uses `CoreBluetooth` to scan for the custom Service UUID. Once found, it connects and subscribes to notifications on the Characteristic.
2. **Event Detection**: The M5Atom Lite sends `0x01` on button press and `0x00` on button release.
3. **Bulb Mode**: On `0x01` (Press), the app starts a timer. On `0x00` (Release), the app captures with the measured duration as the exposure time.
4. **Timer Mode**: On `0x01` (Press), the app starts a countdown. After the selected duration, the app automatically captures the photo.

## License

This project is open-source and available under the MIT License.
