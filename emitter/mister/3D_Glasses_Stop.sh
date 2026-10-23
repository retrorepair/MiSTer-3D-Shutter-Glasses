#!/bin/sh
# Stop the Bluetooth 3D glasses emitter (MiSTer Scripts menu); the ESP32 is reset, so the glasses go clear.
for p in $(ps | grep -E "mister_bt3d" | grep -v grep | awk '{print $1}'); do kill "$p" 2>/dev/null; done
sleep 1
echo "3D glasses emitter stopped"
