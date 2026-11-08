#!/usr/bin/env bash
# 一条命令跑完：视频 -> 关键点 -> 用线上同一份计数代码回放
#
#   bash test/run.sh 视频.mp4 [真实次数] [输出json]
set -e
cd "$(dirname "$0")/.."

export PYTHONPATH=/root/dsh/test/.pylibs:${PYTHONPATH:-}
export LD_LIBRARY_PATH=/root/dsh/test/.syslibs/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}
export MPLCONFIGDIR=/root/dsh/test/.mpl

VIDEO="$1"
EXPECTED="${2:-}"
OUT="${3:-/tmp/landmarks.json}"

if [ -z "$VIDEO" ]; then
  echo "用法: bash test/run.sh 视频.mp4 [真实次数] [输出json]"
  exit 1
fi

echo ">>> 1/2 提取关键点"
python3 test/extract.py "$VIDEO" "$OUT"

echo
echo ">>> 2/2 回放计数"
if [ -n "$EXPECTED" ]; then
  node test/replay.mjs "$OUT" "$EXPECTED" --sweep
else
  node test/replay.mjs "$OUT"
fi
