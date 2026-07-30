_pkgname=dragon
pkgname=dragon-drop
pkgver=1.2.0
pkgrel=1
depends=('gtk3' 'make' 'gcc')
url='https://github.com/mwh/dragon'
source=("$pkgname-$pkgver.tar.gz::https://github.com/mwh/dragon/archive/v${pkgver}.tar.gz")
sha256sums=('9bda28e96d715c759c8a1db754bdfde5e7d83671e13cd25a892f6b5e29357994')

build() {
  cd "${srcdir}/${_pkgname}-${pkgver}"
  make NAME=${pkgname}
}

package() {
  install -d "${pkgdir}/.local/bin"
  install -D "${srcdir}/${_pkgname}-${pkgver}/dragon-drop" "${pkgdir}/.local/bin/dragon-drop"
}
