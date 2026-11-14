#!/usr/bin/env bash
# 统一发版入口：能走热更新就走补丁，走不了才发全量 APK。
#
# 用法:
#   ./scripts/release-auto.sh "修复 xxx"            # 自动判断
#   FORCE_APK=1 ./scripts/release-auto.sh "..."    # 强制发 APK（升 versionCode）
#
# 判断依据（与 scripts/release-patch.sh 内的一致）：
#   自 pubspec.yaml 上次变更（= 当前 versionCode 的基线）以来，改动是否只落在 lib/
#   - 只改 lib/**            → 发补丁（不升 versionCode，用户下次冷启动生效）
#   - 改了 android/ ios/ assets/ pubspec.yaml 等 → 必须发全量 APK
set -euo pipefail

NOTES=${1:-暂无说明}
FORCE_APK=${FORCE_APK:-0}
SERVER=${SERVER:-http://192.168.1.100:8000}
SECRET=${SECRET:?请先 export SECRET=你的上传密钥}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BASE_COMMIT=$(git log -1 --format=%H -- pubspec.yaml 2>/dev/null || true)
CHANGED=$(git diff --name-only "$BASE_COMMIT" HEAD 2>/dev/null || true)
BLOCKED=$(printf '%s\n' "$CHANGED" | grep -vE '^(lib/|test/|scripts/|docs/|.*\.md$)' | grep -v '^$' || true)

if [ "$FORCE_APK" = "1" ]; then
  echo "==> 指定 FORCE_APK=1，走全量"
  exec "$ROOT/scripts/release.sh" "$@"
fi

if [ -z "$BLOCKED" ]; then
  echo "==> 改动只涉及 Dart，走热更新补丁"
  exec "$ROOT/scripts/release-patch.sh" "$NOTES"
fi

echo "==> 检测到原生/依赖/资源改动，必须发全量 APK："
printf '   %s\n' $BLOCKED
echo "==> 提示：如果这些改动其实和用户无关（如 CI、文档），把对应路径加进上面的白名单"
exec "$ROOT/scripts/release.sh" "$@"

