pkgname=zed
pkgver=v1.24.4
pkgrel=1
url="https://github.com/zed-industries/zed"
source=("${pkgname}-${pkgver}.tar.gz::${url}/releases/download/${pkgver}/zed-linux-x86_64.tar.gz")
sha256sums=('ecf2a7969fc71f74a7392b5022c3037c526108f9fe4b6da60355e259cd0dd4d2')

package() {
  local zed_app="${srcdir}/zed.app"
  local bindir="${pkgdir}/.local/bin"
  local appsdir="${pkgdir}/.local/share/applications"

  install -d "${pkgdir}/.local/zed.app" "$bindir" "$appsdir"
  cp -r "${zed_app}/." "${pkgdir}/.local/zed.app/"

  ln -s "../zed.app/bin/zed" "${bindir}/zed"

  local desktop="${appsdir}/dev.zed.Zed.desktop"
  cp "${zed_app}/share/applications/dev.zed.Zed.desktop" "$desktop"
  sed -i \
    -e "s|^Icon=zed$|Icon=${HOME}/.local/zed.app/share/icons/hicolor/512x512/apps/zed.png|" \
    -e "s|Exec=zed|Exec=${HOME}/.local/zed.app/bin/zed|g" \
    -e "s|^TryExec=zed$|TryExec=${HOME}/.local/zed.app/bin/zed|" \
    "$desktop"
}
