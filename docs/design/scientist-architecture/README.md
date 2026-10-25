# Native illustrated presentation

Status: implemented; integrated native captures and independent acceptance pending.
The owner approved the mature scientist and menu before requesting the game remake.

The production remains Godot 4.7.2, Compatibility, Android sensor landscape.
The 1920×1080 logical viewport and deterministic 24×28 simulation grid are retained.
The design reference 1560×720 controls composition, palette and hierarchy; it is
not a second simulation coordinate system or a browser replacement for the game.

`presentation/reboot_art.gd` reads `assets/art/reboot/manifest.json`. The creative
director owns this manifest and source art. Runtime entries have `path`, optional
source-pixel `region`, normalized `pivot`, and optional named `variants`.
`AtlasTexture.filter_clip=true` prevents neighbouring source art from entering a
crop. Whole source PNGs are retained; atlas selection does not edit pixels.
Texture resources are cached and shared across character instances.

`StageView` keeps the existing kernel, translator, target signal, selection,
inspection and reduced-motion API. `world()` and `unworld()` are a matching affine
projection of the same authoritative XY ground plane. The field occupies the
full stage; the top HUD and contextual commands belong to the separate UI layer.
Normal projected grid rows occupy 58–84% of stage height, leaving room for the
objective and bottom controls. At 140% text, the upper limit moves to 66% so
faces remain below the enlarged instruction. Chapter illustrations expose a
continuous open floor before that range; floor-source metadata records the
observed source boundary rather than the generation prompt's requested number.
Figures stand with their painted foot pivot on
the ground position; logical observation points are ground-plane pins rather
than a claim of literal three-dimensional eye ray tracing.

`asset_texture(entity_id)` returns the correct cropped prop/state. Callers must
use it for inventory art instead of loading `asset_path()`, whose source can be
an entire atlas. `entity_display_position()` and `witness_display_position()` are
available for contextual controls. Input rectangles retain a minimum 144×144
native design units. A face hit can inspect an observer while a torso hit
selects the associated physical actor. Neither target expansion nor display
packing changes authored positions, visibility or accepted commands.

CharacterPuppet adds `configure_illustrated()`. Its `visual_mode` explicitly says
`illustrated_cutout`, with `rigged=false` and the exact `source_art_key`.
AnimationPlayer supplies restrained root motion, cue timing, facing and route
interpolation. These assets are whole illustrated silhouettes, not separated
limb rigs, 3D meshes, turnarounds or generated facial animation. Legacy separated
rig authoring/validation APIs remain for archived tools and regression coverage;
they do not silently replace the new cast in production.

L01 uses one Marfa actor and observer identity. The body is rendered once and
follows its own confirmed crossing while the professor stays ashore. The screen
switches between the actual tall/folded atlas regions according to kernel state.
The Atlas sits beside the professor. Floating stones retain a support ripple;
cold fire, frozen water and strengthened paper have visible material cues.
Contained water and thermal food zones do not become a second decorative pool
under their container: the bowl's water/ice state is in the bowl illustration.
Real crossings and navigable water retain the authored polygon. Attached mooring
ropes connect their actual owner and target; clamped fasteners follow the screen
frame. These display changes read the existing attachment state.
Capacity numbers appear only on an inspected/selected stone, or when an explicit
comparison overlay is enabled. They do not cover the tutorial by default.
The L01 scientist and Plum use cosmetic packing beside Marfa, with their own
painted footing, so the two human silhouettes do not occlude each other.
Diagnostic rays appear only while an experiment can be examined, not from the
old observation location after Marfa has walked away. Artistic piers and water
patches follow authored ground starts and water zones; no new traversable route
or simulation support is introduced by painted scenery.

Prepared paper spans have a separate visual support plane derived from the two
actual authored anchors. The temporary steel frame occupies the space below a
thin, fully visible beam; a staged load's bottom meets the top plane. Draw order
is below-frame → anchors → paper → load. Removing the frame changes neither the
paper plane nor the load anchor. A stone/paper route interpolates a smooth
cosmetic elevation on approach and exit. The body and interaction anchor use
the same display position, while the kernel keeps its authoritative XY route.

The [targeted native evidence](evidence/targeted-verification.json) records 91
stage-boundary checks and seven native input-edge checks with zero failures.
The three stage-only captures show Marfa at the real 12-tick stone midpoint and
the staged paper load before/after removal of its frame. These captures verify
contact and stacking; full-HUD composition remains part of independent QA.

L08's safety-thread mount lies exactly on the water boundary, which the kernel
continues to classify as water. Its footing and painted body extend only into
the immediately dry side; a source inside the water cannot invent a platform.
When the existing support offset actually matches the stone, the visible thread
connects the source and target. The native L08 plan capture records this limited
shoreline treatment without moving the logical anchor or changing any water zone.

L18's corrected sailing route is reviewed at plan, actual sailing midpoint and
success. Its moving capture follows the second `RunResolution` and advances ten
ticks, rather than capturing the earlier warming-only phase. The unchanged
185-unit boat artwork remains recognizable inside the right basin, with the
heated stone on the bank. The authored arc passes through `(22,19) → (21,20) →
(22,21)`; no presentation-only displacement substitutes for that real route.

## Rendering choices and technical scope

| Technique | Current integration | Evidence and next decision |
| --- | --- | --- |
| Stylized painted volume | Active 2D illustration pipeline | New source art and atlas manifest; native captures still to review |
| Native canvas rendering, linear mipmap filtering | Active Compatibility baseline | Project configuration and CanvasItem filtering; native aliasing review remains necessary |
| Texture atlases and shared resources | Active | Manifest region checks and cached AtlasTexture implementation |
| Geometric LOD | No 3D mesh geometry in this pipeline | A mesh LOD chain would not change these 2D cutouts; evaluate if a 3D asset path is adopted |
| Texture quality tiers | Not yet benchmarked | Need matched mobile memory/frame-time evidence before choosing downsample/mipmap thresholds |
| DLSS / XeSS | No SDK or integration present | Candidate scope remains open; vendor OS/GPU/API and Godot integration must be verified before an adoption claim |
| FSR upscaling / frame generation | Not integrated | This change renders CanvasItem illustrations with Compatibility; a 3D viewport upscaler is not evidence of canvas upscaling or frame generation |
| Ray tracing / denoising | Not integrated | Light and material volume are painted into these sources; no measured ray-traced runtime is claimed |

The primary baseline renderer guidance already reviewed by the team is pinned
in [the creative charter](../../team/creative-direction-charter.md). No new SDK,
paid service, remote installer or rendering backend was introduced in this pass.
Advanced features remain research candidates, not project exclusions.

No physical Android GPU/driver counters, sustained thermal runs, human
comprehension tests or subjective art acceptance are inferred from parser checks.
Final import, native screenshots and the full regression gate are coordinated by
the parent after all production writes are frozen.
