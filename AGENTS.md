# Cauldron in OpenCode

Read `CLAUDE.md` for the project layout, commands and conventions. Its Claude-specific model assignments and agent-team mechanics are replaced by the OpenCode roles and handoffs below; its engineering and review rules still apply.

## Roles

| Agent | Model | Responsibility |
| --- | --- | --- |
| `orchestrator` | Sol, medium | Planning, delegation, cross-cutting work and final review (Opus equivalent) |
| `coder` | Luna, high | Bounded coding and tests (Sonnet equivalent) |
| `reviewer` | Luna, high | First-pass PR review (Sonnet equivalent) |
| `scout` | Terra, low | Read-only lookups (Haiku equivalent) |
| `shepherd` | Terra, low | Check runs and explicitly requested cleanup (Haiku equivalent) |
| `adversary` | Astra, high | Concrete failure scenarios (Fable equivalent) |

Definitions live in `.opencode/agents/`. They reuse the role instructions in `.claude/agents/` as the source of truth, with explicit OpenCode adaptations. Read the referenced role file before doing its work; treat its frontmatter as Claude configuration, not OpenCode settings.

## Handoffs

When delegating tickets, working on integration branches, stacking or merging PRs, or reviewing delegated work, read `docs/agents/orchestration.md`. In OpenCode, Sol takes every responsibility assigned there to Opus. Use OpenCode subagents rather than Claude teams: the parent dispatches work, receives reports, and relays findings to the same coder by continuing its session. Shared team tasks and teammate messaging are not required or assumed. Parallelize independent tickets only; keep dependent coding, review and verification in order.

Give each child a standalone brief with its ticket, scope, base, branch, worktree and required evidence. Use `.opencode/worktrees/<issue>-<slug>` instead of `.claude/worktrees/`. Preserve GitHub PRs and comments as the durable record. Only the orchestrator marks PRs ready, and merging still requires the user's authorization.
