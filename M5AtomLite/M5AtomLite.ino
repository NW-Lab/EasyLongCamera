#include <M5Atom.h>
#include <BleKeyboard.h>

// BLE Keyboardインスタンスの作成
// 第1引数: デバイス名, 第2引数: メーカー名, 第3引数: バッテリー残量
BleKeyboard bleKeyboard("M5Atom Shutter", "M5Stack", 100);

// ボタンの状態管理用
bool isPressed = false;

void setup() {
  // M5Atomの初期化 (シリアル, I2C, LED)
  M5.begin(true, false, true);
  
  // LEDを初期状態(赤: 未接続)にする
  M5.dis.drawpix(0, 0xff0000); 

  Serial.println("Starting BLE work!");
  bleKeyboard.begin();
}

void loop() {
  // ボタン状態の更新
  M5.update();

  if (bleKeyboard.isConnected()) {
    // 接続時はLEDを緑に
    M5.dis.drawpix(0, 0x00ff00);

    // M5Atom本体のボタン(前面全体)が押された時
    if (M5.Btn.wasPressed()) {
      Serial.println("Button Pressed - Sending Volume Up");
      // シャッターを切るためにVolume Upキーを送信
      bleKeyboard.write(KEY_MEDIA_VOLUME_UP);
      // 青く光らせてフィードバック
      M5.dis.drawpix(0, 0x0000ff);
      delay(100); // チャタリング防止とLED点灯時間
      M5.dis.drawpix(0, 0x00ff00); // 緑に戻す
    }
  } else {
    // 未接続時はLEDを赤に
    M5.dis.drawpix(0, 0xff0000);
  }

  delay(50);
}
