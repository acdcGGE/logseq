#!/usr/bin/env bash
# 本机 loong64 构建配方：基于 scripts/loong64/build.sh，改为使用
# 用户态 Node 22 / Clojure CLI / loongnix npm 源 / rayburst 的 aria2-next 下载器。
# CLI（OCaml/Melange）步骤由 SKIP_CLI=1 跳过，产物可事后从发布包取 JS。
set -euo pipefail
cd "$(dirname "$0")/../.."

# Node 22 loong64（unofficial-builds）解压后的 bin 目录；按实际情况覆盖
NODE_BIN_DIR="${NODE_BIN_DIR:-$HOME/.local/opt/node-v22.20.0-linux-loong64/bin}"
export PATH="$NODE_BIN_DIR:$HOME/.local/bin:$PATH"
# loongnix 镜像对 @tailwindcss/oxide、rolldown 的 tarball 校验失败，默认走 npmmirror
export NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
export npm_config_registry="$NPM_REGISTRY"
export npm_config_strict_ssl=false
export NODE_TLS_REJECT_UNAUTHORIZED=0
export ELECTRON_VERSION=42.3.0
export ELECTRON_DIST="${ELECTRON_DIST:-$PWD/electron-v42.3.0-linux-loong64}"
DOWNLOADER="${DOWNLOADER:-/usr/bin/aria2-next}"
# 发布包 v2.0.2-loong64 解包目录，提供架构无关的 CSS/JS/CLI 产物
PREBUILT_DIR="${PREBUILT_DIR:-/tmp/logseq-release}"

[ -x "$ELECTRON_DIST/electron" ] || { echo "缺少 ELECTRON_DIST: $ELECTRON_DIST" >&2; exit 1; }

echo "=== [1/8] root deps + gulp assets ==="
pnpm install
pnpm gulp:build
if [ "${LOONG64_PREBUILT_CSS:-0}" = "1" ]; then
  [ -f "$PREBUILT_DIR/style.css" ] || { echo "缺少 $PREBUILT_DIR/style.css" >&2; exit 1; }
  mkdir -p static/css
  cp "$PREBUILT_DIR/style.css" static/css/style.css
fi

echo "=== [2/8] ClojureScript release ==="
if [ "${USE_PREBUILT_JS:-0}" = "1" ]; then
  echo "USE_PREBUILT_JS=1，使用发布包中同版本编译好的 JS（本机只编译原生模块）"
  SRC="$PREBUILT_DIR/asar-full"
  [ -d "$SRC/js" ] || { echo "缺少 $SRC/js" >&2; exit 1; }
  mkdir -p static/js dist
  cp -a "$SRC/js/." static/js/
  cp "$SRC/db-worker-node.js" dist/db-worker-node.js
  cp "$SRC/db-worker-node.js" static/db-worker-node.js
  cp "$SRC/logseq-cli.js" static/logseq-cli.js
else
  clojure -J-Xmx6g -M:cljs release app db-worker db-worker-node electron publishing
  pnpm webpack-app-build
  pnpm db-worker-node:bundle
fi

echo "=== [3/8] CLI runtime JS ==="
if [ "${SKIP_CLI:-0}" = "1" ]; then
  echo "SKIP_CLI=1，跳过 OCaml CLI 构建，使用已准备好的 CLI JS"
  [ -f "$PREBUILT_DIR/logseq-cli.js" ] || { echo "缺少 $PREBUILT_DIR/logseq-cli.js" >&2; exit 1; }
  cp "$PREBUILT_DIR/logseq-cli.js" static/logseq-cli.js
else
  (cd cli && pnpm install --ignore-workspace --ignore-scripts && opam exec -- dune build @bundle)
  cp cli/_build/default/dist/logseq-cli.js static/logseq-cli.js
fi
pnpm desktop:prepare-runtime-js

echo "=== [4/8] Electron headers ==="
NODE_GYP_DIR=$HOME/.cache/node-gyp/$ELECTRON_VERSION
if [ ! -d "$NODE_GYP_DIR/include/node" ]; then
  mkdir -p "$NODE_GYP_DIR"
  "$DOWNLOADER" --dir=/tmp --out=node-headers.tar.gz \
    "https://registry.npmmirror.com/-/binary/electron/$ELECTRON_VERSION/node-v$ELECTRON_VERSION-headers.tar.gz"
  tar -xzf /tmp/node-headers.tar.gz -C "$NODE_GYP_DIR" --strip-components=1
fi
GYP="node-gyp rebuild --release --target=$ELECTRON_VERSION --dist-url=https://electronjs.org/headers --ensure"

echo "=== [5/8] better-sqlite3 ==="
(cd node_modules/better-sqlite3 && rm -rf build && $GYP --force_build=1)

echo "=== [6/8] static deps ==="
(cd static && ELECTRON_SKIP_BINARY_DOWNLOAD=1 \
  pnpm install --ignore-workspace --frozen-lockfile --ignore-scripts)

echo "=== [7/8] keytar ==="
(cd static/node_modules/keytar && rm -rf build && $GYP)

echo "=== [8/8] electron-builder (linux dir) ==="
(cd static && pnpm exec electron-builder --config electron-builder.yml --linux dir --x64 \
  -c.electronDist="$ELECTRON_DIST" -c.electronVersion="$ELECTRON_VERSION" \
  -c.npmRebuild=false --publish never)

cp -f static/node_modules/keytar/build/Release/keytar.node \
  static/dist/linux-unpacked/resources/app.asar.unpacked/node_modules/keytar/build/Release/keytar.node

echo "完成：static/dist/linux-unpacked"
