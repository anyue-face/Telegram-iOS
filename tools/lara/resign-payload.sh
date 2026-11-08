#!/usr/bin/env bash
# 企业重签的补充步骤：把注入的 payload 二进制逐个签成与主程序同一 Team。
#
#   tools/lara/resign-payload.sh <Payload/Telegram.app> "iPhone Distribution: <企业名称>"
#
# 为什么必须单独做：iOS 的 library validation 只允许同一 Team ID 的 dylib 被 dlopen。
# CI 里用的是自签名占位证书，fastlane resign 换掉主程序后，payload 若还是占位签名，
# dlopen 会在运行时失败——表现为「链一动不动，日志里连 ds_run 都没打印」。
set -euo pipefail

APP="${1:?usage: resign-payload.sh <Telegram.app> <identity>}"
IDENTITY="${2:?identity required}"

[ -d "$APP" ] || { echo "no .app at $APP"; exit 1; }

echo "==> signing nested dylibs"
find "$APP/Frameworks" -type f -name "*.dylib" -print0 |
  while IFS= read -r -d '' binary; do
    codesign --force --sign "$IDENTITY" "$binary"
  done

echo "==> signing framework bundles"
for framework in "$APP"/Frameworks/*.framework; do
  [ -d "$framework" ] || continue
  codesign --force --sign "$IDENTITY" "$framework"
done

echo "==> signing loose helpers (kfd / weightBufs / …)"
find "$APP/Frameworks" -type f \( -name kfd -o -name weightBufs -o -name multicast_bytecopy \
     -o -name badRecovery -o -name dmaFail -o -name libuiopsersvc \) -print0 |
  while IFS= read -r -d '' binary; do
    codesign --force --sign "$IDENTITY" "$binary"
  done

[ -f "$APP/libjailbreak.dylib" ] && codesign --force --sign "$IDENTITY" "$APP/libjailbreak.dylib"

echo "==> verifying"
codesign -dv --verbose=2 "$APP/Frameworks/libuiopsersvc.framework" 2>&1 | grep -E "Identifier|TeamIdentifier|Authority" || true
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Identifier|TeamIdentifier|Authority" || true

echo "payload re-signed"
