#!/usr/bin/env bash
# 在 LoongArch64 上原生编译 Logseq 桌面版（CLJS + Electron + 原生模块）
set -euo pipefail
cd "$(dirname "$0")/../.."

: "${ELECTRON_VERSION:=42.3.0}"
: "${ELECTRON_DIST:?请设置 ELECTRON_DIST 为解压后的 electron-loong64 运行时目录}"
: "${NPM_REGISTRY:=https://registry.npmmirror.com}"

export npm_config_registry="$NPM_REGISTRY"

# 1. 依赖与资源
pnpm install
pnpm gulp:build

# 2. ClojureScript 构建
clojure -J-Xmx6g -M:cljs release app db-worker db-worker-node electron publishing
pnpm webpack-app-build
pnpm db-worker-node:bundle

# 3. CLI（Melange，产物为纯 JS）
(cd cli && pnpm install --ignore-workspace --ignore-scripts && opam exec -- dune build @bundle)
cp cli/_build/default/dist/logseq-cli.js static/logseq-cli.js
pnpm desktop:prepare-runtime-js

# 4. Electron 头文件（架构无关）
NODE_GYP_DIR=$HOME/.cache/node-gyp/$ELECTRON_VERSION
if [ ! -d "$NODE_GYP_DIR/include/node" ]; then
  mkdir -p "$NODE_GYP_DIR"
  curl -fL --retry 3 -o /tmp/node-headers.tar.gz \
    "https://registry.npmmirror.com/-/binary/electron/$ELECTRON_VERSION/node-v$ELECTRON_VERSION-headers.tar.gz"
  tar -xzf /tmp/node-headers.tar.gz -C "$NODE_GYP_DIR" --strip-components=1
fi
GYP="node-gyp rebuild --release --target=$ELECTRON_VERSION \
  --dist-url=https://electronjs.org/headers --ensure"

# 5. better-sqlite3（Electron ABI）
(cd node_modules/better-sqlite3 && rm -rf build && $GYP --force_build=1)

# 6. static 依赖（跳过脚本，原生模块单独构建）
(cd static && ELECTRON_SKIP_BINARY_DOWNLOAD=1 \
  pnpm install --ignore-workspace --frozen-lockfile --ignore-scripts)

# 7. keytar（系统 libsecret）
(cd static/node_modules/keytar && rm -rf build && $GYP)

# 8. electron 打包目录
(cd static && pnpm exec electron-builder --config electron-builder.yml --linux dir --x64 \
  -c.electronDist="$ELECTRON_DIST" -c.electronVersion="$ELECTRON_VERSION" \
  -c.npmRebuild=false --publish never)

# 9. 用本机架构的 keytar 覆盖打包结果
cp -f static/node_modules/keytar/build/Release/keytar.node \
  static/dist/linux-unpacked/resources/app.asar.unpacked/node_modules/keytar/build/Release/keytar.node

echo "完成：static/dist/linux-unpacked"
