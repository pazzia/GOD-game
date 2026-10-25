# Character acting implementation

The nine existing part rigs now have 47 additional authored body-animation timelines.
The authored source is `data/character_animations.json`; `presentation/character_acting.gd`
resolves cue variants; `CharacterPuppet` creates real AnimationPlayer tracks from the data.
This supplements the existing base states. It does not change the simulation.

## Runtime contract

- `Acting.states_for(actor)` returns the actor’s additional clips.
- `Acting.pose_for(actor, trigger, variant)` selects a reproducible cosmetic variant.
- `Puppet.special_states()`, `Puppet.play_cue(trigger, variant, force)` and
  `Puppet.is_loop_state(state)` expose the same contract to Stage.
- Triggers: idle, observe, suspect, accept, reveal, success, enter, interact, move.
- Variant counters belong to presentation; no clock, animation completion or random
  choice writes gameplay state.
- Each authored clip owns root position/scale/rotation and every bone rotation.
  Neutral tracks prevent an earlier pose leaking into the next animation.
- Nonuniform key times preserve anticipation, clear held intent and recovery.
  Linear interpolation prevents unplanned cubic overshoot beyond the keyed anatomy.
- Only walk, idle_chew and sleepy repeat. Other additional clips return to the
  queued loop after one completion signal. Routine loop refresh cannot cancel them.
- Reduced motion keeps a representative static pose. Routine loop refresh queues
  the next loop without erasing that pose; changing a semantic cue can replace it.

## Authored motion inventory

| Actor | Clip | Seconds | Stage dispatch / campaign reachability | Intent |
|---|---|---:|---|---|
| felix | distract | 1.35 | Second prop_interacted/prop_removed cue variant | Look left, sweep the empty hand wide, glance back while the prop hand stays low. |
| felix | place_prop | 0.95 | prop_placed event, or first interaction variant | Bend with both hands, lower the held prop, release and straighten. |
| felix | concealed_panic | 1.1 | prop_blown or recoverable_failure | Quick side glances and hands pressed inward, then a deliberately composed recovery. |
| felix | genuine_surprise | 1.3 | method_exposed | Compress before a startled rise, open both hands and settle. |
| felix | rescue_react | 1.55 | route_completed or SUCCESS idle beat | Reach to steady a safely arrived traveller, look down, then give a relieved nod. |
| plum | land | 1.15 | First scene signature / level initialization | Wings brake the descent, feet extend and the body settles through a small landing bounce. |
| plum | scarf | 1.8 | water_phase_changed to liquid (thaw) | Reach toward the satchel and wrap the wings at the neck; scarf cloth awaits its separate art. |
| plum | hide | 1.1 | water_phase_changed to frozen | Fold both wings protectively around the face and cautiously re-emerge. |
| plum | sleepy | 3.4 | 8-second planning idle beat, alternating with hover | Slow drooping antennae and head, a tiny startle, then back into the same drowsy posture. |
| plum | carry_note | 1.65 | prop_placed / prop_interacted / prop_removed | Lift carefully with both feet together, balance the satchel and offer the carried note; separate note art remains. |
| marfa | inspect_rope | 1.6 | observe: show/rehearsal observation; actor present from L01 | Lift and turn the coil, follow the rope with the eyes, then lower it. |
| marfa | pull_mooring | 1.45 | interact: inspect/select this witness card; actor present from L01 | Reach forward, plant weight back and give the mooring a firm two-hand pull. |
| marfa | arms_crossed | 1.25 | suspect: visible-method exposure streak; actor present from L01 | Bring the forearms across the apron, hold a patient appraisal, then release. |
| marfa | restrained_laugh | 1.8 | accept: witness vote accepted; success: SUCCESS phase; actor present from L01 | A contained shoulder laugh, small head dip and a calm settling pause. |
| semyon | measure | 1.85 | observe: show/rehearsal observation; actor present from L03 | Extend the wooden rule, sight along it, adjust its angle and fold back. |
| semyon | crouch_inspect | 1.65 | interact: inspect/select this witness card; actor present from L03 | Lower into a grounded inspection crouch, look under the mechanism, rise without translating feet. |
| semyon | glasses_wipe | 2.0 | idle: 8-second planning idle beat; actor present from L03 | Raise one glove to the spectacle area, make a short wiping arc and lower it; separate glasses are not rigged. |
| semyon | point_method | 0.9 | reveal: method exposed; suspect: visible-method exposure streak; actor present from L03 | A quick clear extended arm toward the exposed method, followed by a firm recovery. |
| semyon | thoughtful_nod | 1.35 | accept: witness vote accepted; actor present from L03 | Consider first, give one deep and one shallow nod while the rule stays still. |
| nika | notebook_draw | 2.1 | idle: 8-second planning idle beat; interact: inspect/select this witness card; actor present from L01 | Hold the notebook at chest level, draw several small strokes and inspect the sketch. |
| nika | lean_forward | 1.25 | observe: show/rehearsal observation; actor present from L01 | Shift curiosity forward with the notebook held out of the way, then return to balance. |
| nika | raised_hand | 1.05 | accept: witness vote accepted; actor present from L01 | An eager high hand above the head, held long enough to read, then lowered. |
| nika | small_hop | 0.8 | success: SUCCESS phase; actor present from L01 | Small anticipation, joyful hop and soft landing; feet do not leave their logical slot. |
| nika | protect_notes | 1.2 | reveal: method exposed; actor present from L01 | Draw the notebook safely into the chest and turn the shoulders away from the disturbance. |
| lada | taste | 1.8 | idle: 8-second planning idle beat; actor present from L11 | Lift the copper spoon, pause to taste, consider and lower it. |
| lada | kettle_check | 1.5 | observe: show/rehearsal observation; actor present from L11 | Lean over the kettle area and test with the spoon, keeping a cautious distance. |
| lada | apron_shake | 1.25 | suspect: visible-method exposure streak; actor present from L11 | Lift the apron sides and shake out a little flour in two broad beats. |
| lada | recipe_flip | 1.55 | interact: inspect/select this witness card; actor present from L11 | Hold an imagined recipe at chest level and turn a page; the missing page prop remains an art limitation. |
| lada | delighted_plan | 1.45 | accept: witness vote accepted; success: SUCCESS phase; actor present from L11 | An idea arrives: lift the head, open both hands generously, then nod at the new plan. |
| roza | inspect | 1.7 | observe: show/rehearsal observation; actor present from L25 | Inspect from one angle, pause, then compare a second angle while the folder stays upright. |
| roza | page_turn | 1.9 | idle: 8-second planning idle beat; actor present from L25 | Steady the folder and move the free hand across it to turn one page. |
| roza | stamp_check | 1.15 | interact: inspect/select this witness card; actor present from L25 | Inspect the administrative stamp, lift, press once against the folder and recover; no game-law callback. |
| roza | eyebrow_raise | 1.1 | suspect: visible-method exposure streak; actor present from L25 | Reserved questioning head tilt with a long appraisal hold; independent eyebrow artwork remains missing. |
| roza | approval_smile | 1.65 | accept: witness vote accepted; success: SUCCESS phase; actor present from L25 | Tiny approving nod and relaxed arms; the fixed painted mouth does not become a facial smile. |
| hugo | grand_entrance | 2.0 | enter: first witness creation; actor present from L21 | Gather the cape, open a grand two-arm presentation, let the hat ribbon overshoot and settle. |
| hugo | premature_bow | 1.5 | accept: witness vote accepted; actor present from L21 | Bow too confidently, hold, then lift the head suddenly to check whether applause has started. |
| hugo | ribbon_tangle | 1.75 | reveal: method exposed; suspect: visible-method exposure streak; actor present from L21 | The hat ribbon swings across his head; he catches at it, disentangles and regains composure. |
| hugo | honest_help | 1.6 | interact: inspect/select this witness card; actor present from L21 | Step out of presentation mode and extend both hands low to support someone else’s work. |
| hugo | shared_bow | 2.05 | success: SUCCESS phase; actor present from L21 | Invite a partner with one open arm and bow together at a gentler, respectful pace. |
| caramelka | walk | 1.0 | Goat route moving in L06/L10/L22 | A four-legged diagonal walk with a grounded rise/fall and delayed bell swing. |
| caramelka | idle_chew | 2.35 | Goat planning idle, alternating with idle | Small chewing head beats and a relaxed tail swish; no independently deforming jaw is present. |
| caramelka | sniff | 1.35 | Show/rehearsal or goat selection without nearby paper | Extend the muzzle, take two small inquisitive sniffs, then pull back. |
| caramelka | nibble_attempt | 1.65 | NOT REACHABLE: only L22 has goat+paper; route stays at least 10 cells away, trigger needs ≤5 | Reach to the paper, try two tiny nibbles, then withdraw; never modifies paper state. |
| caramelka | surprised_stop | 0.85 | method_exposed with goat present | Plant the front hooves, lift the muzzle abruptly and let the bell finish its swing. |
| caramelka | cargo_balance | 1.45 | NOT REACHABLE: no goat route can enter water-phase wait in L06/L10/L22 | Counterbalance a rocking load with four planted hooves and an opposing head motion. |
| caramelka | safe_rescue | 1.7 | Goat route_completed / SUCCESS first variant | A relieved little bound only after safe arrival, with four-foot recovery and bell follow-through. |
| caramelka | satisfied | 1.9 | SUCCESS repeated idle beat, second variant | Lift the chin proudly, swish the tail, then give a contented final nod. |

This is source-level dispatch traceability, not an assertion that 47 clips have been
observed in a campaign playthrough. Two clips (`nibble_attempt`, `cargo_balance`) have
no reachable authored campaign trigger with the current geometry/route requirements.
The remaining 45 have concrete reachable UI, phase or event conditions. Their exact
visual read and in-game timing still need the native-render review. No level geometry
or rule was changed just to make an animation play.

## Verification

`tests/test_character_acting.gd` reads the immutable asset specification and checks
all 47 additional clip IDs, cue reachability, real rig-bone targets, unique timelines,
evaluated motion, actor isolation, loop handoff, full pose reset and reduced motion.
The fixture run deliberately uses one SVG for all parts; it proves timeline and
hierarchy behaviour only. Use `--actual-rigs` after resource import to additionally
load every produced painted part rig.

```sh
/path/to/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script tests/test_character_acting.gd
/path/to/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script tests/test_character_acting.gd -- --actual-rigs
```

The isolated fixture pass on Godot 4.7.2 recorded 1069 checks, zero failures, 47 clips.
After resource import, the same test with `--actual-rigs` also passed 1069 checks
using all nine restored painted rigs. Existing puppet regression suites passed
43 checks / nine actual part rigs and nine edge checks, with zero failures and
no engine errors. Reports: `tests/reports/character-acting.json`, `puppet.json`,
`puppet-edges.json`. Automated motion checks do not accept composition, humour,
facial acting, two-angle art, real grip contact, or physical-device performance.

## Remaining art-dependent details

The painted head is a single part. `eyebrow_raise`, `approval_smile`, `glasses_wipe`
and `idle_chew` currently express their beats through head/body/hand motion; separately
articulated eyebrow, mouth, spectacles and jaw drawings remain necessary for literal
facial or object animation. `scarf`, `carry_note` and `recipe_flip` contain authored
reach/wrap/carry/page-turn motion, but the existing rigs lack separate scarf, note and
recipe-page artwork. These clips are playable body-acting implementations, not proof
that those specific visual details or the complete art specification are finished.
Gameplay staging must dispatch cues only in a suitable context: for example a goat’s
nibble_attempt cannot imply a new damaging interaction or replace an authored command.
