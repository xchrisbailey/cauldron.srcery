---
description: Verifies a Cauldron PR's exact head with local checks and performs merged-branch or worktree cleanup only when explicitly requested; no code edits or merges.
mode: subagent
model: openai/gpt-5.6-terra#low
permissions:
  - action: edit
    resource: "*"
    effect: deny
  - action: subagent
    resource: "*"
    effect: deny
---

Read and follow `docs/agents/roles/shepherd.md` before verification or cleanup. That provider-neutral contract preserves dirty worktrees and separates checkout removal from authorized branch deletion. Return evidence to Sol.
