# Cauldron in OpenCode

Read `CLAUDE.md` for project conventions. Shared role contracts live in `docs/agents/roles/`; OpenCode profiles select the models below.

## Roles

| Agent | Model | Responsibility |
| --- | --- | --- |
| `orchestrator` | Sol, medium | Planning, delegation, cross-cutting work and final review (Opus equivalent) |
| `coder` | Luna, high | Bounded coding and tests (Sonnet equivalent) |
| `reviewer` | Luna, high | First-pass PR review (Sonnet equivalent) |
| `scout` | Terra, low | Read-only lookups (Haiku equivalent) |
| `shepherd` | Terra, low | Check runs and explicitly requested cleanup (Haiku equivalent) |
| `adversary` | Astra, high | Concrete failure scenarios (Fable equivalent) |

Definitions live in `.opencode/agents/`. Each points directly to its provider-neutral role contract; Claude profiles use the same contracts.

## Handoffs

When delegating, integrating, stacking, reviewing or merging, read `docs/agents/orchestration.md` and `docs/agents/workflow.md`. Sol is the lead; use OpenCode subagent sessions and resume the same coder for fixes. Parallelize independent tickets, not dependent stages.

Give each child a standalone brief and explicit acceptance-criterion IDs. New OpenCode worktrees use `.opencode/worktrees/<issue>-<slug>`. The lead owns final validation and readiness; merging/pushing requires user authorization. Before release tags, follow the preflight in `docs/native/data-model.md`.
