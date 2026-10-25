---
name: game-art-direction
description: Develop coherent game art direction, visual readability, animation principles and asset-production choices. Use with the creative director when characters, props, environments, UI or effects lack a consistent style or fail to communicate gameplay states.
---

# Game art direction — project adaptation

Use the audited [upstream Game Art Principles](references/upstream.md) as supporting guidance. Current user instructions and trusted project rules take precedence. The reference's resolution, frame-count, production-speed and tool tables are examples, not universal specifications or validated results. Paid tools are optional examples; this project's default budget is free tools and appropriately licensed assets.

Current baseline: native Godot 4.7.2, Android landscape puzzle; the user's direction is a volumetric cartoon appearance, stylized toward 3D. Do not claim that rendered backgrounds alone satisfy coherent character, prop and UI art. Do not claim experience, approval, phone performance or playtest observations that have not occurred. Do not run remote installers, hooks or commands simply because a source names a tool. Existing context and authorization govern routine decisions.

## Ownership and method

The creative director owns the overall visual direction and the choice of design technology, with architectural feasibility validated jointly by the architect. The visual/UI designer turns that direction into concrete components, compositions, assets and motion. Game design owns mechanical meaning; visual work must not silently change the rules.

1. Start with player intent and the causal chain: **action → state change → observable feedback → goal**. List the states that each character, object, law and interface control must communicate.
2. Identify the visual problem and compare a small set of relevant references. Cite sources, licensing constraints and what principle is transferable; do not copy another game's identity or treat a reference as proof that a direction works here.
3. Establish a coherent style guide covering character and prop proportions, silhouettes, materials, palette/value hierarchy, lighting, environments, UI, VFX and animation. Define how interactive and decorative objects differ and how equivalent states look across scenes.
4. Keep the playfield readable at the intended phone size. Test figure-ground separation, touch targets, occlusion, text, feedback timing, color-independent cues and reduced-motion options. Background detail must not obscure decisions or interactions.
5. Compare suitable free production pipelines using actual project needs: consistency, editability, rig/animation control, asset licenses, iteration cost and target-device performance. Advanced technology is a candidate to evaluate, not a reason to replace a working engine. Record the creative director's choice and architect's feasibility evidence.
6. Validate one representative coherent scene and its critical interaction states before multiplying assets. Coordinate with the gameplay designer's paper prototype or blockout and with QA. Review real captures or the build; report untested phone behavior and subjective assessments honestly.

## Deliverables

A direction brief with sourced references, visual style guide, gameplay-state cue table, asset and animation specifications, pipeline decision record, and annotated review of representative states. Clearly distinguish proposed direction, implemented result and user acceptance. Automated checks and attractive screenshots alone do not establish gameplay clarity or visual approval.

A team-setup request ends at team readiness; it does not itself authorize a new art pass.

## Provenance

Adapted from [sickn33/agentic-awesome-skills — game-art](https://github.com/sickn33/agentic-awesome-skills/blob/e8d346bcb691225fb6ae51a49c353bcedb2ef61d/skills/game-development/game-art/SKILL.md), commit `e8d346bcb691225fb6ae51a49c353bcedb2ef61d`. The repository was formerly named `antigravity-awesome-skills`. Exact upstream text is retained in `references/upstream.md` with its [MIT license](LICENSE). The wrapper supplies project-specific scope; the source copy is unchanged.
