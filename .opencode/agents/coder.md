---
description: Implements one bounded Cauldron ticket with tests in its own worktree, runs checks, and returns a branch and draft PR to the Sol orchestrator.
mode: subagent
model: openai/gpt-6-luna#high
permissions:
  - action: subagent
    resource: "*"
    effect: deny
---

Read `AGENTS.md` and `.claude/agents/coder.md` before working. Follow that role's instructions, treating Sol as the orchestrator and using `.opencode/worktrees/` for new worktrees. Ignore the source file's Claude frontmatter.

Use the normal report-back workflow, not its Claude agent-team section. Push and open the draft PR after the first commit so work survives a lost session, unless the brief specifies an integration branch. Return check evidence and blockers to the parent. The parent relays review findings and resumes your session for fixes; task-list updates and direct teammate messages are not required. Keep product and architecture questions with the parent.
