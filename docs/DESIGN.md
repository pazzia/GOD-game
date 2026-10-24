# Почти бог — visual/UX contract, recovery revision

Regenerated baseline after workspace reset 2026-10-23. Historical screenshots and asset bytes were lost. Historical review is evidence of identified defects, never proof of current build correctness. Current art paths remain stable for native Godot project.

## Art
Hand-painted original gouache storybook, cream paper, teal river, clay/copper props, plum costume and UI. No emoji buttons or gray placeholder actors in accepted build. Source PNGs in assets/art/source/.gdignore, atlas regions/pivots in atlas_metadata.json, executable original icon sources in build_ui_icons.py.

Runtime backgrounds: environments/bg_river.png, bg_kitchen.png, bg_archive.png. Characters: felix/plum/marfa/semyon/nika/lada/roza/hugo/caramelka.png. Bottom-center people pivot, center moth. Stage reference heights Felix220,Marfa205,Semyon210,Nika140,Plum60. Full figure sprites are separate from UI portrait crops. Never let TextureRect inherit image minimum size: expand_mode IGNORE_SIZE, deliberate rect, clip_contents on portrait container.

Authored game geometry24×28 is authoritative. Affine world-to-stage projection must be used consistently for props, hit targets and ray diagnostics. Decorative environment never defines walkability. Render witnesses as small distinct numbered eye pins at exact authored anchor; larger portraits/names/status live in bottom cards. Do not shift eye anchor to spread sprites aesthetically.

## Palette / legibility
ink#25243B, cream#FFF5DE, panel#F5E5C4, primary#5D43A7, primaryText white, accepted#276B5C, revealed#A84148, water#4C98AA, clay#DA8951, gold#D7AA47 decorative only. Main text contrast>=4.5:1, UI meaningful outlines>=3:1. Override Godot CheckButton text for normal/hover/pressed/focus/disabled to dark readable colors; default white-on-cream fails. Meaning uses shape and label in addition to color.

## Mobile sizing
Target360dp reference width implies1080units/360=3: minimum48dp touch region=144reference units, main16sp text=48units; captions14sp=42units. Do not confuse render pixels with dp. Use safe areas, keyboard/back handling, textscale100/120/140, and scroll settings where needed. Scale decorative stage to free space rather than making controls tiny. All mandatory actions via single tap; drag is optional convenience. Never require long press.

Suggested compact layout1080×1920: top level title+menu y40–184, law card y196–308, stage y320–1040, contextual instruction y1048–1192, witness cards y1200–1344, tray horizontal scroll y1352–1496, primaryCTA y1504–1648, Undo/Hint/Rehearsal y1656–1800, safe bottom remaining. On wider/taller devices stage may grow. Stage projection must adapt to actual rectangle rather than hardcoded geometry spilling under HUD. Main branding and slogan belong title screen; do not consume250px on every level.

One primaryCTA by phase: Show→Stamp→RunPlan. Rehearsal secondary. Tray shows icon+name+selected state and small return-to-tray target. Law scope label «В этой сцене»; never imply a persistent global law across levels. Support badge says «Груз 3»/«Груз 5» near stone with dark background; L02/03 larger stoneL cap5 vsL01stoneM cap3. No magical extra support is drawn without data.

## Scene animation
No opaque debug WATER rectangles. Gentle ripple strokes and selection-only boundary. All interactive props separate; inspector movement follows kernel windows, witnesses vote only on kernel events. Felix breathes/presents/stamps/bows; Plum hovers and reacts; prop move150ms, invalidreturn220ms, transformation1100ms, removefloat650ms. Reducedmotion disables bob/parallax/shake and preserves meaningful state order. Cosmetic callbacks must never set gameplay outcomes.

## Acceptance
Need current actual screenshots: title/map, L01plan, proof, activation, resolution, success, settings, L02blocked witness, L03backview, L11M02, L21M03. Capture360×640 and360×800 plus large text. Acceptance cannot be inferred from headless tests or artwork alone. Full30 authored compositions, all9model bibles with8expressions/3angles and layered5ENVsource remain distinct production requirements until files actually exist and are integrated.
