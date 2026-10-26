# Shared actor / observer context correction

The first retest's images 0015–0016 selected Marfa's illustrated body and
opened a generic fixed-object explanation. The rendering definition explicitly
shares that actor body with observer `w1`; requiring a precise eye-pin tap made
the visible instruction to check Marfa's view difficult to follow.

The correction was prepared and validated in the separate
`GOD-ux051-observers` worktree. It was not silently applied to the still-running
first Player session.

- Actor-to-observer association reads the explicit
  `presentation.observer_actor_id` and matching character asset.
- The actor's action menu exposes `ObjectView_w1` / “Check view”. It also keeps
  legitimate actor route actions during application.
- The view action sets only presentation inspection/selection. It does not
  dispatch game commands, move Marfa, assign a route or toggle an already visible
  inspection off. Read-only inspection remains available during an active check.

Validation after the manager's worktree import:

```text
NATIVE POINTER UI: 93 checks; 0 failures; 136 pointer events
```

The added regression actually clicks Marfa's body, opens Actions, chooses the
view and confirms witness inspection plus unchanged state hash, position and
routes. A second context check after recording the law confirms that view and
route actions coexist. The complete L01→L02 pointer journey and prior UI cases
also passed. Exit code 0; zero engine error / resource-leak lines.

Runtime before/after the targeted run:
`b61f531c136fa30d5e67b8df83f29e2011c49b786bf5d7d7ecdcf5b2d1ee2f15`.

This is a known-fixture native pointer regression, not a fresh-player passage or
physical Android test. The earlier Player observations remain evidence of the
prior source revision; the manager coordinates the final frozen gate and build.
