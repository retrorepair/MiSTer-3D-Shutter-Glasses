// ESP32 as a Bluetooth HCI controller over the USB serial port ("HCI over UART", H4 framing).
//
//   PC -> ESP32 : H4 command packets   [0x01][opcode lo][opcode hi][len][params...]
//   ESP32 -> PC : H4 event packets     [0x04][event][len][params...]
//
// The ESP32's controller supports the Bluetooth 4.1 connectionless-broadcast and synchronization
// train commands, so tools running on the PC can use it as a 3D display or as 3D glasses.
// After start-up it prints "HCI-BRIDGE READY" once, then only HCI packets flow (921600 baud).
#include <Arduino.h>
#include "esp_bt.h"
#include "esp_system.h"

// Keep the controller's memory instead of letting the Arduino core release it at start-up.
extern "C" bool btInUse() { return true; }

static const size_t RING = 8192;
static uint8_t ring[RING];
static volatile size_t rhead = 0, rtail = 0;
static volatile uint32_t dropped = 0;
static portMUX_TYPE mux = portMUX_INITIALIZER_UNLOCKED;

static void ring_put(const uint8_t *d, uint16_t n) {
    portENTER_CRITICAL(&mux);
    size_t freeb = (rtail + RING - rhead - 1) % RING;
    if (n > freeb) {
        dropped++;
    } else {
        for (uint16_t i = 0; i < n; i++) {
            ring[rhead] = d[i];
            rhead = (rhead + 1) % RING;
        }
    }
    portEXIT_CRITICAL(&mux);
}

static void host_send_available(void) {}
static int host_recv(uint8_t *data, uint16_t len) {     // controller -> host (includes the H4 type byte)
    ring_put(data, len);
    return 0;
}
static esp_vhci_host_callback_t vhci_cb = { host_send_available, host_recv };

static uint8_t cmd_buf[262];
static int cmd_len = 0, cmd_need = 0;

void setup() {
    Serial.setRxBufferSize(2048);
    Serial.begin(921600);
    esp_bt_controller_config_t cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    esp_bt_controller_init(&cfg);
    esp_bt_controller_enable(ESP_BT_MODE_BTDM);
    esp_vhci_host_register_callback(&vhci_cb);
    delay(200);
    Serial.printf("\nHCI-BRIDGE READY reset=%d\n", (int)esp_reset_reason());
    Serial.flush();
}

void loop() {
    // PC -> controller
    while (Serial.available()) {
        uint8_t b = Serial.read();
        if (cmd_len == 0 && b != 0x01) continue;         // wait for a command packet start
        cmd_buf[cmd_len++] = b;
        if (cmd_len == 4) cmd_need = 4 + cmd_buf[3];
        if (cmd_len >= 4 && cmd_len == cmd_need) {
            uint32_t t0 = millis();
            while (!esp_vhci_host_check_send_available() && millis() - t0 < 500) delay(1);
            esp_vhci_host_send_packet(cmd_buf, cmd_len);
            cmd_len = 0;
        }
        if (cmd_len >= (int)sizeof(cmd_buf)) cmd_len = 0;
    }

    // controller -> PC
    uint8_t tmp[256];
    size_t n = 0;
    portENTER_CRITICAL(&mux);
    while (rtail != rhead && n < sizeof(tmp)) {
        tmp[n++] = ring[rtail];
        rtail = (rtail + 1) % RING;
    }
    portEXIT_CRITICAL(&mux);
    if (n) Serial.write(tmp, n);
    else delay(1);
}
