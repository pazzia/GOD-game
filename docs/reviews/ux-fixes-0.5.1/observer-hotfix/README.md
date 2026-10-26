# Witness inspection hotfix

CI found that selecting the first single-view observer implicitly entered witness
placement. A tap on the next observer consequently produced placement_invalid.
The stage now requires placement_entity == selected for witness movement, just
as it already does for props. The UI can still assign witness positions through
its existing menu.

An isolated A/B copy reproduced the unchanged touch suite: 14 checks, two failures
(w2/w3), 30 native events before; 14 checks, no failures, the same30 events after
the one-line fix. The primary player worktree was not changed.

After the manager's one import of the new worktree, its actual suites passed:
Touch14/0/30 events, Stage Targets34/0/12 clicks, Input Edges7/0/9 events.
No engine errors or leak lines occurred. The touch assertions were not changed.
The added stage regression covers sequential inspection of three single-view
observers, explicit witness placement, and returning to inspection after cancel.

[Structured result](verification.json), [touch](touch.log),
[stage targets](targets.log), [input edges](edges.log),
[A/B baseline](isolated-touch-baseline.log), [A/B fixed](isolated-touch-fixed.log).
This is native headless input dispatch, not a physical phone test.
