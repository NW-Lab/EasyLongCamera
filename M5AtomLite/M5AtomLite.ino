#include <M5Atom.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// カスタムGATTサービス・キャラクタリスティックのUUID
#define SERVICE_UUID        "12345678-1234-1234-1234-123456789012"
#define CHARACTERISTIC_UUID "12345678-1234-1234-1234-123456789013"

BLEServer* pServer = nullptr;
BLECharacteristic* pCharacteristic = nullptr;
bool deviceConnected = false;

// LED色の定数
const uint32_t LED_RED   = 0xff0000; // 未接続
const uint32_t LED_GREEN = 0x00ff00; // 接続済み・待機中
const uint32_t LED_BLUE  = 0x0000ff; // 露光中（ボタン押下中）

// 接続・切断コールバック
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    deviceConnected = true;
    M5.dis.drawpix(0, LED_GREEN);
    Serial.println("Client connected");
  }

  void onDisconnect(BLEServer* pServer) override {
    deviceConnected = false;
    M5.dis.drawpix(0, LED_RED);
    Serial.println("Client disconnected - restarting advertising");
    // 切断後に再アドバタイズ開始
    BLEDevice::startAdvertising();
  }
};

void setup() {
  // M5Atomの初期化 (Serial, I2C, LED)
  M5.begin(true, false, true);
  M5.dis.drawpix(0, LED_RED);
  Serial.println("Initializing BLE...");

  // BLEデバイスの初期化
  BLEDevice::init("M5Atom Shutter");

  // BLEサーバーの作成
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  // カスタムGATTサービスの作成
  BLEService* pService = pServer->createService(SERVICE_UUID);

  // キャラクタリスティックの作成（Notify対応）
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  // Notifyに必要なClient Characteristic Configuration Descriptor (CCCD) を追加
  pCharacteristic->addDescriptor(new BLE2902());

  // 初期値（離した状態）
  uint8_t initialValue = 0x00;
  pCharacteristic->setValue(&initialValue, 1);

  // サービス開始
  pService->start();

  // アドバタイズ設定と開始
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.println("BLE advertising started. Device name: M5Atom Shutter");
}

void loop() {
  M5.update();

  if (deviceConnected) {
    // ボタンが押された瞬間
    if (M5.Btn.wasPressed()) {
      Serial.println("Button PRESSED -> Notify 0x01");
      uint8_t val = 0x01;
      pCharacteristic->setValue(&val, 1);
      pCharacteristic->notify();
      M5.dis.drawpix(0, LED_BLUE);
    }

    // ボタンが離された瞬間
    if (M5.Btn.wasReleased()) {
      Serial.println("Button RELEASED -> Notify 0x00");
      uint8_t val = 0x00;
      pCharacteristic->setValue(&val, 1);
      pCharacteristic->notify();
      M5.dis.drawpix(0, LED_GREEN);
    }
  }

  delay(10); // ポーリング間隔（チャタリング防止）
}
