#!/bin/bash
# Chạy lệnh flutter cho iOS trong thư mục frontend/ (dùng CocoaPods cục bộ nếu máy chưa có `pod`).
set -euo pipefail
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
project_root="$repo_root/frontend"
cd "$project_root"
# Giữ thư mục build iOS ngoài Desktop/iCloud (iCloud gắn FinderInfo khiến codesign từ chối framework).
ios_build_root="/private/tmp/android-nhom3-ios-build"
mkdir -p "$ios_build_root" "$project_root/build"
if [ ! -e "$project_root/build/ios" ] && [ ! -L "$project_root/build/ios" ]; then
  ln -s "$ios_build_root" "$project_root/build/ios"
fi
if ! command -v pod >/dev/null 2>&1 && [ -x "$repo_root/.tooling/gems/bin/pod" ]; then
  export GEM_HOME="$repo_root/.tooling/gems"
  export GEM_PATH="$GEM_HOME"
  export PATH="/opt/homebrew/Library/Homebrew/vendor/portable-ruby/current/bin:$GEM_HOME/bin:$PATH"
fi
exec flutter "$@"
