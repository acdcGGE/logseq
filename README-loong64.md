# Logseq LoongArch64 原生构建

在 LoongArch64 上原生编译 Logseq 桌面端（Electron + 原生模块），前端/CLI 的架构无关产物取自同版本发布包 v2.0.2-loong64。

## 依赖

- 系统包：`nodejs`、`pnpm`、`clojure`、`opam`、`node-gyp`、`gcc`/`g++`、`ar`、`libsecret`（开发文件）；打包 deb 需 `dpkg-deb`、`ar`，打包 pkg 需 `bsdtar` + `zstd`（或 `makepkg`）
- Node 22 loong64（unofficial-builds）解压到用户目录，例如 `~/.local/opt/node-v22.20.0-linux-loong64/bin`，通过 `NODE_BIN_DIR` 指定
- Electron loong64 运行时：`darkyzhou/electron-loong64` 的 `v42.3.0`，解压后目录通过 `ELECTRON_DIST` 指定
- 下载器默认 `/usr/bin/aria2-next`（rayburst），可用 `DOWNLOADER` 覆盖
- npm 依赖默认走 npmmirror（loongnix 镜像对 `@tailwindcss/oxide`/`rolldown` 的 tarball 校验失败）
- 发布包 v2.0.2-loong64 解包到某目录（默认 `/tmp/logseq-release`，用 `PREBUILT_DIR` 覆盖），提供架构无关的 CSS/JS/CLI 产物

## 构建

```bash
export ELECTRON_DIST=$PWD/electron-v42.3.0-linux-loong64
export NODE_BIN_DIR=$HOME/.local/opt/node-v22.20.0-linux-loong64/bin
export PREBUILT_DIR=/tmp/logseq-release     # 发布包解包位置

# 推荐：跳过 CSS/CLJS/CLI 的本地编译（龙芯单核极慢或未适配），从发布包取架构无关产物
LOONG64_PREBUILT_CSS=1 USE_PREBUILT_JS=1 SKIP_CLI=1 \
  scripts/loong64/build-local.sh
scripts/loong64/fix-asar-deps.sh /path/to/logseq-2.0.2-linux-loong64.tar.gz
scripts/loong64/package.sh       # deb + tar.gz
scripts/loong64/pkg.sh           # Arch Linux pkg.tar.zst（见下）
```

`build.sh` 为原始全量构建配方；`build-local.sh` 为龙芯本机实操配方。`LOONG64_PREBUILT_CSS`/`USE_PREBUILT_JS`/`SKIP_CLI` 开关对应 gulpfile 与各构建阶段的本地化替代。

## 产物

- `static/dist/linux-unpacked/`
- `static/dist/logseq-<version>-linux-loong64.tar.gz`
- `static/dist/logseq_<version>_loong64.deb`（`Architecture: loong64`）
- `static/dist/logseq-<version>-<rel>-loong64.pkg.tar.zst`（Arch Linux）

发布包见 GitHub Releases 的 `v2.0.2-loong64`：当前含上述 deb、tar.gz 与 pkg.tar.zst 三种格式。

## 已知限制

- 原生模块 `better-sqlite3` 13.2.0、`keytar` 7.9.0 以 Electron 42 头文件在本机编译；数据库实际走 `@sqlite.org/sqlite-wasm`（架构无关）。
- Electron 42.3.0，electron-builder 不识别 loong64，用 `--linux dir --x64` 配合 `electronDist` 生成目录，再手工构造 `Architecture: loong64` 的 deb / tar.gz / pkg。
- electron-builder 26.17 + pnpm 10.33 的依赖收集器跳过 pnpm 顶层符号链接，`app.asar` 会缺 `electron-log` 等运行时依赖；`fix-asar-deps.sh` 以发布包 baseline 迭代补齐，并修正 `path-exists` v5/v3 冲突后重建 asar。
- `@zvec/zvec` 只有 x64/arm64 预编译，源码移植需 Arrow/SIMD，未做；`sentence-transformers`/torch 无 loong64 wheel。二者均为懒加载，不影响启动、编辑与 CLI，但语义检索不可用。
- 无头/终端启动需加 `--disable-gpu --no-sandbox` 以绕开 GPU 进程崩溃。
