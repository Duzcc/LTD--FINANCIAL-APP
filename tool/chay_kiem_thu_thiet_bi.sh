#!/usr/bin/env bash
# Cách dùng: chay_kiem_thu_thiet_bi.sh <id thiết bị> <tệp test> [thư mục ảnh]
ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 1
DEV=$1; TARGET=$2; OUTDIR=${3:-demo}
cd "$ROOT/frontend" || exit 1
rm -rf build/demo
START=$(date +%s)
if [[ "$DEV" == emulator-* ]]; then RUN=flutter; else RUN="$ROOT/tool/flutter_ios.sh"; fi
"$RUN" drive --driver=test_driver/integration_test.dart --target="$TARGET" -d "$DEV" > "$ROOT/tool/drive_log.txt" 2>&1 &
DRIVE_PID=$!
(
  sleep 1200 &
  TIMER_PID=$!
  trap 'kill "$TIMER_PID" 2>/dev/null; exit 0' TERM
  wait "$TIMER_PID" && kill "$DRIVE_PID" 2>/dev/null
) </dev/null >/dev/null 2>&1 &
WD=$!
wait "$DRIVE_PID"
CODE=$?
kill "$WD" 2>/dev/null
wait "$WD" 2>/dev/null
cp "$ROOT/tool/drive_log.txt" "$ROOT/tool/drive_log_${OUTDIR}.txt"
echo "drive exit=$CODE ($(( $(date +%s) - START ))s) thiết bị=$DEV tệp=$TARGET"
grep -E "All tests passed|Some tests failed|Không thấy|Expected:|Actual:|Hóa đơn:|màn .* dựng lỗi|was thrown" "$ROOT/tool/drive_log.txt" | sed "s/^I\/flutter ( *[0-9]*): //; s/^flutter: //" | sort -u | head -12
if [ -d build/demo ]; then mkdir -p "build/$OUTDIR"; [ "$OUTDIR" != demo ] && cp build/demo/*.png "build/$OUTDIR/" 2>/dev/null; ls build/demo | wc -l; fi
exit "$CODE"
