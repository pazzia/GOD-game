# Native scientist UI — implementation contract

The owner approved the mature professor and menu on 25 October 2026 and requested
production implementation across the game. This document describes the native
Godot UI implementation; it is not another browser prototype or a claim of owner
acceptance of the running game.

## Shared layout

The project keeps a 1920×1080 reference canvas and expands horizontally on wider
phones. The Stage fills the canvas. Essential stage geometry is coordinated with
the stage developer in the middle band, approximately y360–820. There is no
permanent right sidebar and no permanent inventory strip.

- `ObjectiveTicket` at (36,28), up to1160×144: level, short current goal, opens the
  full journal containing the complete objective, next instruction, all goal
  conditions and active law. `CurrentGoal` is its native shaped label.
- `NextActionHint` below the goal: a short authored next action. Selection changes
  the local hint without replacing the phase CTA or the top goal. Full prose stays
  in the journal and narrative sheet.
- Top right:144×144 undo, hint, pause/settings; screen safe areas add insets.
- Bottom left: `OpenObjects` and `OpenPlan`, minimum320/240×144. Their widths
  grow from the actual Onest text width at the current text scale plus the
  actual icon, separation and stylebox padding; targets and font never shrink.
- Bottom right: `PrimaryAction`,620px wide (700at140% text), minimum144high;
  height grows for wrapped copy. All actions remain48px high on a360px phone.
- `ObjectContext`,400×144, appears near the selected object or witness and is
  clamped above the fixed bottom actions. It opens actions or view inspection.
- Character captions sit above the bottom controls. Reduced motion is passed
  directly to the shared Stage; UI does not advance authoritative simulation.

The active-law badge is hidden while no law is active. Once active, it displays
only the readable law names in dark ink on a compact cream surface. The empty
Atlas message is available in the journal rather than floating on the scenery.

The goal and active law tickets are overlays on a full canvas, so Stage bounds
intentionally intersect HUD bounds. Tests requiring the old sidebar or requiring
Stage and primary rectangles to be disjoint are obsolete.

## Tokens and type

Native `presentation/theme.gd` is the token source: ink252647, coralF16C65,
creamFFF2D8, turquoise40B8B3, lemonF7D760. Coral buttons use dark ink text.
Body600and headings800use Onest with Cyrillic; exact source TTF, OFL license and
provenance are copied from the approved design package into `assets/fonts/`.
Body48and target144are the1080reference equivalents of16sp/48dp on360px phones.
Action and prose text honor100/120/140%; the large editorial wordmark is fixed to
its composition. Text uses native controls, not text baked into artwork.

## All game surfaces

The title layers the production ENV01 scene, CH01professor, CH02Plum, indigo
horizontal gradient, native two-line wordmark and single coral story button.
Fresh state says Start Story; changed checkpoint or completion says Continue.
Settings stays in the top right; its journal and main-menu links remain available.

Narrative briefing, three-stage hints, failures, victory and final credits use the
same cream journal sheet with a fixed return/continue action and scrolling prose.
Settings supports category volumes, mutes, reduced motion, subtitles, haptics,
text size, locale, restart, all experiments and main menu. Escape/Android Back
returns from a sheet; from play it opens settings. App backgrounding saves and
freezes the cosmetic Stage and audio.

The album is a chapter journey with three named sections and30story rows, not
an anonymous grid. Each row displays its experiment title, completion, and why a
later experiment is locked. The fixed return action remains outside the scroll.
Semantic row names are `Level_L01`…`Level_L30`, with `level_number` metadata.

Objects open in a scrolling drawer. Every movable tool, attachment, removable
support, foldable screen, source and route actor remains accessible even when its
initial mount is offstage. Native buttons use `Object_<entity_id>` and `entity_id`
metadata. Selecting closes the drawer and exposes legal stage slots. A separate
context action opens placement, folding, removal, attachment, source toggles or
route choices as applicable. Fixed unmodifiable objects have an inspection
explanation. Removal requiring a law is visibly disabled until that law exists.
During an active check, object inspection explains that edits require preparation.

The Plan sheet retains routes, candidate-law preparation, rehearsal, law removal,
replacement, world-run and album. Law replacement remains explicit and cancellable.

## Causal action contract

Primary always expresses the phase; selecting an item does not turn it into a
hidden context-menu opener. `QuestGuide.describe()` can return `primary_intent`:

- `remove_l01_float`: explicit Interact/remove after the law.
- `cross_l01_marfa`: explicitly assign Marfa's cross route if needed, then run.
- `begin_required_experiment`: choose `required_experiment` law if needed, then
  BeginPerformance. It does not place tools or solve the experiment automatically.

Proof is followed by an explicit Make Law action. L01then removes the actual
support and separately sends Marfa across. A failure does not reset the arrangement;
Undo uses the kernel's previous state. All other route/law/object actions retain
the authoritative kernel command interfaces across all30levels.

A checkpoint rejected after the rules revision restarts only the current task.
A short explanation on story entry states that unlocked levels are preserved.
Completion and unlock records are not cleared.

## Verification and remaining review

The native source parser was run with Godot4.7.2, isolated XDG data/cache paths,
`--headless --check-only --script presentation/game.gd`: exit0and no engine or
script errors. A first attempt with the default read-only home produced only
user-data/cache write errors; the isolated-path rerun was clean.

Actual native screenshot/tap/layout review follows the coordinated art+code
freeze and shared import. It must cover844×390,720×360,960×540; RU/EN100/140%;
main menu, brief, preparation, both failed L01arrangements, folding, law, removal,
real crossing, success→anchor, object drawer, multi-law replacement, three chapter
scenes, settings and the final album row. No phone performance or human
comprehension result is inferred from a source parser check.

## First native review corrections

The first native menu capture revealed that assigning a texture before setting
TextureRect.EXPAND_IGNORE_SIZE clamped the figure to its source-image minimum.
Both menu figures now set the expansion mode before texture and final rectangle,
so the full professor and moth use the approved composition rather than cropped
source dimensions. This is a resource-layout correction, not arbitrary scaling.

## Minified illustration filtering

Native menu figures, scene plate and item-drawer illustration icons request
CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS. PNG import settings for the new
production art must generate mipmaps; the parent owns this shared import step.
This preserves fine hair and fabric edges at phone scale without repainting or
a blur overlay. AtlasTexture clipping/regions remain the art manifest authority;
edge bleed must be reviewed on the minified native captures after reimport.

## Enlarged control-label regression

Independent EN140% native review found that the original240px Plan button
clipped its last glyph once its route icon and content padding were counted.
Both permanent text controls now measure their localized shaped-font width,
add the actual icon allowance and stylebox content margins, and grow while
keeping144px touch height. The independent layout gate checks every displayed
line of every permanent button against that same available native content area.
