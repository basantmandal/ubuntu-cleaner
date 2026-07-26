<!-- Please ensure your PR title follows Conventional Commits: type(scope): description -->

## 📝 Description

<!-- Describe your changes in detail. Explain why these changes are necessary. -->

---

## 🔗 Related Issues

<!-- If this PR fixes an open issue, link it here: Fixes #123 -->

---

## 📋 Type of Change

<!-- Check the relevant options -->

- [ ] 🐛 Bug fix (non-breaking change which fixes an issue)
- [ ] ✨ New feature (non-breaking change which adds functionality)
- [ ] 💥 Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] 📚 Documentation (updates to README or other markdown files)

---

## 🧪 How Has This Been Tested?

<!-- Describe the tests you ran to verify your changes. Provide instructions so we can reproduce. -->

- [ ] Tested locally on Ubuntu/Debian version:
- [ ] Verified via `sudo bash modular_cleanup_script.sh --dry-run` — no errors
- [ ] Ran `shellcheck modular_cleanup_script.sh` — no new warnings

---

## ✅ Checklist

<!-- Go over all the following points, and put an `x` in all the boxes that apply. -->

- [ ] My code follows the project's Bash coding standards (`set -euo pipefail`, `run_cmd` wrapper for destructive operations)
- [ ] I have performed a self-review of my own code
- [ ] New cleanup functions are guarded with `command -v` for optional tools
- [ ] I have updated the documentation (if applicable)
- [ ] My changes generate no new errors or warnings
- [ ] My commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)
