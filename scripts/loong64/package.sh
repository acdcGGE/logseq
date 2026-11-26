#!/usr/bin/env bash
# 将 static/dist/linux-unpacked 打包为 loong64 的 deb 与 tar.gz
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=static/dist
UNPACKED=$OUT/linux-unpacked
VERSION=$(node -p "require('./static/package.json').version")
PKGDIR=$OUT/deb-root

[ -d "$UNPACKED" ] || { echo "缺少 $UNPACKED，请先运行 build.sh"; exit 1; }

rm -f "$OUT/logseq-$VERSION-linux-loong64.tar.gz" "$OUT/logseq_${VERSION}_loong64.deb"
rm -rf "$PKGDIR"
tar -czf "$OUT/logseq-$VERSION-linux-loong64.tar.gz" -C "$UNPACKED" .

mkdir -p "$PKGDIR/opt/Logseq" "$PKGDIR/usr/bin" "$PKGDIR/usr/share/applications" \
  "$PKGDIR/usr/share/icons/hicolor/512x512/apps" "$PKGDIR/usr/share/pixmaps" "$PKGDIR/DEBIAN"
cp -a "$UNPACKED/." "$PKGDIR/opt/Logseq/"
ln -sf /opt/Logseq/logseq "$PKGDIR/usr/bin/logseq"
cp static/icons/logseq.png "$PKGDIR/usr/share/icons/hicolor/512x512/apps/logseq.png"
cp static/icons/logseq.png "$PKGDIR/usr/share/pixmaps/logseq.png"

cat > "$PKGDIR/usr/share/applications/logseq.desktop" <<'EOF'
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
EOF

SIZE=$(du -sk "$PKGDIR/opt" | cut -f1)
cat > "$PKGDIR/DEBIAN/control" <<EOF
Package: logseq
Version: $VERSION
Architecture: loong64
Maintainer: Logseq <hello@logseq.com>
Section: office
Priority: optional
Installed-Size: $SIZE
Depends: libgtk-3-0, libnotify4, libnss3, libxss1, libxtst6, libasound2, libsecret-1-0, libgbm1
Description: A privacy-first, open-source platform for knowledge management
 Logseq is a local-first, non-linear, outliner notebook for organizing
 and sharing your personal knowledge base.
EOF

TMP=$OUT/deb-tmp
rm -rf "$TMP" && mkdir -p "$TMP"
printf '2.0\n' > "$TMP/debian-binary"
tar -czf "$TMP/control.tar.gz" -C "$PKGDIR/DEBIAN" .
tar -czf "$TMP/data.tar.gz" -C "$PKGDIR" ./opt ./usr
ar rcs "$OUT/logseq_${VERSION}_loong64.deb" "$TMP/debian-binary" "$TMP/control.tar.gz" "$TMP/data.tar.gz"
rm -rf "$TMP"

ls -lh "$OUT/logseq-$VERSION-linux-loong64.tar.gz" "$OUT/logseq_${VERSION}_loong64.deb"
