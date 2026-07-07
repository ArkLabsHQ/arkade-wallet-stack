#!/usr/bin/env bash
# Install the Arkade Wallet Stack prerequisites: git, Docker Engine, and the
# Docker Compose plugin. Idempotent and safe to re-run. Targets Linux servers.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

install_git() {
	if have git; then ok "git already installed"; return; fi
	log "Installing git..."
	case "$PKG" in
		apt-get) run_priv apt-get update -qq && run_priv apt-get install -y git ;;
		dnf)     run_priv dnf install -y git ;;
		pacman)  run_priv pacman -Sy --noconfirm git ;;
		*)       die "unsupported package manager; please install git manually" ;;
	esac
	ok "git installed"
}

install_docker() {
	if have docker; then
		ok "docker already installed"
	else
		log "Installing Docker Engine via https://get.docker.com ..."
		fetch https://get.docker.com | run_priv sh
		ok "docker installed"
	fi
	if docker compose version >/dev/null 2>&1; then
		ok "docker compose plugin present"
	else
		warn "docker compose plugin missing; attempting to install it"
		case "$PKG" in
			apt-get) run_priv apt-get install -y docker-compose-plugin ;;
			dnf)     run_priv dnf install -y docker-compose-plugin ;;
			*)       warn "install the docker compose plugin manually for your distro" ;;
		esac
	fi
}

enable_docker() {
	if have systemctl; then
		run_priv systemctl enable --now docker >/dev/null 2>&1 \
			|| warn "could not enable the docker service automatically"
	fi
}

add_user_to_docker_group() {
	local u=${SUDO_USER:-${USER:-}}
	[ -n "$u" ] && [ "$u" != root ] || return 0
	if getent group docker >/dev/null 2>&1; then
		if run_priv usermod -aG docker "$u" 2>/dev/null; then
			warn "added '$u' to the 'docker' group — log out/in (or run 'newgrp docker') to use docker without sudo"
		fi
	fi
}

main() {
	detect_os
	[ "$OS_FAMILY" = macos ] && die "this installer targets Linux servers; on macOS install Docker Desktop manually"
	[ "$OS_FAMILY" = unknown ] && warn "unrecognized OS; attempting a best-effort install"
	install_git
	install_docker
	enable_docker
	add_user_to_docker_group
	ok "prerequisites ready"
	docker --version 2>/dev/null || true
	docker compose version 2>/dev/null || true
}

main "$@"
