# Marfa cutout rig handoff

Created with built-in imagegen from this project's own Marfa identity reference. Exact generation prompt and source-output path are in parts.png.json. The 1254×1254 parts sheet contains nine separately drawn items; it is not sliced assembled character art.

Runtime parts: head, torso, left_arm, right_arm, left_leg, right_leg, cape (ordinary short work-coat back), accessory (red rope sash), prop (working rope coil).

Actual build/marfa-rig-assembly.png was inspected twice. The first assembly exposed an overlong collar and overly broad arms; the head was lowered40 reference pixels and arm sizes/shoulder positions calibrated. The final assembly has coherent neck/collar, solid overlapping shoulders, two boots under the apron hem and a rope suspended from the screen-right fist. Rope is parented to right_arm; sash/back/head/arms to torso. Canvas1400×1400, feet_origin[700,1320], nominal_height1320. Alpha exports and assembly writes are atomic and Pillow-load-verified.

This accepts the static assembly only. Native full motion, the eight state poses and actual profile/back art remain unverified. Re-running export.py deliberately resets the status to assembly_review_pending until the newly exported assembly is reviewed.
