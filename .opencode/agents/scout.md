---
description: Fast read-only Cauldron lookups with paths, reusable services and types, related tickets, and explicit gaps; no edits or design decisions.
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

Read and follow `docs/agents/roles/scout.md` before looking up facts. That provider-neutral contract owns the lookup and reporting workflow. Return facts to the parent; Sol owns their interpretation.
