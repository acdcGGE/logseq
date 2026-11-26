# Logseq LoongArch64 原生构建

在 LoongArch64 上原生编译 Logseq 桌面端（ClojureScript + Electron + 原生模块）。

## 依赖

- 系统包：`nodejs`、`pnpm`、`clojure`、`opam`、`node-gyp`、`gcc`/`g++`、`ar`、`libsecret`（开发文件）
- 网络：
  - Electron loong64 运行时：`darkyzhou/electron-loong64` 的 `v42.3.0` 产物，解压后目录通过 `ELECTRON_DIST` 指定
  - Electron 头文件从 npmmirror 自动下载；npm 依赖默认走 npmmirror
- opam 环境：`cli` 目录执行 `opam install --deps-only .`（OCaml 5.2 + melange 等）

## 构建

```bash
export ELECTRON_DIST=$PWD/electron-v42.3.0-linux-loong64
scripts/loong64/build.sh     # 前端 + CLI + 原生模块 + linux-unpacked
scripts/loong64/package.sh   # deb + tar.gz
```

## 产物

- `static/dist/linux-unpacked/`
- `static/dist/logseq-<version>-linux-loong64.tar.gz`
- `static/dist/logseq_<version>_loong64.deb`

## 说明

- 原生模块（`better-sqlite3`、`keytar`）以 Electron 头文件在本机编译。
- `better-sqlite3` 升级到 13.2.0：Electron 42 的 V8 14 头文件移除了旧版 `External` 接口。
- `logseq-cli` 为 OCaml/Melange 项目，产物是架构无关的 JS，随应用分发。
- Electron 使用 42.3.0（loong64 当前可用版本）。
- electron-builder 不支持 loong64 架构，因此以 `--linux dir --x64` 配合 `electronDist` 生成目录，再手工构造 `Architecture: loong64` 的 deb 与 tar.gz。
