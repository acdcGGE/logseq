#!/usr/bin/env bash
# 生成 Arch Linux 包：logseq-<version>-<rel>-loong64.pkg.tar.zst
set -euo pipefail
cd "$(dirname "$0")/../.."

UNPACKED=static/dist/linux-unpacked
[ -d "$UNPACKED" ] || { echo "缺少 $UNPACKED，请先运行 build.sh"; exit 1; }
VERSION=$(node -p "require('./static/package.json').version")
REL=${PKGREL:-1}
WORK=static/dist/pkgbuild

rm -rf "$WORK"
mkdir -p "$WORK"
cp -a "$UNPACKED" "$WORK/linux-unpacked"
cp static/icons/logseq.png "$WORK/logseq.png"

cat > "$WORK/PKGBUILD" <<EOF
pkgname=logseq
pkgver=$VERSION
pkgrel=$REL
pkgdesc="Privacy-first, open-source platform for knowledge management"
arch=('loong64')
url="https://logseq.com"
license=('AGPL-3.0')
depends=('gtk3' 'nss' 'libxss' 'libxtst' 'alsa-lib' 'libsecret' 'libnotify' 'libxkbcommon' 'mesa')
options=('!strip' '!debug')


package() {
  install -d "\$pkgdir/opt/Logseq" "\$pkgdir/usr/bin" "\$pkgdir/usr/share/applications"
  cp -a "\$startdir/linux-unpacked/." "\$pkgdir/opt/Logseq/"
  ln -sf /opt/Logseq/logseq "\$pkgdir/usr/bin/logseq"
  install -Dm644 "\$startdir/logseq.png" "\$pkgdir/usr/share/icons/hicolor/512x512/apps/logseq.png"
  install -Dm644 "\$startdir/logseq.png" "\$pkgdir/usr/share/pixmaps/logseq.png"
  install -Dm644 /dev/stdin "\$pkgdir/usr/share/applications/logseq.desktop" <<'DESK'
[Desktop Entry]
Name=Logseq
Comment=A privacy-first, open-source platform for knowledge management
Type=Application
Categories=Office;
Exec=logseq %U
Icon=logseq
Terminal=false
StartupWMClass=Logseq
MimeType=x-scheme-handler/logseq;
DESK
}
EOF

CONF_ARGS=()
[ -n "${MAKEPKG_CONF:-}" ] && CONF_ARGS=(--config "$MAKEPKG_CONF")
(cd "$WORK" && makepkg -A -f --nodeps --nocheck "${CONF_ARGS[@]}")
mv "$WORK"/logseq-"$VERSION"-"$REL"-loong64.pkg.tar.zst static/dist/
ls -lh static/dist/logseq-"$VERSION"-"$REL"-loong64.pkg.tar.zst
