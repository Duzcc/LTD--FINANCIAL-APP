#!/bin/zsh -l
# Giữ cửa sổ này mở: mỗi khi có tệp tool/.chay_lai, chạy lại kiểm tra và ghi tool/ket_qua_kiem_tra.txt
cd "$(dirname "$0")/.."
echo "Đang chờ yêu cầu kiểm tra (đóng cửa sổ để dừng)…"
touch tool/.chay_lai
while true; do
  if [ -f tool/.chay_lai ]; then
    rm -f tool/.chay_lai
    echo "$(date '+%H:%M:%S') chạy kiểm tra…"
    zsh tool/kiem_tra.command
    echo "$(date '+%H:%M:%S') xong."
  fi
  sleep 3
done
