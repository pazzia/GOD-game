# Design acceptance ledger

Designer reports to Manager. Current UI acceptance: **accepted for the native test build with documented P1 polish**. Full S3 production acceptance is **not granted**. See the final31-frame review below; historical rejections remain as an audit trail.

## Historical evidence
The pre-reset screenshots plan-ui and L01plan/proof/settings/success were actually inspected then lost. They exposed debugwaterrectangles, crowded spectator bodies, giant portraits spilling into tray, white text on cream settings, tiny touch targets, global-scope law wording and material mismatches. These are historical observations, never current verification.

## Regenerated run before second reset
Actual Godot captures build/L01-plan.png,L11-law.png,L21-plan.png,L30-plan.png from18:08 were rejected. P0: portraitoverflow;«Садовник»single-letterwrap; footerbuttons overlap; longCTA truncated; L30exposed internal«latched»and overflowed goal; kitchen watergeometry looked dry. Artwork corrected: PROP_ANCHOR withWOOD now uses wooden span_anchor.png; PROP_STONE_ANCHOR now visibly roughlimestone stone_anchor.png. Water_surface/ice_surface created for exact authored polygons.

Actual same-named captures updated18:19 were inspected. Previous P0 removed at100percent: portrait/footer/CTA no longer spill, short clear goals, new stone/wood materials and textured waterpools. Settings darktext/large switches/scroll readable. These reviewed image bytes might be from a previous checkpoint; restored timestamps are not proof of rerender.

Remaining P1: Plum hovered over Felix's face (move offset to+160,-130); topstrip-of-fullbody portrait made tiny heads (replace with square face crops/emotionPNG); character reactions need named emotion events rather than just numbered pins. Poolrim should be painted with light/shadow, not debugline. UI140percent, compact/tallphone andEN need newly rendered actual evidence after latest fixes.

## Mobile requirements
At360dpwidth with1080referencepixels:48dp target=144pixels;16spbody=48pixels,14spcaption=42pixels. Critical goals/errors must not be ellipsized. At140percent grow lowerHUD, shrinkstage coherently, keep all requiredactions reachable. Witness144highcard: portrait/statusupperrow, fullnamefullwidthbottomrow. TextureRect: setIGNORE_SIZE beforetexture, zero minsize, then desiredsize, clippedparent. PrimaryCTA is only action («Показать чудо/Поставить печать/Разыграть план»). Footer«Откат/Совет/План». Lawscope «В этой сцене».

## Next evidence
Current newrun at100and140percent,360×640and360×800,andEN: title,map,settings,plan,proof,law,resolution,success,L02blockedwitness,L03inspector,L11M02,L21M03,L30multi-law. Developer supplies files; Designer logs actual pass/revision and exact dates. A successful render command or headless suite alone is not visual acceptance. Source/artBible files must be distinguished from runtimeintegratedfiles and unfinishedproduction.

## Actual restored native run reviewed 2026-10-23, after v5 restoration

Developer supplied 22 newly rendered Godot/Mesa/Xvfb cases in `build/ui/`; Designer inspected L01 plan/show/proof/law/success at RU100, L01 plan at RU140 and EN140 on 360×640, settings EN140, L11/L21 plan RU100, L11 EN140 on 360×800, L21 EN140 on 360×640, and L30 law selection EN140 on 360×800. Source metadata: `build/ui/ui-captures.json`. These are actual new image bytes, not acceptance inferred from restored old timestamps.

Accepted aspects: witness portrait PNGs are readable and stay inside their cards; main action and footer fit at both text scales; settings have dark readable labels, large switches and a scrolling body; the L30 replacement dialog presents two laws and explicit cancel/close actions without clipping its choices; success text fits.

Returned to Developer as P0:

- RU140 L01 law banner: its second text line descends outside the lavender background. EN140 is similarly tight. Allocate measured wrapped text height after final font/width, including panel padding.
- RU140 witness name «Садовник» is clipped to «Садовни». Full name must wrap or card width must grow; do not ellipsize required character identity.
- RU100 L01 show instruction has three lines but the cream panel reserves two: «убедился.» descends beyond the panel into the cards. Measure all instruction states, not a single handpicked phrase.
- Fresh L21 still maps wooden `PROP_ANCHOR` to the stone anchor. Correct runtime mapping to `span_anchor.png`; keep `PROP_STONE_ANCHOR` mapped to limestone art. The correct assets are already present.
- Water rendering changes were lost at reset: current stage draws ripples/frozen tint but never loads the water/ice texture planes. Restore exact authored textured polygons so ENV02/03 do not depict dry floor where open water exists.

P1: compact140 stage is approximately 328×100 px and squashes scenery. A 3:2 stage needs about219px height at328px width. Use coherent fit and a scroll/focus solution for constrained screens, preserving text size and sticky primary actions. Plum offset must scale with actual hero height; fixed(-155px) leaves the companion floating far above the shrunken hero. Suggested relative offset(+0.73h,-0.59h).

ENV01 offline assembly: inspected five new independent layers at1536×1024 in `build/ENV01-layer-assembly.png`. Warm square framing and quiet central playfield are coherent. Native placement/water/occlusion acceptance remains pending until Developer integrates the manifest and supplies a fresh actual screenshot.

Felix native key poses: inspected `build/felix-keyposes-native.png`. Closed shoulders and part overlaps are coherent in idle/move/observe/suspect/accept/reveal/celebrate/stamp. Turn at35% shrinks to an implausibly thin strip; Manager is correcting it. Full profile/back art remains outstanding, so this is not accepted as a genuine directional rig.

Static nonhuman production review: `build/plum-rig-assembly.png` and `build/caramelka-rig-assembly.png` inspected after manual pivot/scale calibration. Plum head/neck and feet gaps were corrected; satchel strap root is now hidden naturally under chin fur. The two wing fans connect behind the body; antennae follow the head joint. Caramelka has four separate coherent legs, overlapping fur at hip/shoulder joints, a connected raised tail and head-parented horns/collar. These are approved as static production inputs for Manager's native key-pose review, not yet as accepted runtime animation. Portrait states remain the actual 81 runtime face assets; body cutout movement does not replace facial expression art.

## Second fresh native run: ui-v8

Inspected the actual new files in `build/ui-v8/`: L01 plan/show/law RU100; L01 plan RU140 and EN140 at360×640, including the audience-scrolled variants; L11/L21 plan RU100; L11 EN140 at360×800; L21 EN140 at360×640 and RU140 audience variant; settings EN140; L30 selection EN140.

The three text P0 issues are closed in these image bytes: two-line law labels stay on their backgrounds, the three-line show instruction has a correctly expanded cream panel, and witness cards allocate enough width for their names. In compact140, the last witness is intentionally reached by horizontal scrolling; requested a specific right-end capture proving the full RU name «Садовник». Requested a separate upper-content bottom capture proving inventory access because the initial compact screen and first-card ensure-visible capture do not show that row. This is a missing visual check, not a declared unreachable-inventory defect.

Actual integration verified: ENV01 uses the new five independently painted landscape layers; the stage preserves3:2 instead of squashing scenery; Felix uses his assembled part rig; Plum fallback is placed relative to his height; wooden span-anchor art is correct in L21; authored water zones have visible textured fills in ENV02. Primary action and footer stay fixed and legible at both scales. The framed pool edges are still a visual-polish item: add a subtle inset/contact shadow rather than increasing unrelated geometry or pretending to hide a visible method.

Actual nonhuman native review: `build/plum-keyposes-native.png` and `build/caramelka-keyposes-native.png` were inspected. Eight base states plus an extra stamp pose are captured at35percent of their clips. Wings genuinely change angles independently; antennae, horns and collar stay on the head joint; four goat limbs stay coherent. Accepted as native key poses for Stage integration. Each rig JSON records the evidence hash and scope. Continuous full-cycle visual QA and genuine front/profile/back direction art remain outstanding; the key-pose sheet does not prove them complete.

## Production freeze and v9 targeted review

All nine actual part rigs are statically and natively key-pose reviewed. Designer inspected each actor independently; Manager accepted the native sheets. Final evidence is `build/rig-review-final/<actor>-keyposes.png`, with each SHA256 recorded in that actor's rig JSON. Eight final PNGs match the previously inspected bytes; final Felix was individually viewed after the turn correction. Turn now preserves at least84percent width instead of collapsing to18percent. Key-pose acceptance is limited to eight base states plus stamp at35percent, not continuous directional acting.

Six human rigs were produced by three explicitly delegated art assistants, two actors each, then defended to Designer through actual static assemblies and per-actor export/provenance records. Marfa's neck/shoulders/rope grip, Semyon's leading-hand ruler, Lada's shawl/spoon, Hugo's head-parented ribbon, Nika's corrected outward elbows and Roza's folder/stamp were inspected. No shared metadata was concurrently written by assistants.

ENV02/ENV03 now also contain five genuine independent paintings each, full1536×1024canvas, with inspected offline assemblies. Their floor revision2 raises paving to approximately20percent height so authored props at30–40percent do not stand in the distant vista. Original v1 floors and exact edit prompts remain in source. Final native integration review follows this asset freeze; offline assemblies do not establish gameplay readability by themselves.

Actual v9 compact140 end captures were inspected: `L01-plan-ru-140-360x640-audience_end.png` shows the full name «Садовник»; `L01-plan-ru-140-360x640-inventory_end.png` proves vertical access to the tray and horizontal access to «Первая ширма». The missing evidence from v8 is closed. All three text P0 issues are accepted as fixed. L06 plan/moving actual captures show Felix, Plum and Caramelka using real assembled parts; joints remain coherent. P1: goat, crate and hero overlap heavily in initial staging; preserve authoritative coordinates while improving depth/readability later.

This is a visual review of named image bytes, not a blanket technical pass for every v9 capture. Developer reported a shutdown-audio error in the original map capture and separately fixed/retested it; final whole-batch technical status belongs to the new final capture catalog. Final fresh full-batch native review remains pending after freeze.

## Final independent native visual acceptance

Designer individually inspected **all31actual final PNGs**:30cases in `build/ui-final/` and the additional RU140settings case in `build/ui-final-extra/`. Combined technical catalog: `build/ui-final/all-captures.json`,31clean cases. Independent review, exact image SHA256 values and remaining limitations: `tests/reports/designer-visual-review.json`.

Runtime source digest: `cb83d6eae698674b8f25768da86d10853c0a73128c5381af8534b9c88eaac66c`. Matching APK SHA256: `4cdd114c9afc50566226d49a7352918019dbee02c12ae9685cf4b929a9232451`. No runtime/assets were changed during final review.

**Decision: accepted for the native test build, with P1 polish.** The three returned text P0 issues are closed: RU/EN140law text stays on its measured background; the RU100three-line show instruction fits its expanded cream panel; horizontal witness scroll reveals the complete name «Садовник». Compact140vertical scroll reaches the inventory, horizontal scroll reaches full item labels, and the main action/footer remain fixed. Portraits stay in cards, actor sprites remain coherent, settingsRU/EN140and both law-replacement dialogs fit.

Final integrations actually observed: L11shows Lada, L21Hugo, L30Marfa/Lada/Roza; L02has the distinct Postwoman and L03Semyon. All three independent landscape stacks render in the game. Revised kitchen/archive floors provide visible ground contact; wood supports have the correct material; water zones are textured. L06plan/moving shows the actual Felix/Plum/Caramelka part rigs. Exact L30header inspection confirms the initial title and settings gear are present at scroll0; an inline-preview impression was not a real defect.

Remaining P1 items are concrete and do not reopen the closed text issues:

- Water pools have thin flat framed edges; add inset/contact shading and painterly edge polish while retaining exact authored polygons.
- L06initial goat/crate/Felix staging is crowded; improve depth and loaded-payload readability without moving authoritative anchors.
- Locked album numbers and the disabled checking-status CTA have weak text contrast. Preserve the disabled state while keeping their labels readable.
- «Груз3» is ambiguous between current load and capacity; a concise maximum-capacity label such as «До3» would communicate the number better.
- Default42reference-pixel body copy is approximately14sp at360dp. It is readable in these native renders;16sp and icon size should be assessed on real phones while preserving48dp targets and the working140percent layout.

**This is not full S3 acceptance.** Genuine direction art and directional acting, full-cycle actor-specific animation/event staging, segmented crowd acting, dedicated level overlays, the full authored VFX pass, environment parallax and real-device visual/touch/performance/listening acceptance remain separate work. The other six human bodies are actual native-review-room rigs; campaign witnesses currently use their expression cards at exact eye pins. Authored focused/embarrassed/wink portraits have no current witness-event mapping. Source presence and a clean native screenshot matrix do not erase these production gaps.
