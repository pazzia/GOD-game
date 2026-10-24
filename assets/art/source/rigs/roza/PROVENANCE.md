# Roza part rig: production record

Original project artwork generated with the built-in image generation tool on 2026-10-23, using this project's own characters/roza.png as identity reference. No external stock, franchise art or third-party asset source was used.

Source: parts.png and exact prompt parts.png.json. This is an independently painted nine-part atlas, not nine slices of a complete figure. Identity follows the gray bob, black glasses, cream cravat, olive waistcoat, long plum coat and black lace-up boots in the reference.

Nine actual runtime parts: head, torso, left_arm, right_arm, left_leg, right_leg, cape (long split coat backpanel), accessory (wood/brass stamp), prop (tan paper folder). The coat backpanel is clothing, not an invented fantasy cloak.

Authored atlas boxes, alpha-trim records and dimensions: parts_metadata.json. Anatomical joint/pivot placements: config.json and ../../../characters/rigs/roza/rig.json. export_parts.py reproduces lossless exports and the mechanical assembly. It writes only this actor's files; no shared atlas metadata or runtime code.

Actual static image inspected: game/build/roza-rig-assembly.png. Shoulder pivots were calibrated to cover duplicate round attachment zones; folder is held in the screen-left hand and follows left_arm. The stamp stem was aligned to the screen-right grip and follows right_arm. Head/arms/coat follow torso; knee and neck overlaps remain closed. All nine runtime PNGs passed complete RGBA/IEND/alpha validation. Evidence hashes: VALIDATION.json.

Acceptance scope: static assembly only. Native AnimationPlayer pose review, continuous full-cycle animation review and genuine front/profile/back direction artwork remain outstanding. runtime_animation_verified:false and angles:{} are intentional.
