#!/usr/bin/env bash
# Shared helpers for the Arkade Wallet Stack scripts. Meant to be sourced:
#   . "$(dirname "$0")/scripts/lib.sh"

# --- output helpers ----------------------------------------------------------
if [ -t 1 ]; then
	_C_RESET=$'\033[0m'; _C_RED=$'\033[31m'; _C_GRN=$'\033[32m'
	_C_YEL=$'\033[33m'; _C_BLU=$'\033[34m'
else
	_C_RESET=''; _C_RED=''; _C_GRN=''; _C_YEL=''; _C_BLU=''
fi

log()  { printf '%s\n' "${_C_BLU}==>${_C_RESET} $*"; }
info() { printf '%s\n' "    $*"; }
ok()   { printf '%s\n' "${_C_GRN}[ok]${_C_RESET} $*"; }
warn() { printf '%s\n' "${_C_YEL}[warn]${_C_RESET} $*" >&2; }
die()  { printf '%s\n' "${_C_RED}[error] $*${_C_RESET}" >&2; exit 1; }

# --- environment helpers -----------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# run_priv <cmd...> : run as root directly, else via sudo, else fail.
run_priv() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	elif have sudo; then
		sudo "$@"
	else
		die "need root or sudo to run: $*"
	fi
}

# fetch <url> : print a URL's body to stdout using curl or wget.
fetch() {
	if have curl; then
		curl -fsSL "$1"
	elif have wget; then
		wget -qO- "$1"
	else
		die "need curl or wget to download $1"
	fi
}

# detect_os : sets OS_FAMILY (debian|rhel|arch|macos|unknown) and PKG.
# OS_FAMILY and PKG are outputs consumed by scripts that source this file.
# shellcheck disable=SC2034
detect_os() {
	OS_FAMILY=unknown; PKG=''
	case "$(uname -s 2>/dev/null || echo unknown)" in
		Darwin) OS_FAMILY=macos; PKG=brew; return 0 ;;
	esac
	if [ -r /etc/os-release ]; then
		# shellcheck disable=SC1091
		. /etc/os-release
		case "${ID:-}${ID_LIKE:-}" in
			*debian*|*ubuntu*)        OS_FAMILY=debian; PKG=apt-get ;;
			*rhel*|*fedora*|*centos*) OS_FAMILY=rhel;   PKG=dnf ;;
			*arch*)                   OS_FAMILY=arch;   PKG=pacman ;;
		esac
	fi
}

# --- secret generation (openssl preferred, /dev/urandom fallback) ------------
gen_hex() {
	local n=${1:-32}
	if have openssl; then openssl rand -hex "$n"
	else od -An -tx1 -N "$n" /dev/urandom | tr -d ' \n'; fi
}
gen_b64() {
	local n=${1:-24}
	if have openssl; then openssl rand -base64 "$n" | tr -d '\n'
	else head -c "$n" /dev/urandom | base64 | tr -d '\n'; fi
}

# --- interactive prompts -----------------------------------------------------
# confirm <question> [default Y|N] : returns 0 for yes.
confirm() {
	local q=$1 def=${2:-Y} ans hint='[Y/n]'
	[ "$def" = N ] && hint='[y/N]'
	printf '%s %s ' "$q" "$hint" >&2
	read -r ans || ans=''
	ans=${ans:-$def}
	case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# prompt_default <question> <default> : echoes the entered value or the default.
prompt_default() {
	local q=$1 def=$2 ans
	printf '%s [%s]: ' "$q" "$def" >&2
	read -r ans || ans=''
	printf '%s' "${ans:-$def}"
}
