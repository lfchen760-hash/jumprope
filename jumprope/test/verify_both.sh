#!/usr/bin/env bash
# 一条命令：本地视频 → JS 计数 + Dart 计数，并比对
#
#   bash test/verify_both.sh 视频.mp4 [真实次数]
set -e
cd "$(dirname "$0")/.."

export PYTHONPATH=/root/dsh/test/.pylibs:${PYTHONPATH:-}
export LD_LIBRARY_PATH=/root/dsh/test/.syslibs/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}
export MPLCONFIGDIR=/root/dsh/test/.mpl
export PATH=/root/dsh/test/.dart/dart-sdk/bin:$PATH
export HOME=/root/dsh/test/.dart-home
export PUB_CACHE=/root/dsh/test/.pub-cache

VIDEO="$1"
EXPECTED="${2:-}"
LM=/tmp/lm_verify.json
GOLD=/tmp/golden_verify.json

[ -z "$VIDEO" ] && { echo "用法: bash test/verify_both.sh 视频.mp4 [真实次数]"; exit 1; }

echo ">>> 1/3 提取关键点"
python3 test/extract.py "$VIDEO" "$LM" >/dev/null
echo "    ok"

echo ">>> 2/3 转成黄金向量"
node test/make_golden.mjs "$LM" "$GOLD" "$EXPECTED" >/dev/null
echo "    ok"

echo ">>> 3/3 两端计数"
JS=$(node test/count_golden.mjs "$GOLD")
DART=$(cd ../dart_core && dart run verify.dart "$GOLD" --count 2>/dev/null | tail -1)

echo
echo "  视频      $(basename "$VIDEO")"
[ -n "$EXPECTED" ] && echo "  标注      $EXPECTED"
echo "  JS 计数   $JS"
echo "  Dart 计数 $DART"
if [ "$JS" = "$DART" ]; then
  echo "  一致性    ✅ 完全相同"
else
  echo "  一致性    ❌ 不一致"
  exit 1
fi
