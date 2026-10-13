adb root
adb shell setprop persist.vehicle.hardware.stop.sync.mcu.time 1
time=$(date +"%H%M")
date=$(date +"%m%d%H%Y.%S")
if [ ${time:0:2} -lt 10 ]; then
  time="0${time:1:1}${time:2:2}"
fi

adb shell date ${date:0:4}${time}${date:8:6} set
adb shell date
