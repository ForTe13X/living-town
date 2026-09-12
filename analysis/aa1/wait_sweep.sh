#!/bin/sh
# 阻塞到 margin 扫描的 180 局全部落盘为止。只发一条通知（docs/41 §1：别后台跑完就交卷，也别空转轮询）。
DIR="$1"
while true; do
  n=$(cat "$DIR"/*.txt 2>/dev/null | grep -c '^\[X1M\]')
  if [ "$n" -ge 180 ]; then
    echo "SWEEP_DONE $n/180"
    break
  fi
  sleep 30
done
