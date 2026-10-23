#!/bin/sh
# Start the Bluetooth 3D glasses emitter in the background (MiSTer Scripts menu).
# Needs the ESP32 HCI bridge plugged into a MiSTer USB port and the SMS 3D core with
# OSD > 3D Glasses > USB sync output: On and Glasses sync clock +2.2%: On.  Log: /tmp/3d_glasses.log
DIR=/media/fat/Scripts/3d_glasses

for p in $(ps | grep -E "mister_bt3d" | grep -v grep | awk '{print $1}'); do kill "$p" 2>/dev/null; done
sleep 1

cd "$DIR" || { echo "missing $DIR"; exit 1; }
rm -f /tmp/3d_ctl                    # settings left over from an experiment
found=0
for d in /dev/ttyUSB* /dev/ttyACM*; do
    [ -e "$d" ] && found=1
done
if [ "$found" = 0 ]; then
    echo "No ESP32 found on a USB port (expected /dev/ttyUSB0)."
    exit 1
fi
nohup python3 mister_bt3d.py > /tmp/3d_glasses.log 2>&1 < /dev/null &
sleep 3
echo "3D glasses emitter started (log: /tmp/3d_glasses.log)"
tail -n 3 /tmp/3d_glasses.log
