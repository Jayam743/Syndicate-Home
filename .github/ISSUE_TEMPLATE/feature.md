---
name: Feature
about: Propose a feature or unit of work for the Syndicate
title: ""
labels: ""
assignees: ""
---

## Summary

<!-- What is this issue about? One or two sentences. -->

## Details

<!-- Context, acceptance criteria, links. -->

## Paths (wave-fan eligibility)

List the file globs this issue will touch. These become the item's `paths[]` in a
campaign and drive the deterministic fan-vs-serialize decision (issue #8). Declaring
**disjoint** paths across related issues lets the campaign fan them out in parallel;
overlapping paths force safe serialization.

```
- src/example/**
- docs/example.md
```

## Mechanical work? (yes/no)

<!-- Answer "yes" ONLY for low-risk, mechanical work. Together with a non-empty
     Paths list, "yes" makes the item fan-eligible; otherwise it serializes. -->
