#!/usr/bin/env bash
# 补齐 Logseq loong64 发布包/本地包中缺失的运行时依赖。
#
# 背景：
#   - 社区发布包 v2.0.2-loong64 的 app.asar 本身就缺 electron-log 等 14 个顶层
#     dependencies，启动主进程直接报 "Cannot find module 'electron-log'"。
#   - electron-builder 26.17.0 + pnpm 10.33 的依赖收集器会跳过 pnpm 顶层符号链接，
#     本地重建同样漏掉这些依赖。
#   - 单纯补顶层依赖不够，还需要递归补齐 socks / fastify / electron-updater 的
#     传递依赖（smart-buffer、ip-address、escape-string-regexp 等）。
#   - path-exists 存在版本冲突：unused-filename 需要 v5 的命名导出，
#     locate-path 需要 v3 的默认导出；顶层放 v5，给 locate-path 单独塞 v3。
#
# 用法：bash scripts/loong64/fix-asar-deps.sh [发布包tar.gz路径]
# 依赖：@electron/asar（默认 /tmp/asar-tool/node_modules/.bin/asar）、Node 22 loong64。
set -euo pipefail
cd "$(dirname "$0")/../.."

RELEASE_TAR=${1:-/tmp/logseq-release.tar.gz}
ASAR=${ASAR:-/tmp/asar-tool/node_modules/.bin/asar}
NODE_BIN=${NODE_BIN:-$(command -v node)}
RES=static/dist/linux-unpacked/resources
WORK=/tmp/logseq-asar-fix
export PATH="$(dirname "$NODE_BIN"):$PATH"

[ -x "$ASAR" ] || { echo "缺少 $ASAR" >&2; exit 1; }
[ -f "$RELEASE_TAR" ] || { echo "缺少 $RELEASE_TAR" >&2; exit 1; }

# 0) 以发布包 baseline 起手（本地 electron-builder 产物补依赖后会段错误）
rm -rf "$WORK" && mkdir -p "$WORK/release"
tar -xzf "$RELEASE_TAR" -C "$WORK/release" ./resources/app.asar ./resources/app.asar.unpacked
"$ASAR" extract "$WORK/release/resources/app.asar" "$WORK/build"
cp -a "$WORK/release/resources/app.asar.unpacked/." "$WORK/build/" 2>/dev/null || true

# 1) 把 pnpm 顶层依赖符号链接解引用为真实目录
cd static/node_modules
for m in "$("$NODE_BIN" -p "Object.keys(require('../package.json').dependencies||{}).join(' ')")"; do
  [ -L "$m" ] || continue
  t=$(readlink -f "$m"); rm "$m"; cp -a "$t" "$m"
done
cd - >/dev/null

# 2) 复制顶层运行时依赖
for m in abort-controller command-exists diff-match-patch electron-dl electron-log \
         electron-updater electron-window-state extract-zip fastify socks-proxy-agent \
         ws zod; do
  cp -a "static/node_modules/$m" "$WORK/build/node_modules/$m"
done
mkdir -p "$WORK/build/node_modules/@fastify" "$WORK/build/node_modules/@modelcontextprotocol"
cp -a static/node_modules/@fastify/cors "$WORK/build/node_modules/@fastify/cors"
cp -a static/node_modules/@modelcontextprotocol/sdk "$WORK/build/node_modules/@modelcontextprotocol/sdk"

# 3) 迭代补齐传递依赖：扫描实际 require/import 的裸包名，缺什么补什么，直到收敛
"$NODE_BIN" - "$WORK" <<'EOF'
const fs=require('fs'),os=require('os'),path=require('path'),cp=require('child_process');
const work=process.argv[2], build=path.join(work,'build'), store='static/node_modules/.pnpm';
const pnpm={};
for(const d of fs.readdirSync(store)){
  const nm=path.join(store,d,'node_modules');
  if(!fs.statSync(nm).isDirectory())continue;
  for(const e of fs.readdirSync(nm)){
    if(e.startsWith('.'))continue;
    const p=path.join(nm,e);
    if(e.startsWith('@')&&fs.statSync(p).isDirectory()){
      for(const s of fs.readdirSync(p))if(!(e+'/'+s in pnpm))pnpm[e+'/'+s]=path.join(p,s);
    } else if(!(e in pnpm))pnpm[e]=p;
  }
}
const EX=new Set(['electron','electron-devtools-installer','electron-builder','electron-publish',
 'electron-winstaller','electron-builder-squirrel-windows','app-builder-lib','dmg-builder','opam']);
const PREFIXES=['@electron/','@electron-internal/','@malept/','@types/','eslint','webpack','rollup',
 '@rollup/','vite','vitest','jest','prettier','typescript','tailwindcss','@tailwindcss/','postcss',
 'autoprefixer','lightningcss','terser','esbuild','@swc/','babel','@babel/','ts-node','mocha'];
const excluded=n=>EX.has(n)||PREFIXES.some(p=>n.startsWith(p));
const re=/(?:require\(\s*|from\s+|import\(\s*)['"]([^'"]+)['"]/g;
for(let it=0;it<10;it++){
  const mods=new Set();
  const files=cp.execSync(`find ${build} -type f \\( -name '*.js' -o -name '*.cjs' -o -name '*.mjs' \\)`).toString().trim().split('\n').filter(Boolean);
  for(const f of files){
    let t;try{t=fs.readFileSync(f,'utf8')}catch{continue}
    for(const m of t.matchAll(re)){
      const n=m[1].startsWith('@')?m[1].split('/').slice(0,2).join('/'):m[1].split('/')[0];
      if(n&&!n.startsWith('.')&&!n.startsWith('/'))mods.add(n);
    }
  }
  const nd=path.join(build,'node_modules'),have=new Set();
  for(const e of fs.readdirSync(nd)){
    if(e.startsWith('.'))continue;
    if(e.startsWith('@'))for(const s of fs.readdirSync(path.join(nd,e)))have.add(e+'/'+s);
    else have.add(e);
  }
  const need=[...mods].filter(n=>!have.has(n)&&pnpm[n]&&!excluded(n)).sort();
  console.log(`iter ${it}: need=${need.length}`);
  if(!need.length)break;
  for(const n of need){
    const dst=path.join(nd,n);fs.mkdirSync(path.dirname(dst),{recursive:true});
    fs.rmSync(dst,{recursive:true,force:true});cp.execFileSync('cp',['-a',pnpm[n],dst]);
  }
}
EOF

# 4) path-exists 版本冲突：顶层 v5（命名导出），locate-path 内部 v3（默认导出）
rm -rf "$WORK/build/node_modules/path-exists"
cp -a static/node_modules/.pnpm/path-exists@5.0.0/node_modules/path-exists "$WORK/build/node_modules/path-exists"
mkdir -p "$WORK/build/node_modules/locate-path/node_modules"
cp -a static/node_modules/.pnpm/path-exists@3.0.0/node_modules/path-exists \
      "$WORK/build/node_modules/locate-path/node_modules/path-exists"

# 5) 重建 asar（发布包 baseline 才有 @zvec 原生绑定）
rm -f "$WORK/app.asar"; rm -rf "$WORK/app.asar.unpacked"
"$ASAR" pack "$WORK/build" "$WORK/app.asar" --unpack-dir 'node_modules/{keytar,jszip,@zvec}'
rm -rf "$RES/app.asar" "$RES/app.asar.unpacked"
cp -a "$WORK/app.asar" "$RES/app.asar"
cp -a "$WORK/app.asar.unpacked" "$RES/app.asar.unpacked"

echo "完成：$RES/app.asar"
echo "启动验证：cd $RES/.. && env -u ELECTRON_RUN_AS_NODE ./logseq"
