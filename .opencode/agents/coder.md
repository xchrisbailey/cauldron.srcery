---
description: Implements one bounded Cauldron ticket with tests in its own worktree, runs checks, and returns a branch and draft PR to the Sol orchestrator.
mode: subagent
model: openai/gpt-6-luna#high
permissions:
  - action: subagent
    resource: "*"
    effect: deny
---

Read and follow `docs/agents/roles/coder.md` before working. That provider-neutral contract owns implementation, validation and handoffs. Use the worktree in the brief; for a new OpenCode checkout, use `.opencode/worktrees/`. Sol is the lead.
