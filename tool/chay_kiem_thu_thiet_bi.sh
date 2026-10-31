#!/bin/zsh -l
# Chạy một kịch bản integration_test trên thiết bị: chay_kiem_thu_thiet_bi.sh <id-thiết-bị> <tệp> [thư-mục-ảnh]
ROOT="$HOME/Desktop/Android-NHOM3"
DEV=$1; TARGET=$2; OUTDIR=${3:-demo}
cd "$ROOT/frontend"
rm -rf build/demo 2>/dev/null || mv build/demo "$ROOT/_to_delete/demo_$(date +%s)" 2>/dev/null
( sleep 1200; pkill -f "flutter_tools.*drive" ) &
WD=$!
START=$(date +%s)
if [[ "$DEV" == emulator-* ]]; then RUN=flutter; else RUN="$ROOT/tool/flutter_ios.sh"; fi
$RUN drive --driver=test_driver/integration_test.dart --target="$TARGET" -d "$DEV" > "$ROOT/tool/drive_log.txt" 2>&1
CODE=$?
kill $WD 2>/dev/null
cp "$ROOT/tool/drive_log.txt" "$ROOT/tool/drive_log_${OUTDIR}.txt"
echo "drive exit=$CODE ($(( $(date +%s) - START ))s) thiết bị=$DEV tệp=$TARGET"
grep -E "All tests passed|Some tests failed|Không thấy|Expected:|Actual:|Hóa đơn:|màn .* dựng lỗi|was thrown" "$ROOT/tool/drive_log.txt" | sed "s/^I\/flutter ( *[0-9]*): //; s/^flutter: //" | sort -u | head -12
if [ -d build/demo ]; then mkdir -p "build/$OUTDIR"; [ "$OUTDIR" != demo ] && cp build/demo/*.png "build/$OUTDIR/" 2>/dev/null; ls build/demo | wc -l; fi
