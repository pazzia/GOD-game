# Artwork provenance and production status

Updated 2026-10-23 after the restored v5 production pass.

All illustrations were generated specifically for «Почти бог» with the built-in image generation tool. Identity references are this project's own character artwork. No external stock or franchise artwork was incorporated. The SVG icon system is original editable code. This is a provenance record, not a claim of exclusive rights or a third-party license grant.

## Actual files

| Group | Files | Production status |
|---|---:|---|
| Named-character and crowd baseline cutouts | 15 PNG | Original alpha cutouts; fallback and identity references |
| Facial expression portraits | 81 PNG | Nine expressions for each of nine named actors |
| Separate puppet body parts | 81 PNG | Nine genuine separately painted parts per named actor |
| Independent environment layers | 15 PNG | Five independently painted layers for each of three environments |
| Gameplay props and state variants | 39 PNG | Includes wooden and limestone supports and water/ice planes |
| UI icons | 32 SVG | Original vector source; no redundant raster sizes required |
| App icon master and exports | 4 PNG | Original Felix/stone illustration and faithful size exports |
| Earlier portrait environment plates | 3 PNG | Explicit fallback plates; never counted as independent layers |

Source rasters, prompt sidecars and extraction metadata are retained under `source/`. Baseline atlas export records are in `atlas_metadata.json`; the six new human rigs retain their own extraction records under `source/rigs/<actor>/`. Some early exact prompt text was lost during workspace resets; original source PNGs and crop provenance were retained. Newly produced expression sheets, parts atlases, environment paintings and targeted edits have exact prompt records.

## Characters

The 81 actual square face PNGs are in `characters/portraits/<actor>/<state>.png`. States are idle, observe, suspect, accept, reveal_react, focused, embarrassed, celebrate and extra (wink). Source expression sheets and exact prompts are in `source/bibles/`.

Witness cards select real portraits through `presentation/game.gd`: exposed→reveal_react, eligible vote→accept, inspected→suspect, performance→observe, success→celebrate, default→idle. Focused/embarrassed/wink are authored expressions without a current witness-event mapping. Automatic code support is distinct from a character actually appearing in campaign data. The explicit campaign-cast authoring pass assigns every named character and all six crowd identities while preserving witness IDs, geometry and rule weights.

All nine named actors now have calibrated `characters/rigs/<actor>/rig.json` and nine separately drawn transparent pieces. Sources: Felix/Plum/Caramelka in `source/bibles/`; Marfa/Semyon/Nika/Lada/Roza/Hugo in `source/rigs/<actor>/`. These are parts atlases, not whole-character illustrations arbitrarily sliced into anatomy. Source corrections preserve prior versions: Felix v2 removes hollow shoulder sockets; Nika v2 reverses the two isolated arm orientations.

The native Godot AnimationPlayer is implemented in `presentation/character_puppet.gd`. Actual native key-pose sheets for all nine actors were inspected and accepted for integration: `build/rig-review-final/<actor>-keyposes.png`. Each rig records its exact evidence path, SHA256 and limited scope: eight base clips plus stamp at35percent of clip duration. Closed anatomical joints, parented props, independent moth wings and the corrected Felix turn were checked. Full continuous-cycle acting and genuinely painted front/profile/back directions are not claimed. `runtime_animation_verified:false` deliberately reserves full-motion acceptance; `native_keypose_review.accepted_for_integration:true` records the completed check.

Stage currently binds the actual Felix, Plum and Caramelka puppets. The other six body rigs are genuine native-review-room assets; their campaign presentation and actor-specific acting remain separate integration work. Witness cards use expression portraits at the authoritative geometry's exact world pins. The crowd has six distinct baseline cutouts, not a finished shared segmented crowd rig.

## Environments

`environments/ENV01`, `ENV02` and `ENV03` each contain backdrop, floor, midground, foreground and atmosphere, plus `layers.json`. All are full-canvas1536×1024 paintings. Transparent margins are retained; never alpha-trim these aligned layers. They are separate generation/edit outputs, not bands cropped from one image.

The common draw order is backdrop→floor→midground→foreground→atmosphere (opacity0.16), then authoritative gameplay content. Midground and foreground are decorative and cannot claim to occlude a method. Atmosphere contains faint light motes, not smoke/steam or gameplay blockers. The layer stack is currently static; metadata describes optional future parallax. Actual actor motion and water effects are separately animated and respect reduced motion.

ENV02/ENV03 floor revision2 extends paving upward to approximately20percent canvas height so props at30–40percent have visible ground. Original floor v1 PNGs and their prompts remain beside the selected source. Source edits preserve the painting's material and do not alter authored world geometry.

`presentation/stage_view.gd` loads each five-layer manifest and renders actual water/ice texture polygons above the ground in every environment. Layers, actors, pins and hit regions use one undistorted3:2playfield transform. Offline assemblies `build/ENV0{1,2,3}-layer-assembly.png` prove composition only; final native screenshots are separately reviewed.

## Materials, UI and validation

WOOD `PROP_ANCHOR` maps to `props/span_anchor.png`, a wooden bracketed support. `PROP_STONE_ANCHOR` maps to rough porous limestone `stone_anchor.png`. The stone S/M/L capacity variants share source art with deliberately different scales and capacity badges; image counts do not substitute for effective-capacity rules. Water/ice planes remain exact authored geometry, and frozen fire/bowl variants are separate paintings.

`build_ui_icons.py` is the editable source for32SVG icons. `ui/app_icon_master.png` references the game's own Felix and floating stone;1024,512and192exports are faithful resizes. Font files and their license are in `assets/fonts/`.

Exports use temporary `.tmp` files and atomic replacement. Runtime cutouts were alpha-checked; metadata references and decode integrity are checked by `tools/verify_art.py`. The complete571-row planned-vs-actual register is generated by `tools/inventory_assets.py` into `docs/ASSET_STATUS.csv`. Presence, native key-pose acceptance, campaign use and full production completion are deliberately different statuses.

Remaining production work includes genuine three-direction character art and actor-specific continuous acting, crowd rigs, dedicated level overlays/composition acceptance, full authored VFX timing/masks, and real-device visual/audio/touch review. No full S3 art-completion claim is made from file counts.
