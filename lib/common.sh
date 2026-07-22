#!/usr/bin/env bash
# Shared helpers for the StarMade-Pelican setup scripts. Sourced, not executed.
# Requires bash 4+.

# ── Output ─────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
  C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_BLU=$'\033[36m'; C_BOLD=$'\033[1m'
else
  C_RESET=; C_DIM=; C_RED=; C_GRN=; C_YEL=; C_BLU=; C_BOLD=
fi

log()   { printf '%s\n' "${C_BLU}==>${C_RESET} $*"; }
ok()    { printf '%s\n' "${C_GRN}  ✓${C_RESET} $*"; }
warn()  { printf '%s\n' "${C_YEL}  !${C_RESET} $*" >&2; }
err()   { printf '%s\n' "${C_RED} ✗${C_RESET} $*" >&2; }
die()   { err "$*"; exit 1; }
hr()    { printf '%s\n' "${C_DIM}────────────────────────────────────────────────────────${C_RESET}"; }

# ── Prompts ────────────────────────────────────────────────────────────────────
# ask VAR "Prompt" "default"
ask() {
  local __var="$1" __prompt="$2" __default="${3:-}" __reply
  if [ "${ASSUME_YES:-0}" = "1" ] && [ -n "$__default" ]; then
    printf -v "$__var" '%s' "$__default"; return
  fi
  if [ -n "$__default" ]; then
    read -r -p "$(printf '%s [%s]: ' "$__prompt" "$__default")" __reply || true
  else
    read -r -p "$(printf '%s: ' "$__prompt")" __reply || true
  fi
  printf -v "$__var" '%s' "${__reply:-$__default}"
}

# ask_secret VAR "Prompt" — no echo, no default.
ask_secret() {
  local __var="$1" __prompt="$2" __reply
  read -r -s -p "$(printf '%s: ' "$__prompt")" __reply || true
  printf '\n'
  printf -v "$__var" '%s' "$__reply"
}

# confirm "Question" [default y|n] — returns 0 for yes.
confirm() {
  local q="$1" def="${2:-n}" reply
  [ "${ASSUME_YES:-0}" = "1" ] && return 0
  local hint="[y/N]"; [ "$def" = "y" ] && hint="[Y/n]"
  read -r -p "$(printf '%s %s ' "$q" "$hint")" reply || true
  reply="${reply:-$def}"
  case "$reply" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# ── Environment ────────────────────────────────────────────────────────────────
require_cmd() { command -v "$1" >/dev/null 2>&1; }

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    if require_cmd sudo; then SUDO="sudo"; else die "This step needs root. Re-run as root or install sudo."; fi
  else
    SUDO=""
  fi
}

detect_os() {
  OS_ID=""; OS_VER=""; OS_LIKE=""
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"; OS_VER="${VERSION_ID:-}"; OS_LIKE="${ID_LIKE:-}"
  fi
}

is_debian_like() {
  detect_os
  case "$OS_ID $OS_LIKE" in *debian*|*ubuntu*) return 0 ;; *) return 1 ;; esac
}

# Best-effort public IPv4 of this host. Echoes the IP, or nothing if it can't be
# determined (offline, IPv6-only, etc.). Used to prefill the panel URL so a
# hand-typed IP (and its typos) isn't the only option.
detect_public_ip() {
  local ip svc
  for svc in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
    ip="$(curl -4 -fsS --max-time 5 "$svc" 2>/dev/null | tr -d '[:space:]')"
    case "$ip" in
      '' | *[!0-9.]*) ip="" ;;             # require a bare IPv4
      *) printf '%s' "$ip"; return 0 ;;
    esac
  done
  return 0
}

# ── Answers file (repeatable / non-interactive runs) ───────────────────────────
# Values are written as KEY='value'. Secrets are only persisted when the user
# opts in. The file lives in the repo and is git-ignored.
ANSWERS_FILE="${ANSWERS_FILE:-}"

load_answers() {
  local f="$1"
  [ -n "$f" ] && [ -f "$f" ] || return 0
  # shellcheck disable=SC1090
  . "$f"
  ok "Loaded answers from $f"
}

save_answer() {
  # save_answer FILE KEY VALUE
  local f="$1" k="$2" v="$3"
  [ -n "$f" ] || return 0
  touch "$f"; chmod 600 "$f"
  # Drop any prior line for this key, then append.
  grep -vE "^${k}=" "$f" > "${f}.tmp" 2>/dev/null || true
  mv "${f}.tmp" "$f"
  printf "%s=%q\n" "$k" "$v" >> "$f"
}
