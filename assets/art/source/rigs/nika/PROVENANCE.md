# Nika part rig: production record

Original project artwork generated with the built-in image generation tool on 2026-10-23, using this project's own characters/nika.png as identity reference. No external stock, franchise art or third-party asset source was used.

Source: parts.png and exact prompt parts.png.json. The first mechanical composition revealed inward-crossing arms. A targeted built-in image edit mirrored the contents of the two arm cells while preserving the other seven pieces; parts_v2.png and parts_v2.png.json are retained. Runtime exports use parts_v2.png. The source images are separately drawn components, not nine crops of an assembled full-body image.

Nine actual runtime parts: head, torso, left_arm, right_arm, left_leg, right_leg, cape (teal overall backpanel/straps), accessory (belt toolpouch), prop (notebook). Costume follows the actual reference's mustard shirt and teal overalls, without an invented jacket.

Authored atlas boxes, alpha-trim records, PNG dimensions: parts_metadata.json. Anatomical joint/pivot placements: config.json and ../../../characters/rigs/nika/rig.json. export_parts.py reproduces the lossless alpha exports and mechanical assembly. It writes only this actor's files; no shared atlas metadata or runtime code.

Actual static image inspected: game/build/nika-rig-assembly.png. Calibrated neck/shoulders/hips overlap; both elbows bend outward; pencil is visible in the left hand and notebook in the right; toolpouch follows torso. Head and arms are parented to torso; notebook follows right_arm. All parts were validated as complete RGBA PNGs with IEND and nonempty alpha. Evidence hashes: VALIDATION.json.

Acceptance scope: static assembly only. Native AnimationPlayer pose review, continuous full-cycle animation review and genuine front/profile/back direction artwork remain outstanding. runtime_animation_verified:false and angles:{} are intentional.
