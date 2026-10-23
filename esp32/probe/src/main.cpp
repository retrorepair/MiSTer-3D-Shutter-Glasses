// Probe the ESP32's Bluetooth controller over raw HCI (VHCI): which commands/features does it have?
// Mainly: can it receive a synchronization train / connectionless broadcast (needed to act as 3D glasses)
// or send them (needed to act as a 3D display)?
#include <Arduino.h>
#include "esp_bt.h"

// Keep the controller's memory instead of letting the Arduino core release it at start-up.
extern "C" bool btInUse() { return true; }

static volatile bool rx_ready = false;
static uint8_t rx_buf[320];
static volatile uint16_t rx_len = 0;

static void host_send_available(void) {}
static int host_recv(uint8_t *data, uint16_t len) {
    if (len > sizeof(rx_buf)) len = sizeof(rx_buf);
    memcpy(rx_buf, data, len);
    rx_len = len;
    rx_ready = true;
    return 0;
}
static esp_vhci_host_callback_t vhci_cb = { host_send_available, host_recv };

// Send an HCI command and wait for its Command Complete / Command Status.
// Returns the status byte (>= 0), -1 on timeout, -2 if the controller would not accept the packet.
// 'ret' receives the return parameters (status first) of a Command Complete.
static int hci_cmd(uint16_t opcode, const uint8_t *params, uint8_t plen, uint8_t *ret = nullptr, uint16_t *retlen = nullptr,
                   uint32_t timeout_ms = 800) {
    uint8_t pkt[260];
    pkt[0] = 1;
    pkt[1] = opcode & 0xFF;
    pkt[2] = opcode >> 8;
    pkt[3] = plen;
    if (plen) memcpy(pkt + 4, params, plen);
    uint32_t t0 = millis();
    while (!esp_vhci_host_check_send_available()) {
        if (millis() - t0 > 300) return -2;
        delay(1);
    }
    rx_ready = false;
    esp_vhci_host_send_packet(pkt, 4 + plen);
    while (millis() - t0 < timeout_ms) {
        if (rx_ready) {
            rx_ready = false;
            if (rx_buf[0] == 4) {
                uint8_t ev = rx_buf[1];
                if (ev == 0x0E && rx_len >= 7 && (rx_buf[4] | (rx_buf[5] << 8)) == opcode) {
                    uint16_t n = rx_buf[2] - 3;
                    if (ret) memcpy(ret, rx_buf + 6, n);
                    if (retlen) *retlen = n;
                    return rx_buf[6];
                }
                if (ev == 0x0F && rx_len >= 7 && (rx_buf[5] | (rx_buf[6] << 8)) == opcode) {
                    if (retlen) *retlen = 0;
                    return rx_buf[3];
                }
            }
        }
        delay(1);
    }
    return -1;
}

static void hexdump(const uint8_t *d, int n) {
    for (int i = 0; i < n; i++) Serial.printf("%02X ", d[i]);
    Serial.println();
}

static bool cmd_bit(const uint8_t *cmds, int octet, int bit) { return cmds[octet] & (1 << bit); }

static void report(const char *name, int octet, int bit, const uint8_t *cmds) {
    Serial.printf("  %-44s octet %2d bit %d : %s\n", name, octet, bit, cmd_bit(cmds, octet, bit) ? "SUPPORTED" : "no");
}

static void probe() {
    uint8_t ret[300];
    uint16_t rl;
    Serial.println("\n==== ESP32 Bluetooth controller probe ====");

    int st = hci_cmd(0x0C03, nullptr, 0);                    // Reset
    Serial.printf("HCI_Reset                         status %d\n", st);

    st = hci_cmd(0x1001, nullptr, 0, ret, &rl);              // Read_Local_Version_Information
    if (st == 0)
        Serial.printf("HCI version %d rev 0x%04X, LMP version %d, manufacturer 0x%04X (%s), LMP subversion 0x%04X\n", ret[1],
                      ret[2] | (ret[3] << 8), ret[4], ret[5] | (ret[6] << 8), (ret[5] | (ret[6] << 8)) == 0x0060 ? "Espressif" : "?",
                      ret[7] | (ret[8] << 8));

    uint8_t cmds[64] = {0};
    st = hci_cmd(0x1002, nullptr, 0, ret, &rl);              // Read_Local_Supported_Commands
    if (st == 0 && rl >= 65) {
        memcpy(cmds, ret + 1, 64);
        Serial.print("supported commands (octets 0..63): ");
        hexdump(cmds, 64);
        report("Set Connectionless Slave Broadcast (3D display)", 31, 0, cmds);
        report("Set CSB Receive (3D glasses)", 31, 1, cmds);
        report("Start Synchronization Train (3D display)", 31, 2, cmds);
        report("Receive Synchronization Train (3D glasses)", 31, 3, cmds);
        report("Set Reserved LT_ADDR", 31, 4, cmds);
        report("Delete Reserved LT_ADDR", 31, 5, cmds);
        report("Set CSB Data", 31, 6, cmds);
        report("Read Synchronization Train Parameters", 31, 7, cmds);
        report("Write Synchronization Train Parameters", 32, 0, cmds);
        report("Set Triggered Clock Capture", 30, 5, cmds);
    } else {
        Serial.printf("Read_Local_Supported_Commands failed (status %d)\n", st);
    }

    for (uint8_t page = 0; page < 3; page++) {               // Read_Local_Extended_Features
        st = hci_cmd(0x1004, &page, 1, ret, &rl);
        if (st == 0 && rl >= 11) {
            Serial.printf("LMP features page %d (max page %d): ", ret[1], ret[2]);
            hexdump(ret + 3, 8);
            if (page == 2)
                Serial.printf("  page 2 bits: CSB master %d, CSB slave %d, sync train %d, sync scan %d\n", ret[3] & 1, (ret[3] >> 1) & 1,
                              (ret[3] >> 2) & 1, (ret[3] >> 3) & 1);
        } else {
            Serial.printf("LMP features page %d: status %d\n", page, st);
        }
    }

    // direct tests of the commands that matter
    st = hci_cmd(0x0C77, nullptr, 0, ret, &rl);
    Serial.printf("Read_Synchronization_Train_Parameters      -> status %d (0 = implemented, 1 = unknown command)\n", st);
    uint8_t rx_train[12] = {0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x00, 0x01, 0xA6, 0x00, 0xC0, 0x00};   // dummy BD_ADDR, short scan
    st = hci_cmd(0x0444, rx_train, sizeof(rx_train));
    Serial.printf("Receive_Synchronization_Train (dummy peer) -> status %d (0 = accepted, 1 = unknown command)\n", st);
    uint8_t lt = 1;
    st = hci_cmd(0x0C74, &lt, 1, ret, &rl);
    Serial.printf("Set_Reserved_LT_ADDR 1                     -> status %d\n", st);
    Serial.println("==== done ====");
}

void setup() {
    Serial.begin(115200);
    delay(1500);
    esp_bt_controller_config_t cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    esp_err_t e = esp_bt_controller_init(&cfg);
    Serial.printf("\nesp_bt_controller_init -> %d\n", e);
    e = esp_bt_controller_enable(ESP_BT_MODE_BTDM);
    Serial.printf("esp_bt_controller_enable(BTDM) -> %d\n", e);
    esp_vhci_host_register_callback(&vhci_cb);
    probe();
}

void loop() {
    // run again whenever a character arrives on the serial port
    if (Serial.available()) {
        while (Serial.available()) Serial.read();
        probe();
    }
    delay(20);
}
