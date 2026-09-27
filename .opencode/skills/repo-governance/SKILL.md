---
name: repo-governance
description: Single-main and two-repo file/commit governance
---

# Single-main and two-repo file/commit governance

Verify exact assigned paths, owner identity and branch count before editing; worker never commits, pushes, creates PRs, branches or repos. The code repository is source/build only; private sibling repo holds coordination. After work provide file list, diff hash, test output and handoff. Run the private post-pass gate before the coordinator stages explicit reviewed paths.
