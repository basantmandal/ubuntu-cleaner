# Ubuntu Cleaner

**A modular and efficient Bash script to securely reclaim disk space on Ubuntu, Debian, and Linux Mint — desktop or server.**

[![Version](https://img.shields.io/badge/version-3.0.0-blue.svg?style=flat-square)](#)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%2B-orange.svg?style=flat-square)](#)
[![Debian](https://img.shields.io/badge/Debian-11%2B-a80030.svg?style=flat-square)](#)
[![Bash](https://img.shields.io/badge/Bash-4.0%2B-green.svg?style=flat-square)](#)
[![License](https://img.shields.io/badge/license-OSL--3.0-blue.svg?style=flat-square)](https://github.com/basantmandal/ubuntu-cleaner/blob/main/LICENCE.txt)
[![Website](https://img.shields.io/badge/Website-basantmandal.in-6366f1?style=flat-square&logo=google-chrome&logoColor=white)](https://www.basantmandal.in/)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-basantmandal-0A66C2?style=flat-square&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/basantmandal/)
[![Email](https://img.shields.io/badge/Email-support%40basantmandal.in-ea4335?style=flat-square&logo=gmail&logoColor=white)](mailto:support@basantmandal.in)

---

## 📄 Overview

Ubuntu Cleaner is a modular Bash utility that automates the safe removal of system logs, package caches, development artifacts, and orphaned Docker resources — on Ubuntu Desktop, Ubuntu Server, Linux Mint, and other Debian-based distributions. It's built around a single entry point (`ubuntu-cleaner.sh`) with a dry-run mode that lets you preview every operation before anything is deleted.

---

## 🎯 Use Cases

- **Developers:** Clear accumulated caches from npm, Yarn, Docker, Python, and Android Studio toolchains.
- **SysAdmins:** Reclaim disk space on servers by rotating logs, vacuuming systemd journals, and pruning APT and Docker caches — safely, and on a cron schedule.
- **Everyday Desktop Users:** Recover disk space on Ubuntu or Linux Mint without hunting through system directories manually.

---

## 🚀 Features

| Feature | Details |
| --- | --- |
| 🗃️ **System Logs** | Vacuums the systemd journal (default: last 3 days, max 500 MB) and truncates rotated/oversized log files. |
| 📦 **APT Maintenance** | Removes orphaned dependencies, cleans package lists, and purges cached `.deb` archives. |
| 🐳 **Docker Prune** | Clears stopped containers, unused networks, dangling images, and builder caches. Unused volumes are pruned only on explicit opt-in. |
| 🧑‍💻 **Developer Caches** | Purges npm/Yarn/TypeScript caches above configurable thresholds and removes Python `__pycache__` directories. |
| 📱 **Android Caches** | Deletes AVD snapshots, Android Studio system caches, and Gradle caches (relevant on desktop installs; safely skipped on servers). |
| 📝 **Audit Logging** | Every run is tee'd to a timestamped logfile under `/var/log/ubuntu-cleaner/`, so cron runs stay auditable. |
| 🔒 **Single-Instance Locking** | A `flock`-based lock prevents two overlapping runs from racing on the same directories. |
| 🎚️ **Threshold-Aware Cron Runs** | `--min-free-pct` skips the whole run unless root filesystem usage is at/above a given percentage. |
| 🗑️ **Safe by Design** | Dry-run mode via `--dry-run`; destructive operations guarded through a `run_cmd` wrapper; volume pruning is off by default and requires explicit opt-in plus confirmation. |

---

## 🏗 Architecture

The script follows a single-file, function-per-task architecture:

```
┌─────────────────────────────────────────────┐
│  CONFIG (user-editable, or --config FILE)    │
│  DRY_RUN, PRUNE_VOLUMES, MIN_FREE_PCT,       │
│  JOURNAL_RETAIN_DAYS, cache size limits      │
├─────────────────────────────────────────────┤
│  ARG PARSING (--dry-run, --prune-volumes,    │
│  --yes, --min-free-pct, --config, --help)    │
├─────────────────────────────────────────────┤
│  ROOT CHECK → LOGGING → LOCKING              │
│  require_root, tee to timestamped logfile,   │
│  flock-based single-instance lock            │
├─────────────────────────────────────────────┤
│  UTILS (shared helpers)                      │
│  run_cmd, get_used_pct, get_used_space_kb    │
│  log / clean / skip / warn / err             │
├─────────────────────────────────────────────┤
│  CLEANUP FUNCTIONS (one per concern)         │
│  cleanup_journal, cleanup_logs, cleanup_apt  │
│  cleanup_temp, cleanup_crash, cleanup_docker │
│  cleanup_npm, cleanup_dev_caches, cleanup_   │
│  python, cleanup_android, cleanup_trash,     │
│  cleanup_thumbnails                          │
├─────────────────────────────────────────────┤
│  MAIN (orchestration, space accounting)      │
└─────────────────────────────────────────────┘
```

---

## 🧩 Components

### Config Variables (script-level defaults, overridable via `--config FILE`)

| Variable | Default | Purpose |
| --- | --- | --- |
| `DRY_RUN` | `false` | When `true`, all destructive commands are printed but not executed. |
| `PRUNE_VOLUMES` | `false` | Whether Docker volume pruning is included — off by default because volumes can hold unattached database data. |
| `ASSUME_YES` | `false` | Skip the interactive confirmation for volume pruning (needed for non-interactive/cron use with `--prune-volumes`). |
| `MIN_FREE_PCT` | `0` | Only run cleanup if root filesystem usage is at/above this percentage; `0` always runs. |
| `JOURNAL_RETAIN_DAYS` | `3` | Systemd journal log retention period. |
| `JOURNAL_MAX_SIZE` | `500M` | Hard cap on retained journal size. |
| `LOG_DIR` | `/var/log/ubuntu-cleaner` | Where timestamped run logs are written. |
| `LOCK_FILE` | `/var/run/ubuntu-cleaner.lock` | `flock` lock path preventing overlapping runs. |
| `NPM_CACHE_LIMIT_MB` / `NPX_CACHE_LIMIT_MB` / `YARN_CACHE_LIMIT_MB` / `TS_CACHE_LIMIT_MB` | `1024` / `400` / `800` / `400` | Only clean each cache once it exceeds this size. |
| `USER_HOME` | Resolved via `getent passwd "$SUDO_USER"`, falling back to `$HOME` | Target user home directory for per-user caches — resolved this way so it works for custom home paths, not just `/home/<user>`. |

### Command-Line Flags

| Flag | Purpose |
| --- | --- |
| `--dry-run` | Show what would be done, change nothing. |
| `--prune-volumes` | Opt in to pruning unused Docker volumes (destructive). |
| `--yes` | Skip the interactive confirmation for volume pruning (for cron/non-interactive use). |
| `--min-free-pct N` | Only run cleanup if root filesystem usage is ≥ N%. |
| `--config FILE` | Source a shell file to override any CONFIG variable above. |
| `-h`, `--help` | Show usage and exit. |

### Logging Helpers

| Function | Prefix | Purpose |
| --- | --- | --- |
| `log()` | `[INFO]` | Standard progress message. |
| `clean()` | `[CLEAN]` | Confirmation that a cleanup action ran. |
| `skip()` | `[SKIP]` | Indicates a step was skipped (e.g., tool not installed). |
| `warn()` | `[WARN]` | Non-fatal warning. |
| `err()` | `[ERROR]` | Fatal error, written to stderr. |

### Cleanup Functions

Each function is self-contained, uses `run_cmd` for destructive operations, and is guarded with `command -v` when targeting optional tools (currently Docker).

---

## 📦 Requirements

| Requirement | Supported Versions |
| --- | --- |
| Operating System | Ubuntu 20.04+, Debian 11+, Linux Mint 20+, or any compatible Debian-based derivative |
| Bash | Version 4.0 or higher (`set -euo pipefail` requires Bash ≥ 4.0) |
| Utilities | `flock` (util-linux, present by default on Ubuntu/Debian/Mint) for single-instance locking |
| Privileges | Root access (`sudo`) |

> ⚠ **Warning:** The script checks for root immediately after parsing arguments — it exits with a clear error before touching the filesystem if not run as root (or if `-h`/`--help` wasn't passed).

---

## ⚙️ Installation

```bash
git clone git@github.com:basantmandal/ubuntu-cleaner.git
cd ubuntu-cleaner
chmod +x ubuntu-cleaner.sh
```

---

## 🔧 Configuration

Either edit the variables in the `# CONFIG` section at the top of `ubuntu-cleaner.sh` directly, or keep the script untouched and pass `--config FILE` with a shell file that overrides the variables you need — the latter survives `git pull` updates cleanly. See [Config Variables](#config-variables-script-level-defaults-overridable-via---config-file) above for the full list and defaults.

Example config file (`/etc/ubuntu-cleaner.conf`):

```bash
JOURNAL_RETAIN_DAYS=7
MIN_FREE_PCT=80
NPM_CACHE_LIMIT_MB=2048
```

---

## Usage

**Preview what will be cleaned (safe):**

```bash
sudo ./ubuntu-cleaner.sh --dry-run
```

**Run the full cleanup:**

```bash
sudo ./ubuntu-cleaner.sh
```

**Cron-friendly run — only clean if root disk usage is at/above 80%, and prune Docker volumes without a prompt:**

```bash
sudo ./ubuntu-cleaner.sh --min-free-pct 80 --prune-volumes --yes
```

**Override defaults from a config file instead of editing the script:**

```bash
sudo ./ubuntu-cleaner.sh --config /etc/ubuntu-cleaner.conf
```

The script prints a summary of reclaimed disk space on completion:

```
========== Cleanup started: Sun Jul 26 10:00:00 UTC 2026 ==========
...
========== Cleanup finished: Sun Jul 26 10:00:15 UTC 2026 ==========
🎉 Disk space reclaimed: 2048 MB
```

---

## 🗄 Database Changes

Not applicable. The script operates exclusively on filesystem caches, logs, and container artifacts — no database is used or required.

---

## 📂 Project Structure

```
ubuntu-cleaner/
├── ubuntu-cleaner.sh             # Single entry point
├── LICENCE.txt                   # OSL-3.0 license
├── SECURITY.md                   # Security policy
├── .releaserc.json               # semantic-release configuration
├── .github/
│   ├── CONTRIBUTING.md           # Contribution guidelines
│   ├── PULL_REQUEST_TEMPLATE.md  # PR template
│   ├── ISSUE_TEMPLATE/
│   │   └── bug_report.yml        # Bug report form
│   └── workflows/
│       └── release.yml           # Automated release workflow
```

---

## ✅ Testing & CI

- **No formal test framework** exists in this repository.
- The `--dry-run` flag is the primary verification mechanism — run `sudo ./ubuntu-cleaner.sh --dry-run` to validate that changes do not introduce errors.
- [ShellCheck](https://www.shellcheck.net/) passes clean against the script; run `shellcheck ubuntu-cleaner.sh` before submitting changes.
- The only CI workflow (`.github/workflows/release.yml`) triggers semantic-release on pushes to `main`. It does not run tests or linting.

---

## 📈 Performance Considerations

- The script uses `find ... -delete` with `|| true` to avoid aborting on permission-denied directories.
- Threshold-based cleanup (e.g., npm cache only purged above 1 GB; npx/Yarn/TypeScript caches above configurable limits) prevents unnecessary I/O on small caches.
- Systemd journal vacuum is bounded by both time (`JOURNAL_RETAIN_DAYS=3`) and size (`JOURNAL_MAX_SIZE=500M`) to avoid a single large operation.
- `--min-free-pct` lets cron skip the entire run when disk usage is already comfortable, instead of doing needless work on every tick.

---

## 🔐 Security Considerations

- **Root requirement:** The script checks for root (`require_root()`) immediately after argument parsing — before creating the log directory or acquiring the lock — because system directories (`/var/log`, `/var/lib/apt`, systemd journal) require elevated privileges.
- **Dry-run isolation:** All destructive commands pass through `run_cmd()`, which prints the command without executing when `DRY_RUN=true`.
- **Opt-in destructive actions:** Docker volume pruning is off by default (`PRUNE_VOLUMES=false`) and, even when enabled, prompts for interactive confirmation unless `--yes` is explicitly passed — volumes often hold unattached database data.
- **Single-instance locking:** A `flock`-based lock (`LOCK_FILE`) prevents two overlapping runs from racing on the same directories.
- **No telemetry:** The script makes no network calls and does not collect or transmit data.
- **`set -euo pipefail`:** Strict error handling prevents silent failures.

---

## Compatibility

| Platform | Status |
| --- | --- |
| Ubuntu 20.04 LTS (Desktop & Server) | Compatible |
| Ubuntu 22.04 LTS (Desktop & Server) | Compatible |
| Ubuntu 24.04 LTS (Desktop & Server) | Compatible |
| Linux Mint 20 / 21 / 22 | Compatible |
| Debian 11+ | Compatible |
| Pop!_OS and other Debian/Ubuntu derivatives | Compatible (expected) |
| Optional tools (Docker) | Cleanup performed only when the respective CLI is installed (`command -v` guard) |

---

## 🛠 Troubleshooting

| Symptom | Likely Cause | Solution |
| --- | --- | --- |
| `[ERROR] This script must be run as root (use sudo).` | Not executed with `sudo` | Run `sudo ./ubuntu-cleaner.sh` |
| `command not found: docker` | Docker not installed | Step is skipped automatically |
| No space reclaimed despite large caches | Running in `--dry-run` mode | Omit `--dry-run` for actual cleanup |
| Permission denied on certain directories | `find` encounters restricted paths | Expected on some system directories; these are skipped and logged, not fatal |
| `Another instance is already running` | A previous run is still active, or a stale lock file | Wait for the other run to finish, or remove `/var/run/ubuntu-cleaner.lock` if you're sure nothing holds it |

---

## 🤝 Contributing

Contributions are welcome. See [CONTRIBUTING.md](https://github.com/basantmandal/ubuntu-cleaner/blob/main/.github/CONTRIBUTING.md) for pull request guidelines, coding standards, and the commit message format.

---

## ⚖️ Disclaimer

The authors are not responsible for any accidental data loss, configuration resets, or system instability resulting from this script. Always review the code and use `--dry-run` prior to execution.

---

## 🤝 Support

For bug reports, feature requests, and general support:

- **Author**: Basant Mandal
- **Email**: <support@basantmandal.in>
- **Website**: <https://www.basantmandal.in>

---

## 📄 License

This project is licensed under the [OSL-3.0 License](https://github.com/basantmandal/ubuntu-cleaner/blob/main/LICENCE.txt).

---

**Basant Mandal**
*HK2 – Hash Tag Kitto*

[![Website](https://img.shields.io/badge/Website-basantmandal.in-6366f1?style=flat-square&logo=google-chrome&logoColor=white)](https://www.basantmandal.in/)
[![Email](https://img.shields.io/badge/Email-support%40basantmandal.in-ea4335?style=flat-square&logo=gmail&logoColor=white)](mailto:support@basantmandal.in)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-basantmandal-0A66C2?style=flat-square&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/basantmandal/)

---
