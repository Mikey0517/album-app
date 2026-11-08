#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "用法: VERSION_CODE VERSION_NAME [NOTES]"
  echo "示例: ./scripts/release.sh 2 1.1.0 '修复了视频上传卡顿'"
  exit 1
fi

VERSION_CODE=$1
VERSION_NAME=$2
NOTES=${3:-暂无更新说明}

if ! [[ "$VERSION_CODE" =~ ^[0-9]+$ ]] || [ "$VERSION_CODE" -le 0 ]; then
  echo "❌ VERSION_CODE 必须是正整数" >&2
  exit 1
fi
if ! [[ "$VERSION_NAME" =~ ^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$ ]]; then
  echo "❌ VERSION_NAME 只能包含数字、字母、点、下划线、短横线" >&2
  exit 1
fi

SERVER=${SERVER:-http://192.168.1.50:8000}
SECRET=${SECRET:?请先 export SECRET=你的 UPLOAD_SECRET}
FLUTTER=${FLUTTER:-flutter}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> 写入更新日志 assets/changelog.md"
mkdir -p assets
# 同时支持真实换行和用户传入的 \n 转义，避免更新日志里出现字面量 \n。
NOTES_RENDERED=$(printf '%b' "${NOTES:-暂无更新说明}")
printf '%s\n' "$NOTES_RENDERED" > assets/changelog.md

echo "==> 打包 v$VERSION_NAME ($VERSION_CODE)"
"$FLUTTER" build apk --release \
  --build-name="$VERSION_NAME" \
  --build-number="$VERSION_CODE"

APK="build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK" ]; then
  echo "❌ 打包失败，未找到 $APK" >&2
  exit 1
fi

echo "==> APK SHA-256"
sha256sum "$APK"

echo "==> 上传到 $SERVER"
curl -fsS --progress-bar \
  -X POST "$SERVER/api/app/release" \
  -H "X-Upload-Secret: $SECRET" \
  -F "file=@$APK" \
  -F "versionCode=$VERSION_CODE" \
  -F "versionName=$VERSION_NAME" \
  -F "notes=$NOTES"

echo
echo "✅ 发布完成：v$VERSION_NAME ($VERSION_CODE)"
echo "   管理后台：$SERVER/admin"
