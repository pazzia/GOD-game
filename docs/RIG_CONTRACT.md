# Runtime cutout puppet contract

Paths: `assets/art/characters/rigs/<actor>/rig.json`, adjacent `<part_id>.png`. Parts are separately drawn from the actor reference, not nine slices of a complete body. Until files exist, this document is a contract, not a completed rig. State IDs: idle,move,turn,observe,suspect,accept,reveal_react,celebrate; Felix adds show_begin,stamp,bow, Plum adds hover,fly,point,shiver,cheer. Animation is cosmetic; no state change from animation callbacks.

## JSON
schema_version1, actor_id, canvas_size, feet_origin, nominal_height, parts[], portraits{state:path}, angles{front/profile/back:path}, status. Each part: id,file(relative PNG),position[x,y](anatomical pivot in shared canvas),pivot[u,v](normalized in trimmed PNG),target_height(preserve aspect),z_index,parent(null for flat canvas transforms),role(optional head,torso,arm,leg,cape,wing,antenna,tail,prop). Renderer scales by target_height/PNGheight, moves sprite pivot onto position-feet_origin. Entire puppet scales requested_stage_height/nominal_height. No arbitrary native-image-size positioning. Metadata only marked assembled_verified after inspecting the actual composition.

## Humans
canvas_size[1000,1400],feet_origin[500,1320],nominal_height1320. Baseline pivots/placements below; individual JSON overrides body proportions, costume length and prop hand as necessary. Arms/legs have rounded overlap at their upper joint; source image must show whole part without a torso attached. Head includes hair/hat, torso excludes head/arms/legs, cape/backpanel separate.

| Part | Position | Pivot | Height | Z |
|---|---|---|---:|---:|
| cape |500,435|.5,.04|870|-30|
| left_leg |430,820|.5,.04|500|-20|
| right_leg |570,820|.5,.04|500|-19|
| torso |500,430|.5,.02|470|0|
| left_arm |350,470|.5,.04|430|-5|
| right_arm |650,470|.5,.04|430|5|
| head |500,450|.5,.94|400|10|
| accessory |625,810|.5,.5|200|8|
| prop |800,780|.3,.8|340|15|

Marfa cape is a short jacket backpanel, not a fantasy cloak; Semyon vestback short; Nika has an overall backpanel/straps, preserving the actual mustard shirt and teal overalls rather than inventing a jacket. Lada skirt belongs torso, legs shorter under skirt; head height includes tall cookhat and her separate floral shawl. Roza folder uses left hand and stamp right hand; Hugo has empty presenting hands, a separate gold hat ribbon parented to head and red neckbow parented to torso, without an invented wand. Costume/identity must match the actual baseline, with no duplicated hat or cape collar.

## Plum
canvas[1000,1000],feet_origin[500,950],nominal_height950. Body[500,580]pivot[.5,.5]height500z0; head[500,340]pivot[.5,.85]height340z10; wing_left[415,500]pivot[.9,.5]height620z-20; wing_right[585,500]pivot[.1,.5]height620z-19; antenna_left[410,180]/antenna_right[590,180]pivot[.5,.95]height200z11; bag[500,650]pivot[.5,.5]height200z20; foot_left[450,820]/foot_right[550,820]pivot[.5,.06]height120z-10. Wings attach at the inner body edge and overlap body; antennae at head top. Metadata will be calibrated against composition.

## Caramelka
canvas[1400,1000],feet_origin[700,940],nominal_height940. torso[600,500]pivot[.5,.5]height430z0; head[1000,430]pivot[.5,.8]height450z10; front_left_leg[935,650]/front_right_leg[1035,650]/hind_left_leg[340,650]/hind_right_leg[440,650]pivot[.5,.03]height290z-10,-12,-11,-13; tail[240,480]pivot[.9,.7]height220z-15; horns[1030,180]pivot[.5,.94]height230z11; collar_bell[960,510]pivot[.5,.2]height160z20. Four legs and hooves, no anthropomorphic hands. Horns separate from head to avoid duplicated pair.

## Portraits / directions
Real face portraits exist at `characters/portraits/<actor>/<state>.png`, named idle,observe,suspect,accept,reveal_react,focused,embarrassed,celebrate,extra(wink). These are UI head-and-shoulder cutouts; do not blindly substitute the whole bust for the rig head. Witness states: exposed→reveal_react; accepted→accept; performance→observe; selectedinspection→suspect; success→celebrate; fallbackidle. Focused/embarrassed/wink are authored expressions without a current witness-event mapping. Sourceatlas9expressions is in source/bibles. Planned full-body direction frames `characters/angles/<actor>/{front,profile,back}.png` are not yet produced. A future direction sprite must not be labeled a fully animated directional skeleton.

## Actual production status, 2026-10-23

All nine actors have nine genuine separately painted body parts and calibrated rig JSON. The numeric tables above are starting proportions only; actual per-actor JSON is authoritative and uses a larger canvas where needed. All nine native Godot key-pose sheets in `build/rig-review-final/` were independently inspected and accepted for integration. Metadata records exact evidence hashes and scope: eight base clips plus stamp at35percent duration. Continuous acting, three painted direction views and actor-specific event staging remain separate work. Stage currently binds Felix, Plum and Caramelka; witness cards use real expression PNGs at exact authoritative eye pins. Do not count the other six native review-room puppets as visible campaign stage bodies.
