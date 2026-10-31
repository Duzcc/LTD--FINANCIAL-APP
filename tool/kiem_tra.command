#!/bin/zsh -l
# Kiểm tra cả 3 phần (frontend, backend, ai-service); kết quả ghi vào tool/ket_qua_kiem_tra.txt
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT=tool/ket_qua_kiem_tra.txt
# Chế độ chạy thử: nếu có tool/.lenh.sh thì chạy lệnh đó thay cho kiểm tra
if [ -s tool/.lenh.sh ]; then
  mv tool/.lenh.sh tool/.lenh_dang_chay.sh
  zsh -l tool/.lenh_dang_chay.sh > tool/lenh_out.txt 2>&1
  echo "== LENH XONG ==" >> tool/lenh_out.txt
  exit 0
fi
{
  echo "== $(date) =="
  echo "== [ai-service] pytest =="
  if [ -x ai-service/.venv/bin/python ]; then
    (cd ai-service && .venv/bin/python -m pytest -q 2>&1 | tail -15)
  else
    echo "Chưa cài môi trường: cd ai-service && make setup train"
  fi
  echo "== [backend] npm test =="
  if [ -d backend/node_modules ]; then
    (cd backend && npm test 2>&1 | grep -E "^# (tests|pass|fail)|^not ok" )
  else
    echo "Chưa cài: cd backend && npm install"
  fi
  cd "$ROOT/frontend"
  echo "== [frontend] flutter pub get =="; flutter pub get 2>&1 | tail -5
  echo "== [frontend] flutter analyze =="; flutter analyze --no-fatal-infos 2>&1
  echo "== [frontend] flutter test =="; flutter test 2>&1 | grep -v "^  dart:\|^  package:\|^#[0-9]" | tail -60
  if [ -s "$ROOT/tool/.anh_xem_truoc" ]; then
    echo "== previews =="
    FONTS="$(dirname "$(readlink -f "$(command -v flutter)")")/cache/artifacts/material_fonts"; [ -d "$FONTS" ] || FONTS=/usr/local/share/flutter/bin/cache/artifacts/material_fonts
    flutter test test/phone_preview_test.dart --dart-define=CAPTURE_PREVIEWS=true --dart-define=PREVIEW_FONT_DIR="$FONTS" > "$ROOT/tool/preview_log.txt" 2>&1; grep -B3 -A12 "EXCEPTION CAUGHT" "$ROOT/tool/preview_log.txt" | head -60
    ls build/previews
  fi
  if [ -s "$ROOT/tool/.build_thu" ]; then
    echo "== build android =="
    flutter build apk --debug > "$ROOT/tool/build_android.txt" 2>&1; echo "exit=$?"; tail -15 "$ROOT/tool/build_android.txt"
    echo "== build ios =="
    "$ROOT/tool/flutter_ios.sh" build ios --simulator --debug > "$ROOT/tool/build_ios.txt" 2>&1; echo "exit=$?"; tail -15 "$ROOT/tool/build_ios.txt"
  fi
  echo "== DONE =="
} > "$ROOT/$OUT" 2>&1
exit 0
