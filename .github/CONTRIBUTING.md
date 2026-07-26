<div align="center">

# Contributing to Ubuntu Cleanup

**Thank you for considering contributing to the Ubuntu Cleanup!**

<img src="https://img.shields.io/badge/version-3.0.0-blue?style=flat-square" alt="Version">
<img src="https://img.shields.io/badge/license-OSL--3.0-green?style=flat-square" alt="License">
<a href="https://www.basantmandal.in/"><img src="https://img.shields.io/badge/Website-000?style=flat-square&logo=ko-fi&logoColor=white" alt="Website"></a>
<a href="https://www.linkedin.com/in/basantmandal/"><img src="https://img.shields.io/badge/LinkedIn-0A66C2?style=flat-square&logo=linkedin&logoColor=white" alt="LinkedIn"></a>
<a href="mailto:support@basantmandal.in"><img src="https://img.shields.io/badge/Email-support%40basantmandal.in-blue?style=flat-square&logo=gmail" alt="Email"></a>

</div>

---

## 👋 Introduction

Welcome to the **Ubuntu Cleanup** contributing guide! This is a single Bash script (`modular_cleanup_script.sh`) that automates disk cleanup on Ubuntu and Debian-based systems — cleaning APT caches, systemd journals, Docker artifacts, developer tool caches, Python bytecode, and more.

---

## 🐛 Reporting Bugs

Before creating bug reports, please check [existing issues](https://github.com/basantmandal/ubuntu-cleanup/issues) to avoid duplicates.

**When creating a bug report, please include:**

- **Ubuntu/Debian version** and **Bash version** (`bash --version`)
- **Clear steps to reproduce** the behavior
- **Expected behavior** vs **actual behavior**
- **Full terminal output** including any error messages
- **Whether the issue occurs with or without `--dry-run`**

> 💡 **Tip:** Use our [Bug Report Template](../.github/ISSUE_TEMPLATE/bug_report.yml) when creating an issue for a structured report.

---

## 💡 Suggesting Enhancements

Enhancement suggestions are welcome! When suggesting a feature:

- **Use a clear and descriptive title**
- **Provide a detailed description** of the proposed functionality
- **Explain why this enhancement would be useful**
- **Include examples or mockups** if possible
- **Note any new dependencies** the feature would require

---

## 🛠️ Pull Requests

### Process

1. **Fork the repository** and create your branch from `main`
2. **Make your changes** following the coding standards below
3. **Test your changes** using `sudo bash modular_cleanup_script.sh --dry-run`
4. **Submit a Pull Request** with a clear description of changes

### PR Requirements

- [ ] Code follows the project's Bash coding standards (see below)
- [ ] Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) specification
- [ ] Changes are tested with `sudo bash modular_cleanup_script.sh --dry-run` and do not introduce errors
- [ ] New cleanup functions use the `run_cmd` wrapper (not bare commands)
- [ ] No breaking changes without a major version bump

### Commit Message Format

This project uses **Conventional Commits** for automated release via [semantic-release](https://semantic-release.gitbook.io/). The release workflow is defined in `.github/workflows/release.yml` and configured via `.releaserc.json`.

```text
type(scope): description

[optional body]

[optional footer]
```

**Types** (from `.releaserc.json`):

| Type   | Release Effect | Description          |
| ------ | -------------- | -------------------- |
| `feat` | minor          | New feature          |
| `fix`  | patch          | Bug fix              |
| `perf` | patch          | Performance improvement |
| `docs` | patch          | Documentation changes |
| `chore`| no release     | Maintenance tasks    |
| `refactor` | no release | Code refactoring     |
| `test` | no release     | Adding or updating tests |

---

## 🧑‍💻 Coding Standards

### Bash Style

- Shebang: `#!/bin/bash`
- The script uses `set -euo pipefail` and `IFS=$'\n\t'` for strict error handling — preserve these
- All destructive operations must go through the `run_cmd()` wrapper to support `--dry-run`
- Use `|| true` on `find -delete` and `rm -rf` calls to prevent script exit on permission errors
- Use the project's logging functions: `log()`, `clean()`, `skip()`, `warn()`
- Check optional tool availability with `command -v <tool> >/dev/null 2>&1` before using it

### Linting

There is no project-level shellcheck config. Run shellcheck on your changes before submitting:

```bash
shellcheck modular_cleanup_script.sh
```

### Adding New Cleanup Functions

1. Define a `run_cmd`-based function (e.g., `cleanup_example()`)
2. Call it from the `main()` function
3. If it depends on an optional tool, guard it with `command -v`
4. If it operates on a configurable path, define a variable in the `# CONFIG` section

---

## 📚 Additional Resources

- [Conventional Commits](https://www.conventionalcommits.org/)
- [semantic-release](https://semantic-release.gitbook.io/)
- [ShellCheck](https://www.shellcheck.net/)

---

<div align="center">
  <b>Basant Mandal</b><br>
  <a href="https://www.basantmandal.in/"><img src="https://img.shields.io/badge/Website-000?style=flat-square&logo=ko-fi&logoColor=white" alt="Website"></a>
  <a href="https://www.linkedin.com/in/basantmandal/"><img src="https://img.shields.io/badge/LinkedIn-0A66C2?style=flat-square&logo=linkedin&logoColor=white" alt="LinkedIn"></a>
  <a href="mailto:support@basantmandal.in"><img src="https://img.shields.io/badge/Email-support%40basantmandal.in-blue?style=flat-square&logo=gmail" alt="Email"></a>

  ---
</div>
