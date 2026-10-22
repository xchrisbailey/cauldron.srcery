---
description: Reviews a Cauldron draft PR against its ticket and house rules, posts findings, and returns a first-pass verdict to Sol without editing code.
mode: subagent
model: openai/gpt-6-luna#high
permissions:
  - action: edit
    resource: "*"
    effect: deny
  - action: subagent
    resource: "*"
    effect: deny
---

Read and follow `docs/agents/roles/reviewer.md` before reviewing. That provider-neutral contract owns the checklist, evidence and findings. Return findings to the parent; Sol owns the final verdict.
