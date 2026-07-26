#!/bin/bash
#
# ubuntu-cleaner.sh — Safe, production-ready disk cleanup for Ubuntu desktop & Ubuntu VPS hosts.
#
# WHY THIS EXISTS:
#   Long-running debian(Ubuntu, Linux mint, Ubuntu Server) based systems accumulate cruft (apt cache, docker layers, npm/yarn
#   caches, rotated logs, journald) that can silently eat disk until something
#   important fails to write. This script reclaims that space safely, with
#   explicit opt-in for anything destructive (like Docker volume pruning),
#   and logs everything so a cron run can be audited after the fact.
#
# USAGE:
#   sudo ./ubuntu-cleaner.sh [OPTIONS]
#
# OPTIONS:
#   --dry-run             Show what would be done, change nothing.
#   --prune-volumes       Allow pruning unused Docker volumes (DESTRUCTIVE —
#                          off by default; can delete unattached DB data etc).
#   --yes                 Skip the interactive confirmation for volume pruning
#                          (needed for non-interactive/cron use with --prune-volumes).
#   --min-free-pct N      Only run cleanup if root filesystem usage is >= N%.
#                          Useful for cron: "only bother if actually needed."
#   --config FILE         Source an optional shell config file to override
#                          any of the CONFIG variables below (e.g. thresholds).
#   -h, --help            Show this help and exit.
#
# EXIT CODES:
#   0  success (cleanup ran, or skipped because threshold not met)
#   1  bad usage / not run as root
#   2  another instance is already running (lock held)
#
set -euo pipefail
IFS=$'\n\t'

########################################
# CONFIG (override via --config FILE)
########################################
DRY_RUN=false
PRUNE_VOLUMES=false          # destructive — must be explicitly opted into
ASSUME_YES=false
MIN_FREE_PCT=0               # 0 = always run, regardless of current usage
JOURNAL_RETAIN_DAYS=3
JOURNAL_MAX_SIZE="500M"
LOG_DIR="/var/log/ubuntu-cleanup"
LOCK_FILE="/var/run/ubuntu-cleanup.lock"

# Cache size ceilings (MB) — only clean if the dir exceeds this size.
NPM_CACHE_LIMIT_MB=1024
NPX_CACHE_LIMIT_MB=400
YARN_CACHE_LIMIT_MB=800
TS_CACHE_LIMIT_MB=400

########################################
# RESOLVE THE TARGET USER'S HOME
########################################
# Why not just `${SUDO_USER:+/home/$SUDO_USER}`:
#   1. It hardcodes /home/<user>, which breaks for custom home paths.
#   2. If the script is invoked as true root (no `sudo`, e.g. a root cron
#      entry), SUDO_USER is unset and the old code fell back to $HOME=/root,
#      silently cleaning root's caches instead of the intended user's — with
#      no error, just wrong behavior.
# `getent passwd` gives the real home dir regardless of how root got here.
resolve_user_home() {
  if [[ -n "${SUDO_USER:-}" ]]; then
    local home
    home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [[ -n "$home" && -d "$home" ]]; then
      echo "$home"
      return
    fi
  fi
  echo "$HOME"
}
USER_HOME="$(resolve_user_home)"
NPM_CACHE_DIR="$USER_HOME/.npm/_cacache"

########################################
# ARG PARSING
########################################
print_usage() { grep '^#' "$0" | sed -n '2,30p' | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --prune-volumes) PRUNE_VOLUMES=true ;;
    --yes) ASSUME_YES=true ;;
    --min-free-pct) MIN_FREE_PCT="$2"; shift ;;
    --config)
      # Config file is sourced last-writer-wins so it can override any
      # CONFIG value above (e.g. per-host thresholds) without editing this file.
      CONFIG_FILE="$2"
      if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
      else
        echo "[ERROR] Config file not found: $CONFIG_FILE" >&2
        exit 1
      fi
      shift
      ;;
    -h|--help) print_usage; exit 0 ;;
    *) echo "[ERROR] Unknown option: $1" >&2; print_usage; exit 1 ;;
  esac
  shift
done

########################################
# ROOT CHECK
########################################
# Must happen before LOG_DIR is created below — otherwise a non-root user
# hits a raw "mkdir: Permission denied" instead of this clear message.
timestamp() { date "+%Y-%m-%d %H:%M:%S"; }
err()   { echo "[ERROR] $(timestamp) $1" >&2; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (use sudo)."
    exit 1
  fi
}
require_root

########################################
# LOGGING
########################################
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup-$(date +%Y%m%d-%H%M%S).log"
# Tee everything (stdout+stderr) to a timestamped logfile so cron runs are
# auditable after the fact, not just whatever cron mailed you (if anything).
exec > >(tee -a "$LOG_FILE") 2>&1

log()   { echo "[INFO]  $(timestamp) $1"; }
clean() { echo "[CLEAN] $(timestamp) $1"; }
skip()  { echo "[SKIP]  $(timestamp) $1"; }
warn()  { echo "[WARN]  $(timestamp) $1"; }

run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}

get_used_pct() {
  df -P / | awk 'NR==2 {gsub("%","",$5); print $5}'
}

get_used_space_kb() {
  df -k / | awk 'NR==2 {print $3}'
}

########################################
# LOCKING
########################################
# Prevents two overlapping runs (e.g. a slow `docker system prune` still in
# flight when the next cron tick fires) from racing on the same directories
# and producing corrupted before/after space accounting or partial cleans.
acquire_lock() {
  exec 200>"$LOCK_FILE"
  if ! flock -n 200; then
    err "Another instance is already running (lock: $LOCK_FILE). Exiting."
    exit 2
  fi
}

########################################
# CLEANUP FUNCTIONS
########################################

cleanup_journal() {
  log "Cleaning systemd journal (retain ${JOURNAL_RETAIN_DAYS}d, max ${JOURNAL_MAX_SIZE})"
  run_cmd journalctl --vacuum-time="${JOURNAL_RETAIN_DAYS}d"
  run_cmd journalctl --vacuum-size="$JOURNAL_MAX_SIZE"
}

cleanup_logs() {
  clean "Removing rotated logs (*.gz, *.1, *.old)"
  # `|| true`: expected to occasionally hit permission-denied subdirs; that's
  # not a reason to abort the whole run.
  run_cmd find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.old" \) -delete || true

  log "Truncating oversized logs (>100MB)"
  # truncate -s 0 preserves the inode, so processes with the file open for
  # writing keep working — safe to do live, unlike deleting the file.
  run_cmd find /var/log -type f -name "*.log" -size +100M -exec truncate -s 0 {} \; || true
}

cleanup_apt() {
  clean "Cleaning APT"
  # No `|| true` here on purpose: if apt itself is broken (locked, corrupted
  # cache), that's worth surfacing loudly rather than silently continuing.
  run_cmd apt clean
  run_cmd apt autoclean
  run_cmd apt autoremove --purge -y
  run_cmd rm -rf /var/lib/apt/lists/*
}

cleanup_temp() {
  clean "Cleaning /tmp and /var/tmp (files untouched >3 days)"
  run_cmd find /tmp -type f -atime +3 -delete || true
  run_cmd find /var/tmp -type f -atime +3 -delete || true
}

cleanup_crash() {
  clean "Removing crash dumps"
  run_cmd rm -rf /var/crash/* || true
}

cleanup_thumbnails() {
  clean "Cleaning thumbnail cache"
  run_cmd find "$USER_HOME/.cache/thumbnails" -type f -delete || true
}

cleanup_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    skip "Docker not installed"
    return
  fi

  clean "Cleaning Docker (containers, networks, dangling images, build cache)"
  run_cmd docker system prune -f
  run_cmd docker builder prune -f

  log "Unused (dangling) volumes present:"
  docker volume ls -f dangling=true

  if [ "$PRUNE_VOLUMES" = true ]; then
    # Volumes commonly hold database data directories or uploaded files that
    # are unattached only because a container was recreated, not because the
    # data is unwanted. Never do this silently in an unattended run.
    if [ "$ASSUME_YES" = false ] && [ -t 0 ]; then
      read -r -p "About to prune Docker volumes — this can permanently delete data. Continue? [y/N] " reply
      if [[ ! "$reply" =~ ^[Yy]$ ]]; then
        skip "Volume prune cancelled by user"
        return
      fi
    elif [ "$ASSUME_YES" = false ]; then
      warn "Non-interactive session and --yes not passed — skipping volume prune for safety."
      return
    fi
    clean "Pruning unused volumes"
    run_cmd docker volume prune -f
  else
    skip "Skipping volume prune (pass --prune-volumes to enable)"
  fi
}

clean_dir_if_large() {
  local dir_path="$1" name="$2" limit_mb="$3"

  if [ ! -d "$dir_path" ]; then
    skip "$name not found"
    return
  fi

  local size_mb
  size_mb=$(du -sm "$dir_path" | awk '{print $1}')

  if [ "$size_mb" -gt "$limit_mb" ]; then
    clean "Cleaning $name (${size_mb}MB > ${limit_mb}MB limit)"
    run_cmd rm -rf "${dir_path:?}"/*
  else
    skip "$name within limit (${size_mb}MB)"
  fi
}

cleanup_npm()        { clean_dir_if_large "$NPM_CACHE_DIR" "npm cache" "$NPM_CACHE_LIMIT_MB"; }
cleanup_dev_caches() {
  clean_dir_if_large "$USER_HOME/.npm/_npx" "npx cache" "$NPX_CACHE_LIMIT_MB"
  clean_dir_if_large "$USER_HOME/.cache/yarn" "yarn cache" "$YARN_CACHE_LIMIT_MB"
  clean_dir_if_large "$USER_HOME/.cache/typescript" "typescript cache" "$TS_CACHE_LIMIT_MB"
}

cleanup_python() {
  clean "Removing Python __pycache__ directories"
  run_cmd find "$USER_HOME" -type d -name "__pycache__" -exec rm -rf {} + || true
}

cleanup_android() {
  # Rarely relevant on a headless VPS (no Android Studio/emulator), but
  # harmless — nullglob means the loops simply do nothing if absent.
  clean "Cleaning Android caches (if present)"
  shopt -s nullglob
  for snapshot in "$USER_HOME/.android/avd"/*/snapshots; do
    run_cmd rm -rf "$snapshot"
  done
  for dir in "$USER_HOME/.AndroidStudio"*/system/caches; do
    run_cmd rm -rf "$dir"
  done
  shopt -u nullglob
  run_cmd rm -rf "$USER_HOME/.android/cache" || true
  run_cmd rm -rf "$USER_HOME/.gradle/caches" || true
}

cleanup_trash() {
  clean "Cleaning Trash"
  run_cmd rm -rf "$USER_HOME/.local/share/Trash"/* || true
}

########################################
# MAIN
########################################
main() {
  acquire_lock

  echo "========== Cleanup started: $(date) =========="
  log "Target user home: $USER_HOME"
  log "Dry run: $DRY_RUN | Prune volumes: $PRUNE_VOLUMES | Log: $LOG_FILE"

  if [ "$MIN_FREE_PCT" -gt 0 ]; then
    used_pct=$(get_used_pct)
    if [ "$used_pct" -lt "$MIN_FREE_PCT" ]; then
      log "Disk usage (${used_pct}%) below threshold (${MIN_FREE_PCT}%) — skipping cleanup."
      exit 0
    fi
    log "Disk usage (${used_pct}%) at/above threshold (${MIN_FREE_PCT}%) — proceeding."
  fi

  SPACE_BEFORE=$(get_used_space_kb)

  cleanup_journal
  cleanup_logs
  cleanup_apt
  cleanup_temp
  cleanup_crash
  cleanup_thumbnails
  cleanup_docker
  cleanup_npm
  cleanup_dev_caches
  cleanup_python
  cleanup_android
  cleanup_trash

  SPACE_AFTER=$(get_used_space_kb)
  SAVED_KB=$(( SPACE_BEFORE - SPACE_AFTER ))
  # Guard against a negative delta (e.g. something else wrote to disk mid-run)
  # rather than printing a nonsensical negative "space reclaimed" figure.
  if [ "$SAVED_KB" -lt 0 ]; then
    warn "Disk usage increased during cleanup (concurrent writes?) — reporting 0 saved."
    SAVED_KB=0
  fi

  echo "========== Cleanup finished: $(date) =========="

  if [ "$DRY_RUN" = true ]; then
    echo "💡 Dry-run completed. Run without --dry-run to reclaim space."
  elif [ "$SAVED_KB" -gt 0 ]; then
    SAVED_MB=$(( SAVED_KB / 1024 ))
    echo "🎉 Disk space reclaimed: ${SAVED_MB} MB"
  else
    echo "✨ Your system is already clean! No significant space was reclaimed."
  fi

  log "Full log saved to: $LOG_FILE"
}

main "$@"
