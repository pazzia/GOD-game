# Semyon cutout rig handoff

Created with built-in imagegen from this project's own Semyon identity reference. Exact generation prompt and source-output path are in parts.png.json. The1254×1254 sheet is nine separately painted body/costume pieces, not slices of an assembled character.

Runtime parts: head (hair/spectacles/neck), torso, left_arm, right_arm, left_leg, right_leg, cape (short ordinary navy vest back), accessory (ochre toolbelt/pouch), prop (yellow folding rule).

Actual build/semyon-rig-assembly.png was inspected twice. The first assembly put the screen-left hand behind the vest; its draw order was corrected so pinching fingers touch the left rule end. The screen-right open palm supports the other end. Neck/collar, solid shirt shoulders and both trouser/boot legs overlap without gaps. Rule is parented to right_arm; belt/back/head/arms to torso. Canvas1400×1400, feet_origin[700,1320], nominal_height1320. Alpha exports and assembly writes are atomic and Pillow-load-verified.

The soft circular cloth shoulder overlaps are deliberately visible as cutout joints; Designer/Manager should inspect suspect/reveal motion for excessive exposure. Native eight-state/full-cycle animation and profile/back art are not claimed complete. Runtime_animation_verified remains false; angles is empty. Re-running export.py resets assembly status until the regenerated preview is reviewed.
