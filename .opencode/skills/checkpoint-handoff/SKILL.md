---
name: checkpoint-handoff
description: Loss-resistant OpenCode session checkpoints
---

# Loss-resistant OpenCode session checkpoints

Before compaction or exit write private handoff: actual model/session ID, current SHA, touched files, observed output, blockers, one next step. On resume reload CURRENT and source; compaction summary is subordinate to source documents. Never mark unknown test PASSED.
