#!/bin/sh
set -eu

RELEASE_REPO="${HARPYNET_RELEASE_REPO:-sentiox/HarpyNet-RouetGL-OP}"
API_URL="https://api.github.com/repos/$RELEASE_REPO/releases/latest"
WORKDIR="/tmp/harpynet-public-install.$$"
UI_REQUEST="${HARPYNET_UI:-auto}"
UI_KIND=""
RUNTIME_PACKAGES="curl jq coreutils-base64 bind-dig kmod-nft-tproxy ca-bundle conntrack"

info() { printf '\033[32;1m%s\033[0m\n' "$*" >&2; }
warn() { printf '\033[33;1m%s\033[0m\n' "$*" >&2; }
fail() { printf '\033[31;1m%s\033[0m\n' "$*" >&2; exit 1; }

cleanup() {
	[ -d "$WORKDIR" ] && rm -rf "$WORKDIR"
}
trap cleanup EXIT INT TERM

download() {
	local url="$1" out="$2"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$url" -o "$out"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$out" "$url"
	else
		fail "Install curl or wget first"
	fi
}

package_manager() {
	if command -v apk >/dev/null 2>&1; then echo apk
	elif command -v opkg >/dev/null 2>&1; then echo opkg
	else fail "No supported package manager found"
	fi
}

package_installed() {
	if [ "$1" = apk ]; then apk info -e "$2" >/dev/null 2>&1
	else opkg list-installed "$2" >/dev/null 2>&1
	fi
}

install_runtime_packages() {
	local manager missing pkg
	manager="$(package_manager)"
	missing=""
	for pkg in $RUNTIME_PACKAGES; do
		package_installed "$manager" "$pkg" || missing="$missing $pkg"
	done
	[ -z "$missing" ] && return 0
	info "Installing runtime packages:$missing"
	if [ "$manager" = apk ]; then
		apk update || warn "apk update failed; trying installation"
		apk add $missing || fail "Could not install runtime packages"
	else
		opkg update || warn "opkg update failed; trying installation"
		opkg install $missing || fail "Could not install runtime packages"
	fi
}

install_mihomo() {
	command -v mihomo >/dev/null 2>&1 && mihomo -v >/dev/null 2>&1 && {
		info "Mihomo already installed: $(mihomo -v | head -n 1)"
		return 0
	}

	local machine arch json tag asset url archive digest actual
	machine="$(uname -m)"
	case "$machine" in
		aarch64|arm64) arch=arm64 ;;
		armv7l|armv7) arch=armv7 ;;
		armv6l|armv6) arch=armv6 ;;
		x86_64|amd64) arch=amd64 ;;
		i386|i486|i586|i686) arch=386 ;;
		*) fail "Unsupported Mihomo architecture: $machine" ;;
	esac

	json="$WORKDIR/mihomo.json"
	archive="$WORKDIR/mihomo.gz"
	download "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" "$json"
	tag="$(jq -r '.tag_name // empty' "$json")"
	asset="mihomo-linux-${arch}-${tag}.gz"
	url="$(jq -r --arg name "$asset" '.assets[] | select(.name == $name) | .browser_download_url' "$json" | head -n 1)"
	digest="$(jq -r --arg name "$asset" '.assets[] | select(.name == $name) | (.digest // empty)' "$json" | head -n 1)"
	[ -n "$url" ] || fail "Mihomo release does not contain $asset"
	download "$url" "$archive"
	if [ -n "$digest" ] && [ "${digest#sha256:}" != "$digest" ] && command -v sha256sum >/dev/null 2>&1; then
		actual="$(sha256sum "$archive" | awk '{print $1}')"
		[ "$actual" = "${digest#sha256:}" ] || fail "Mihomo checksum verification failed"
	fi
	gzip -dc "$archive" > /usr/bin/mihomo
	chmod 0755 /usr/bin/mihomo
	mihomo -v >/dev/null 2>&1 || fail "Installed Mihomo does not start"
}

has_gl_ui() { [ -d /usr/share/oui/menu.d ] && [ -d /www/views ]; }
has_luci_ui() { [ -d /usr/share/luci/menu.d ] && [ -d /www/luci-static ]; }

choose_ui() {
	local has_gl=0 has_luci=0 choice=""
	has_gl_ui && has_gl=1
	has_luci_ui && has_luci=1
	case "$UI_REQUEST" in
		gl) [ "$has_gl" = 1 ] || fail "GL.iNet OUI was not detected"; UI_KIND=gl ;;
		luci|openwrt) [ "$has_luci" = 1 ] || fail "LuCI was not detected"; UI_KIND=luci ;;
		auto|"")
			if [ -f /usr/share/oui/menu.d/harpynet.json ]; then UI_KIND=gl
			elif [ -f /usr/share/luci/menu.d/luci-app-harpynet.json ]; then UI_KIND=luci
			elif [ "$has_gl" = 1 ] && [ "$has_luci" = 0 ]; then UI_KIND=gl
			elif [ "$has_gl" = 0 ] && [ "$has_luci" = 1 ]; then UI_KIND=luci
			elif [ "$has_gl" = 1 ] && [ "$has_luci" = 1 ]; then
				[ -t 0 ] || fail "Set HARPYNET_UI=gl or HARPYNET_UI=luci"
				printf 'Choose interface: 1) GL.iNet  2) LuCI: ' >&2
				IFS= read -r choice
				case "$choice" in 1) UI_KIND=gl ;; 2) UI_KIND=luci ;; *) fail "Choose 1 or 2" ;; esac
			else fail "Neither GL.iNet OUI nor LuCI was detected"
			fi ;;
		*) fail "Unsupported HARPYNET_UI: $UI_REQUEST" ;;
	esac
	info "Selected interface: $UI_KIND"
}

asset_url() {
	local kind="$1" extension="ipk"
	[ "$(package_manager)" = apk ] && extension="apk"
	case "$kind" in
		core) jq -r '.assets[].browser_download_url // empty' "$WORKDIR/release.json" 2>/dev/null | awk '/\/harpynet-[0-9].*\.(ipk|apk)$/' ;;
		gl) jq -r '.assets[].browser_download_url // empty' "$WORKDIR/release.json" 2>/dev/null | awk '/\/harpynet-gl-ui-.*\.(ipk|apk)$/' ;;
		luci) jq -r '.assets[].browser_download_url // empty' "$WORKDIR/release.json" 2>/dev/null | awk '/\/luci-app-harpynet-.*\.(ipk|apk)$/' ;;
	esac | awk -v ext=".$extension" 'index($0, ext) == length($0) - length(ext) + 1 { print }' | head -n 1
}

install_package_file() {
	local manager="$1" file="$2"
	if [ "$manager" = apk ]; then apk add --allow-untrusted --network=false "$file"
	else opkg install --force-reinstall "$file"
	fi
}

install_release() {
	local manager core_url ui_url core_file ui_file tag
	manager="$(package_manager)"
	download "$API_URL" "$WORKDIR/release.json"
	tag="$(jq -r '.tag_name // empty' "$WORKDIR/release.json")"
	[ -n "$tag" ] || fail "No public HarpyNet release found"
	core_url="$(asset_url core)"
	ui_url="$(asset_url "$UI_KIND")"
	[ -n "$core_url" ] && [ -n "$ui_url" ] || fail "Обновление $tag найдено, но пакеты для $manager/$UI_KIND ещё не опубликованы. Попробуйте позже."
	core_file="$WORKDIR/$(basename "$core_url")"
	ui_file="$WORKDIR/$(basename "$ui_url")"
	info "Downloading HarpyNet $tag packages"
	download "$core_url" "$core_file"
	download "$ui_url" "$ui_file"
	install_package_file "$manager" "$core_file"
	install_package_file "$manager" "$ui_file"
}

[ "$(id -u)" = 0 ] || fail "Run as root on the router"
mkdir -p "$WORKDIR"
choose_ui
install_runtime_packages
install_mihomo
install_release
/usr/bin/harpynet prepare_geodata >/dev/null || fail "Could not prepare Mihomo GeoIP database"
/etc/init.d/harpynet enable >/dev/null 2>&1 || true
if [ -n "$(uci -q get harpynet.main.subscription_url 2>/dev/null || true)" ]; then
	/etc/init.d/harpynet restart >/dev/null 2>&1 || fail "HarpyNet failed to restart"
	/usr/bin/harpynet wait_ready >/dev/null || fail "Mihomo did not become ready"
fi
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
if [ "$UI_KIND" = gl ]; then
	/etc/init.d/oui-httpd restart >/dev/null 2>&1 || /etc/init.d/nginx reload >/dev/null 2>&1 || true
else
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
	/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
fi
info "HarpyNet $(/usr/bin/harpynet show_version) installed successfully ($UI_KIND UI)"
