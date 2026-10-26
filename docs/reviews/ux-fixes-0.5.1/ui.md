# UI corrections for the Player retest

Scope: `presentation/game.gd`, `presentation/theme.gd`, and corresponding
`test_ui.gd` / `test_layout.gd` regressions. Game rules, art assets and the
30-level campaign are unchanged by this part of the work.

## Implemented

- **PLR-003:** Plan opens with a read-only summary of real route assignments,
  attachment targets, route support conditions and actual goals. Assigned,
  running, waiting, stopped and completed routes are distinguished. Required
  supports use the kernel's declared route requirements, actual positions,
  effective capacity and combined assigned load. Direct actor/attachment
  editing remains available; opening the summary changes no game state.
- **PLR-007:** Pause has visible Settings, Main menu and Album entries and a
  fixed Continue action. Settings have persistent Text / Audio section buttons;
  text size is the first accessibility control. A size change retains that
  section. Settings Back / Escape returns to pause (or the title menu), and
  Continue resumes the same simulation. Explicit pause/settings also pause
  the native audio conductor; merely viewing a plan does not issue game commands.
- **PLR-008:** The two-digit objective number is sized using its actual heading
  font at the current scale; a new layout assertion checks the full string.
- **PLR-009:** CheckButton hover+pressed text is explicitly dark, alongside
  normal, hover, pressed and focus states; shared theme defaults agree.
- **PLR-001/004 integration:** Tray selection enters explicit placement. Stage
  receives `placement_entity`; invalid taps explain the action without silently
  choosing another object. Cancel and Back leave placement. Actual accepted
  commands clear the mode. Level-scoped names/descriptions are used consistently.
- **PLR-005 integration:** The fold action says “Fold the top” / “Сложить верх”;
  level-scoped descriptions distinguish folding screens from rigid shields.
- **PLR-006 integration:** Hints call the guidance layer with a per-context
  counter; a blocked plan's reason has priority over selection instructions.
- **Additional inspector overlap:** Viewing diagnostics are part of the measured
  HUD instruction panel. The stage receives its real bottom edge as a safe top;
  the old fixed-stage text is not relied on.

## Interface contracts

`PauseSettings` remains the HUD gear. New targets:
`PauseContinue`, `PauseSettingsMenu`, `PauseMainMenu`, `PauseAtlas`,
`PauseRestart`, `SettingsAccessibility`, `SettingsAudio`, `SettingsBack`,
`TextScale_100/120/140`, `PlanSummary`, `PlanRoutes`, `PlanRoute_<actor>`,
`PlanAttachment_<entity>`, `ObjectiveLevelNumber`, `CancelPlacement`.

Guidance: `hint_context(kernel)` and
`hint(kernel, locale, index, catalog)`; stage: `placement_entity`,
`hud_safe_top`, and `target_tapped("placement_invalid", entity_id)`.

## Validation observed

- Godot 4.7.2 `--headless --check-only --script presentation/game.gd`: exit 0.
- `tests/test_ui.gd`: **88 checks, 0 failures, 124 actual pointer events**.
  Includes failed/accepted L01 demonstrations, undo, explicit law application,
  the L02 follow-up, pausing an active demonstration, source controls, audio /
  accessibility tabs, saved settings and checkpoint fallback.
- `tests/test_layout.gd`: **12,496 checks across 824 native layouts, 0 failures**.
  All campaign phase samples RU/EN at 100/140%, physical landscape canvas
  profiles, context/footer separation, and the added real-font number assertion.
- No engine error or resource-leak lines were observed in either targeted log.

These are desktop/headless native checks. They do not establish physical Android
usability, subjective listening, or user acceptance. The manager's subsequent
frozen full gate and independent Player retest tie final integration to its
runtime digest. No claim of those later results is made here.
