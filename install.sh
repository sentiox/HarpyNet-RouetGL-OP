#!/bin/sh
set -eu

VERSION="${HARPYNET_VERSION:-1.3.9.19}"
REF="${HARPYNET_REF:-v$VERSION}"
REPO="${HARPYNET_REPO:-sentiox/HarpyNet-RouetGL-OP}"
WORKDIR="/tmp/harpynet-gl-install.$$"
RUNTIME_PACKAGES="curl jq coreutils-base64 bind-dig kmod-nft-tproxy ca-bundle conntrack"
UI_REQUEST="${HARPYNET_UI:-auto}"
UI_KIND=""

info() {
	printf '\033[32;1m%s\033[0m\n' "$*" >&2
}

warn() {
	printf '\033[33;1m%s\033[0m\n' "$*" >&2
}

fail() {
	printf '\033[31;1m%s\033[0m\n' "$*" >&2
	exit 1
}

cleanup() {
	if [ -n "$WORKDIR" ] && [ -d "$WORKDIR" ]; then
		rm -rf "$WORKDIR"
	fi
	return 0
}
trap cleanup EXIT INT TERM

download() {
	local url="$1"
	local out="$2"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$url" -o "$out"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$out" "$url"
	else
		fail "Install curl or wget first"
	fi
}

extract_tarball() {
	local archive="$1"
	local dest="$2"
	if tar -xzf "$archive" -C "$dest" 2>/dev/null; then
		return 0
	fi
	fail "Could not extract repository archive"
}

package_manager() {
	if command -v apk >/dev/null 2>&1; then
		echo apk
	elif command -v opkg >/dev/null 2>&1; then
		echo opkg
	else
		fail "No supported package manager found: install apk or opkg first"
	fi
}

package_installed() {
	local manager="$1"
	local pkg="$2"
	if [ "$manager" = "apk" ]; then
		apk info -e "$pkg" >/dev/null 2>&1
	else
		opkg list-installed "$pkg" >/dev/null 2>&1
	fi
}

install_runtime_packages() {
	local manager=""
	local missing=""
	local pkg=""

	manager="$(package_manager)"
	for pkg in $RUNTIME_PACKAGES; do
		if ! package_installed "$manager" "$pkg"; then
			missing="$missing $pkg"
		fi
	done

	if [ -z "$missing" ]; then
		info "Runtime packages already installed"
		return 0
	fi

	info "Installing HarpyNet runtime packages:$missing"
	if [ "$manager" = "apk" ]; then
		apk update || warn "apk update failed, trying apk add anyway"
		apk add $missing || fail "Could not install required packages:$missing"
	else
		opkg update || warn "opkg update failed, trying opkg install anyway"
		opkg install $missing || fail "Could not install required packages:$missing"
	fi
}

install_mihomo() {
	if command -v mihomo >/dev/null 2>&1 && mihomo -v >/dev/null 2>&1; then
		info "Mihomo already installed: $(mihomo -v | head -n 1)"
		return 0
	fi

	local machine=""
	local arch=""
	local release_json="/tmp/harpynet-mihomo-release.$$"
	local archive="/tmp/harpynet-mihomo.gz.$$"
	local tag=""
	local asset=""
	local url=""
	local digest=""
	local actual=""

	machine="$(uname -m)"
	case "$machine" in
		aarch64|arm64) arch="arm64" ;;
		armv7l|armv7) arch="armv7" ;;
		armv6l|armv6) arch="armv6" ;;
		x86_64|amd64) arch="amd64" ;;
		i386|i486|i586|i686) arch="386" ;;
		*) fail "Unsupported Mihomo architecture: $machine" ;;
	esac

	info "Downloading current Mihomo for linux-$arch..."
	download "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" "$release_json"
	tag="$(jq -r '.tag_name // empty' "$release_json")"
	[ -n "$tag" ] || fail "Could not determine the current Mihomo release"
	asset="mihomo-linux-${arch}-${tag}.gz"
	url="$(jq -r --arg name "$asset" '.assets[] | select(.name == $name) | .browser_download_url' "$release_json" | head -n 1)"
	digest="$(jq -r --arg name "$asset" '.assets[] | select(.name == $name) | (.digest // empty)' "$release_json" | head -n 1)"
	[ -n "$url" ] || fail "Mihomo release does not contain $asset"

	download "$url" "$archive"
	if [ -n "$digest" ] && [ "${digest#sha256:}" != "$digest" ] && command -v sha256sum >/dev/null 2>&1; then
		actual="$(sha256sum "$archive" | awk '{print $1}')"
		[ "$actual" = "${digest#sha256:}" ] || fail "Mihomo checksum verification failed"
	fi

	gzip -dc "$archive" > /usr/bin/mihomo
	chmod 0755 /usr/bin/mihomo
	rm -f "$release_json" "$archive"
	mihomo -v >/dev/null 2>&1 || fail "Installed Mihomo binary does not start"
	info "Installed $(mihomo -v | head -n 1)"
}

find_repo_root() {
	local base="$1"
	find "$base" -maxdepth 2 -type f -name install.sh -exec dirname {} \; | head -n 1
}

prepare_source() {
	if [ -f ./harpynet/files/usr/bin/harpynet ] && \
		[ -f ./harpynet-gl-ui/files/www/views/gl-sdk4-ui-harpynet.common.js ] && \
		[ -f ./luci-app-harpynet/htdocs/harpynet/index.html ]; then
		pwd
		return 0
	fi

	mkdir -p "$WORKDIR"
	local archive="$WORKDIR/source.tar.gz"
	local root=""

	info "Downloading HarpyNet GL $REF..."
	if ! download "https://codeload.github.com/$REPO/tar.gz/refs/tags/$REF" "$archive"; then
		warn "Tag $REF is not available yet, falling back to main"
		download "https://codeload.github.com/$REPO/tar.gz/refs/heads/main" "$archive"
	fi

	extract_tarball "$archive" "$WORKDIR"
	root="$(find_repo_root "$WORKDIR")"
	[ -n "$root" ] || fail "Repository archive has an unexpected layout"

	# A newly published installer can briefly be newer than the release tag it
	# references. Fall back to main only when that tag cannot provide the UI
	# selected for this router.
	if [ "$UI_KIND" = "luci" ] && [ ! -f "$root/luci-app-harpynet/htdocs/harpynet/index.html" ]; then
		warn "Tag $REF does not contain the LuCI interface yet, falling back to main"
		rm -rf "$WORKDIR"
		mkdir -p "$WORKDIR"
		archive="$WORKDIR/source.tar.gz"
		download "https://codeload.github.com/$REPO/tar.gz/refs/heads/main" "$archive"
		extract_tarball "$archive" "$WORKDIR"
		root="$(find_repo_root "$WORKDIR")"
		[ -n "$root" ] || fail "Main branch archive has an unexpected layout"
	fi
	echo "$root"
}

has_gl_ui() {
	[ -d /usr/share/oui/menu.d ] && [ -d /www/views ]
}

has_luci_ui() {
	[ -d /usr/share/luci/menu.d ] && [ -d /www/luci-static ]
}

choose_ui() {
	local has_gl=0
	local has_luci=0
	local choice=""

	has_gl_ui && has_gl=1
	has_luci_ui && has_luci=1

	case "$UI_REQUEST" in
		gl)
			[ "$has_gl" = "1" ] || fail "HARPYNET_UI=gl requested, but GL.iNet OUI was not detected"
			UI_KIND="gl"
			;;
		luci|openwrt)
			[ "$has_luci" = "1" ] || fail "HARPYNET_UI=luci requested, but LuCI was not detected"
			UI_KIND="luci"
			;;
		auto|"")
			if [ "$has_gl" = "1" ] && [ "$has_luci" = "0" ]; then
				UI_KIND="gl"
			elif [ "$has_gl" = "0" ] && [ "$has_luci" = "1" ]; then
				UI_KIND="luci"
			elif [ "$has_gl" = "1" ] && [ "$has_luci" = "1" ]; then
				printf '\nBoth web interfaces were detected:\n' >&2
				printf '  1) Native GL.iNet interface (recommended on GL.iNet firmware)\n' >&2
				printf '  2) LuCI interface (OpenWrt)\n' >&2
				if [ ! -t 0 ]; then
					fail "Interactive selection is unavailable. Run again with HARPYNET_UI=gl or HARPYNET_UI=luci"
				fi
				while :; do
					printf 'Choose interface [1/2]: ' >&2
					IFS= read -r choice || fail "Could not read interface selection"
					case "$choice" in
						1) UI_KIND="gl"; break ;;
						2) UI_KIND="luci"; break ;;
						*) warn "Enter 1 for GL.iNet or 2 for LuCI" ;;
					esac
				done
			else
				fail "Neither GL.iNet OUI nor LuCI was detected"
			fi
			;;
		*) fail "Unsupported HARPYNET_UI value: $UI_REQUEST (use auto, gl, or luci)" ;;
	esac

	info "Detected UI: $UI_KIND"
}

install_gl_ui() {
	local ui="$1"
	[ -f "$ui/www/views/gl-sdk4-ui-harpynet.common.js" ] || fail "HarpyNet GL UI files not found"

	info "Installing native GL.iNet UI..."
	mkdir -p \
		/usr/share/oui/menu.d /www/views /www/harpynet/icons /www/harpynet/flags \
		/usr/lib/oui-httpd/rpc /usr/lib /usr/libexec/rpcd \
		/usr/share/gl-validator.d /usr/share/rpcd/acl.d
	cp "$ui/usr/share/oui/menu.d/harpynet.json" /usr/share/oui/menu.d/harpynet.json
	cp "$ui/www/views/gl-sdk4-ui-harpynet.common.js" /www/views/gl-sdk4-ui-harpynet.common.js
	cp "$ui/www/harpynet/icons/"*.png /www/harpynet/icons/
	cp "$ui/www/harpynet/flags/"*.png /www/harpynet/flags/
	cp "$ui/usr/lib/oui-httpd/rpc/harpynet_gl" /usr/lib/oui-httpd/rpc/harpynet_gl
	cp "$ui/usr/lib/harpynet_direct_monitor.sh" /usr/lib/harpynet_direct_monitor.sh
	cp "$ui/usr/share/gl-validator.d/harpynet_gl.lua" /usr/share/gl-validator.d/harpynet_gl.lua
	cp "$ui/usr/libexec/rpcd/harpynet_gl" /usr/libexec/rpcd/harpynet_gl
	cp "$ui/usr/share/rpcd/acl.d/harpynet-gl.json" /usr/share/rpcd/acl.d/harpynet-gl.json
	chmod 0644 /usr/share/oui/menu.d/harpynet.json /www/views/gl-sdk4-ui-harpynet.common.js
	chmod 0644 /www/harpynet/icons/*.png /www/harpynet/flags/*.png
	chmod 0644 /usr/lib/oui-httpd/rpc/harpynet_gl /usr/share/gl-validator.d/harpynet_gl.lua
	chmod 0755 /usr/lib/harpynet_direct_monitor.sh /usr/libexec/rpcd/harpynet_gl
	chmod 0644 /usr/share/rpcd/acl.d/harpynet-gl.json
}

install_luci_ui() {
	local root="$1"
	local gl_ui="$2"
	local luci="$root/luci-app-harpynet"
	[ -f "$luci/htdocs/harpynet/index.html" ] || fail "HarpyNet LuCI files not found"

	info "Installing OpenWrt LuCI UI..."
	mkdir -p \
		/www/harpynet /www/harpynet/icons /www/harpynet/flags \
		/www/luci-static/resources/view/harpynet \
		/usr/share/luci/menu.d /usr/share/rpcd/acl.d /usr/libexec/rpcd /usr/lib
	cp "$luci/htdocs/harpynet/index.html" /www/harpynet/index.html
	cp "$luci/htdocs/harpynet/boot.js" /www/harpynet/boot.js
	cp "$luci/htdocs/harpynet/vue.min.js" /www/harpynet/vue.min.js
	cp "$gl_ui/www/harpynet/icons/"*.png /www/harpynet/icons/
	cp "$gl_ui/www/harpynet/flags/"*.png /www/harpynet/flags/
	cp "$luci/htdocs/luci-static/resources/view/harpynet/overview.js" \
		/www/luci-static/resources/view/harpynet/overview.js
	cp "$luci/root/usr/share/luci/menu.d/luci-app-harpynet.json" \
		/usr/share/luci/menu.d/luci-app-harpynet.json
	cp "$luci/root/usr/share/rpcd/acl.d/luci-app-harpynet.json" \
		/usr/share/rpcd/acl.d/luci-app-harpynet.json

	# Reuse the maintained GL component and RPC backend. LuCI boot.js provides
	# the small compatibility bridge around them.
	cp "$gl_ui/www/views/gl-sdk4-ui-harpynet.common.js" /www/harpynet/gl-component.js
	cp "$gl_ui/usr/libexec/rpcd/harpynet_gl" /usr/libexec/rpcd/harpynet_gl
	cp "$gl_ui/usr/lib/harpynet_direct_monitor.sh" /usr/lib/harpynet_direct_monitor.sh
	chmod 0644 /www/harpynet/index.html /www/harpynet/boot.js /www/harpynet/vue.min.js
	chmod 0644 /www/harpynet/icons/*.png /www/harpynet/flags/*.png
	chmod 0644 /www/harpynet/gl-component.js /www/luci-static/resources/view/harpynet/overview.js
	chmod 0644 /usr/share/luci/menu.d/luci-app-harpynet.json /usr/share/rpcd/acl.d/luci-app-harpynet.json
	chmod 0755 /usr/libexec/rpcd/harpynet_gl /usr/lib/harpynet_direct_monitor.sh
}

[ "$(id -u)" = "0" ] || fail "Run as root on the router"

choose_ui

ROOT="$(prepare_source)"
CORE="$ROOT/harpynet/files"
UI="$ROOT/harpynet-gl-ui/files"

[ -f "$CORE/usr/bin/harpynet" ] || fail "HarpyNet backend files not found"
[ -f "$UI/www/views/gl-sdk4-ui-harpynet.common.js" ] || fail "Shared HarpyNet UI component not found"

install_runtime_packages
install_mihomo

info "Installing HarpyNet backend $VERSION..."
mkdir -p /etc/init.d /etc/config /usr/bin /usr/lib/harpynet
cp "$CORE/etc/init.d/harpynet" /etc/init.d/harpynet
if [ ! -f /etc/config/harpynet ]; then
	cp "$CORE/etc/config/harpynet" /etc/config/harpynet
else
	warn "Keeping existing /etc/config/harpynet"
fi
cp "$CORE/usr/bin/harpynet" /usr/bin/harpynet
cp "$CORE/usr/lib/harpynet/"* /usr/lib/harpynet/
rm -f /usr/lib/harpynet/sing_box_config_facade.sh /usr/lib/harpynet/sing_box_config_manager.sh
rm -f /usr/lib/harpynet/harpynet/mihomo_backend.sh
rmdir /usr/lib/harpynet/harpynet 2>/dev/null || true
chmod 0755 /etc/init.d/harpynet /usr/bin/harpynet
chmod 0644 /usr/lib/harpynet/*

info "Preparing Mihomo GeoIP database..."
/usr/bin/harpynet prepare_geodata >/dev/null || fail "Could not prepare Mihomo GeoIP database"

if [ "$(uci -q get harpynet.settings.config_path)" = "/etc/sing-box/config.json" ]; then
	uci set harpynet.settings.config_path="/tmp/mihomo/config.yaml"
fi
if [ "$(uci -q get harpynet.settings.cache_path)" = "/etc/harpynet/cache.db" ]; then
	uci set harpynet.settings.cache_path="/etc/harpynet/mihomo-config.yaml"
fi
uci commit harpynet

if [ "$UI_KIND" = "gl" ]; then
	install_gl_ui "$UI"
else
	install_luci_ui "$ROOT" "$UI"
fi

info "Reloading services..."
if uci -q get dhcp.@dnsmasq[0] >/dev/null 2>&1; then
	uci -q set dhcp.@dnsmasq[0].logqueries='1'
	uci -q commit dhcp
	/etc/init.d/dnsmasq restart >/dev/null 2>&1 || warn "dnsmasq restart failed"
fi
/etc/init.d/harpynet enable >/dev/null 2>&1 || true
if [ -n "$(uci -q get harpynet.main.subscription_url)" ]; then
	/etc/init.d/harpynet restart >/dev/null 2>&1 || fail "HarpyNet failed to start with Mihomo"
	/usr/bin/harpynet wait_ready >/dev/null || fail "Mihomo did not become ready"
else
	/etc/init.d/harpynet stop >/dev/null 2>&1 || true
	info "HarpyNet is ready; add a subscription in the selected web interface to start Mihomo"
fi
/etc/init.d/rpcd restart >/dev/null 2>&1 || warn "rpcd restart failed"

if [ "$UI_KIND" = "gl" ]; then
	/etc/init.d/oui-httpd restart >/dev/null 2>&1 || \
		/etc/init.d/nginx reload >/dev/null 2>&1 || warn "OUI reload failed"
else
	rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
	/etc/init.d/uhttpd restart >/dev/null 2>&1 || warn "uHTTPd restart failed"
fi

info "Installation completed successfully ($UI_KIND UI)."
ROUTER_IP=""
if [ -n "${SSH_CONNECTION:-}" ]; then
	set -- $SSH_CONNECTION
	ROUTER_IP="${3:-}"
fi
if [ -z "$ROUTER_IP" ]; then
	ROUTER_IP="$(uci -q get network.lan.ipaddr 2>/dev/null || true)"
fi
ROUTER_IP="${ROUTER_IP%%/*}"
if [ -z "$ROUTER_IP" ]; then
	ROUTER_IP="$(ip -4 addr show br-lan 2>/dev/null | awk '/inet / { sub(/\\/.*/, "", $2); print $2; exit }')"
fi
if [ -n "$ROUTER_IP" ]; then
	if [ "$UI_KIND" = "gl" ]; then
		info "Open: http://$ROUTER_IP/#/harpynet"
	else
		info "Open: http://$ROUTER_IP/cgi-bin/luci/admin/services/harpynet"
	fi
else
	if [ "$UI_KIND" = "gl" ]; then
		info "Open HarpyNet from the VPN section of the stock GL.iNet UI"
	else
		info "Open HarpyNet from LuCI: Services -> HarpyNet"
	fi
fi
