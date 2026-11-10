#!/usr/bin/env bash
# 发布 Dart 热更新补丁（flutter_patcher）。
# 用法: ./scripts/release-patch.sh "修复朋友圈九宫格闪烁"
#
# 关键约束：补丁只对同一个 versionCode 的 APK 生效，所以这里不升版本号；
# 一旦 APK 升了 versionCode，旧补丁自动失效，需要基于新基线重新打包。
set -euo pipefail

NOTES=${1:-暂无说明}
SERVER=${SERVER:-http://192.168.1.100:8000}
SECRET=${SECRET:?请先 export SECRET=你的上传密钥}
FORCE=${FORCE:-0}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FLUTTER=${FLUTTER:-flutter}

VERSION_LINE=$(grep '^version:' pubspec.yaml | sed 's/version: *//')
VERSION_NAME=${VERSION_LINE%%+*}
VERSION_CODE=${VERSION_LINE##*+}
if ! [[ "$VERSION_CODE" =~ ^[0-9]+$ ]]; then
  echo "❌ 无法从 pubspec.yaml 读取 versionCode" >&2
  exit 1
fi

echo "==> 基线 APK: $VERSION_NAME ($VERSION_CODE)"
echo "==> 补丁说明: $NOTES"

# ---------- 1. 自动判断这次改动能不能靠补丁解决 ----------
BASE_COMMIT=$(git log -1 --format=%H -- pubspec.yaml 2>/dev/null || true)
if [ -n "${BASE_COMMIT}" ]; then
  CHANGED=$(git diff --name-only "$BASE_COMMIT" HEAD 2>/dev/null || true)
  # 只有 lib/ 下的 Dart 代码可以热更新；测试/脚本/文档不影响产物，放行。
  BLOCKED=""
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    case "$path" in
      lib/*) ;;
      test/*|scripts/*|docs/*|*.md) ;;
      *) BLOCKED="${BLOCKED}${path}"$'\n' ;;
    esac
  done <<< "$CHANGED"

  if [ -n "$BLOCKED" ]; then
    echo "❌ 以下改动发生在原生/依赖/资源层，补丁下发不会生效，必须走 APK 发布：" >&2
    printf '   %s\n' $BLOCKED >&2
    echo "   （仅改 lib/ 下的 Dart 代码才能用热更新；原生代码、权限、插件、图标、AndroidManifest 都要发 APK）" >&2
    if [ "$FORCE" != "1" ]; then
      echo "   如确认只是 Dart 改动被误判，可 FORCE=1 重跑。" >&2
      exit 1
    fi
  fi
else
  echo "⚠️  读不到 pubspec.yaml 的历史提交，跳过改动类型判断"
fi

# ---------- 2. 构建与基线同 versionCode 的 release APK ----------
echo "==> 构建 release APK（versionCode 保持 $VERSION_CODE）"
"$FLUTTER" --no-version-check build apk --release \
  --build-name="$VERSION_NAME" \
  --build-number="$VERSION_CODE"

APK=build/app/outputs/flutter-apk/app-release.apk
[ -f "$APK" ] || { echo "❌ 未找到 $APK" >&2; exit 1; }

# ---------- 3. 生成补丁 ----------
PATCH_TAG="${VERSION_NAME}+${VERSION_CODE}-$(date +%Y%m%d%H%M)"
echo "==> 生成补丁 $PATCH_TAG"
rm -rf dist
dart run flutter_patcher:pack \
  --apk "$APK" \
  --version "$PATCH_TAG" \
  --target-version-code "$VERSION_CODE" \
  --out dist

[ -f dist/patch.zip ] || { echo "❌ 补丁生成失败" >&2; exit 1; }
ls -l dist/patch.zip

# ---------- 4. 上传 ----------
echo "==> 上传到 $SERVER"
curl -fsS -X POST "$SERVER/api/admin/patch/upload" \
  -H "X-Upload-Secret: $SECRET" \
  -F "file=@dist/patch.zip" \
  -F "base_version_code=$VERSION_CODE" \
  -F "release_notes=$NOTES"
echo ""
echo "✅ 补丁已发布：用户下次冷启动会自动下载，再下一次冷启动生效"
