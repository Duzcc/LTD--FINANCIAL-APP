#!/bin/zsh -l
# Tải ảnh hệ thống Android 15 (arm64) và tạo máy ảo "Nhom3_Pixel" để chạy thử ứng dụng.
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
SDK=$HOME/Library/Android/sdk
IMG="system-images;android-35;google_apis;arm64-v8a"
yes | $SDK/cmdline-tools/latest/bin/sdkmanager --licenses > /dev/null 2>&1
$SDK/cmdline-tools/latest/bin/sdkmanager --install "$IMG" "emulator" "platform-tools" 2>&1 | tr '\r' '\n' | grep -vE "^\[=*\s*\]|^$" | tail -5
echo no | $SDK/cmdline-tools/latest/bin/avdmanager create avd -n Nhom3_Pixel -k "$IMG" -d pixel_7 --force 2>&1 | tail -2
# RAM/ổ đĩa vừa phải cho máy 16GB
CFG=$HOME/.android/avd/Nhom3_Pixel.avd/config.ini
sed -i '' 's/^hw.ramSize=.*/hw.ramSize=3072/' $CFG 2>/dev/null; grep -q '^hw.keyboard' $CFG && sed -i '' 's/^hw.keyboard=.*/hw.keyboard=yes/' $CFG || echo 'hw.keyboard=yes' >> $CFG
$SDK/emulator/emulator -list-avds
echo "== XONG TAO MAY AO =="
