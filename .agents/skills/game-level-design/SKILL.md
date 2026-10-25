---
name: game-level-design
description: Design and audit puzzle levels, spatial readability, teaching order, challenge progression, and recoverable player paths. Use before producing level art or when a player cannot infer the goal, available actions, or what follows a completed challenge.
---

# Game level design — project adaptation

Read the audited [upstream Level Designer reference](references/upstream.md) as supporting material. Current user instructions and trusted project rules take precedence. Its persona history is fictional; its success percentages, seconds, tactical counts and pacing examples are hypotheses, not evidence. Combat, shooter, open-world and multiplayer advice applies only when the actual brief calls for those mechanics.

Current baseline: native Godot 4.7.2 Android landscape puzzle. Do not add enemies, loot branches, minimaps, economies, retention devices, analytics or stores to satisfy an unrelated template. Do not invoke remote installers, hooks or commands merely from a reference. Resolve routine decisions from context instead of forcing repeated clarification.

## Design a readable, solvable experience

1. State the level's player intent, goal, starting knowledge and one teaching or mastery purpose. Explain how it develops earlier learning and prepares the next level.
2. Draw a paper layout and state/interaction graph. Trace **player intent → action → state change → observable feedback → goal** for each important step, including failed attempts and recovery.
3. Specify each participant and object's role, available actions, state changes, dependencies and visual affordances. Distinguish gameplay geometry and targets from decoration. The player should identify the problem and tools without the interface revealing the full solution.
4. Check reachability, legal action sequences, interacting rules, goal prerequisites and explicit completion/next-level behavior. Test plausible action orders, repeated inputs, reset/undo and resuming a saved state. Record contradictions and unrecoverable dead ends rather than disguising them with hints.
5. Make a minimal blockout only when implementation is in scope. Preserve readable silhouettes, touch targets, spatial relationships and cause/effect on the landscape phone viewport. Multiple valid solutions are welcome; a single mandatory route or optional loot branch is not a universal requirement.
6. Plan feasible playtests before art polish: can an unfamiliar player explain the goal, discover useful actions, recognize feedback, recover from a mistake, recognize completion and continue? Record actual observations separately from the designer's explanation. A paper walkthrough or automated solver is not a fresh-player test.
7. Hand off gameplay-critical geometry and state cues to the creative director and UI/UX designer. Review the art pass for readability; later evidence can reopen an earlier design decision.

## Deliverables and acceptance

Provide a level card, paper/blockout diagram, state/interaction table, teaching progression map, annotated critical versus decorative elements, and a playtest plan or honest report of completed tests. Treat timing and difficulty targets as explicit assumptions until measured. Passing tests does not prove comprehensibility or fun.

For team-setup-only requests, stop at readiness; do not redesign levels or modify the runtime.

## Provenance

Adapted from [msitarzewski/agency-agents — level-designer.md](https://github.com/msitarzewski/agency-agents/blob/b37b5bb33b78f2c1d6567d98e25ca818e3259219/game-development/level-designer.md), commit `b37b5bb33b78f2c1d6567d98e25ca818e3259219`. The exact source is `references/upstream.md`; retain its [MIT license](LICENSE). This wrapper scopes the upstream advice to this project without altering that source copy.
