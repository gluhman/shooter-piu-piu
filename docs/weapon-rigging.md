# Weapon grips, finger contacts, and clearance

Every new firearm must ship with a fitted grip profile in `assets/weapon_contacts.json`. A pair of wrist markers or a shared finger curl is not an acceptable finished grip. This policy applies to local first-person hands, remote players, bots, and both operator variants.

## Model contract

Use metres, +Y up, and a -Z bore. Retain the original model's scale and orientation in the profile conversion; do not mix source coordinates with held-weapon coordinates. The weapon needs `Muzzle`, rear/front sight, trigger grip, support grip, and reload attachment points. Imported models can retain their source transforms; the profile stores contacts in that model's local space.

Each hand profile includes:

- A **palm surface point** on the intended grip or handguard. This is a point on the weapon, not the wrist joint or the centre of the glove.
- Separate **skeletal palm offset** accounting for glove thickness and the wrist-to-palm length. Placing the skeletal palm centre directly on a metal surface embeds half the hand in it.
- Five named **surface contacts**: thumb, index, middle, ring, and pinky. The trigger finger targets the trigger region; the support fingers wrap the handguard. Do not use the exposed barrel, sight, magazine, or empty space as a substitute for the intended grip.
- A palm orientation, bounded proximal/middle/distal flexion, thumb opposition, and finger splay fitted to those contacts.
- A conservative solid grasp envelope and clearance measurements. A target on the far surface must not pull the intermediate phalanges through the weapon.

`weapon_contacts.gd` converts these contacts and fitted poses into wrist-local markers. `operator_pose.gd` supplies full hand target transforms to GodotIK 1.3.1 and applies the per-weapon finger pose. Each arm has a three-bone chain and an explicit elbow pole. It blends the support hand open during reloading. Geometry fitting belongs in the art pipeline; do not run triangle searches or full glove collision fitting every frame.

Profile `palm` and digit points use the imported model's local coordinates. `palm_offset` uses physical metres in its rotation-only frame; it must not be multiplied by the model's import scale. `basis` stores the palm socket axes, and `curl`/`splay` use radians. `model_frame` records the model-to-weapon-view transform used by the offline verifier; `volume_planes` use that view's metre coordinates. Keep these fields together when changing model transforms. The production target is 2 mm of full-glove clearance against the conservative grasp envelope, followed by rendered review against the actual mesh.

## Fitting and collision rules

Fit the actual articulated glove mesh, including palm tissue and intermediate finger segments. Testing only fingertip distances is insufficient. Construct a conservative convex grasp envelope around the full grip/handguard cross-section, retaining enough length to cover all fingers. Evaluate the skinned glove vertices against this solid volume and include clearance in the fitting objective. Check the complete vertex set after fitting, rather than only the samples used by the optimizer.

Fit the support fingers across the handguard, with the palm facing straight up and the handguard resting on the palm tissue. Keep the thumb relaxed along the left side at approximately the curled fingers’ height, and curl the fingers around the opposite side. A forward grip instead requires a side-facing palm wrapped around the handle; Compact SMG, Bullpup and RPG use this separate `vertical_grip` profile. In the held-weapon frame, the left fingers must cross toward +X from the left side; a negative finger-axis X component produces a right-side grasp even when clearance passes. Both the offline skin test and the final IK test enforce this for handguard grasps. A longitudinal finger pose that merely touches the barrel with the fingertips can leave the palm hanging below it. For short pistols, fit the support palm to the outside of the firing glove and review the contact between both hands. Avoid a single convex hull that fills the firing fist's empty spaces and pushes the support palm away. Keep the solid pistol-grip envelope separate from the trigger-guard opening. Inspect short weapons especially carefully: move the support point behind the muzzle rather than letting a long finger reach in front of it. Preserve terminal finger-bone skin weights in fitting and verification; remapping a weighted end bone to the hand gives a false clearance result.

Keep the hand's wrist-to-middle-knuckle axis close to the elbow-to-wrist axis. Target at most 30 degrees of wrist bend in the ready pose; forearm roll is separate from wrist flexion. If contact and a relaxed wrist cannot both be achieved, move the support grip, adjust weapon carry or elbow position, or author a different grasp. Do not hide a bad wrist behind a cuff or permit a solver to twist it until the fingertips happen to touch.

Check axial palm roll separately from wrist bend. In the held-weapon view frame the trigger hand must keep its thumb axis up, fingers forward, and palm facing the grip. `weapon_grip_volume_test.py` rejects a reflected basis or a projection below 0.8 on any of those three axes. A low wrist-bend measurement alone can still conceal an upside-down palm. The GPMG trigger grip uses a tightly bounded upright basis and full-skin fitting to prevent that failure.

Run `tests/operator_model_test.gd` as well: it samples the final native hand-bone pose after IK for every weapon on both teams. A correct target basis does not establish that the rendered hand actually follows that orientation.

The GPMG support palm belongs under the handguard behind the bipod, within 25 mm laterally of the weapon centreline. Both profile and final-pose tests enforce this. Exclude bipod legs from the handguard cross-section; a clearance projection must not silently move the whole palm to the side. Review first person at the gameplay FOV and near plane, with studio-map colliders prevented from creating a false close-range muzzle convergence.

Finger joints may flex and splay within anatomical bounds; bone lengths and glove scale must remain unchanged. The palm must remain outside the solid gun. All phalanges must wrap around its volume with positive clearance, including when the fingertip touches the opposite side. Avoid fitting against trigger-guard voids as though they were a solid grip; inspect the actual trigger region separately.

## Required review before accepting a gun

1. Inspect the intended grip regions and mark the model surface contacts. Rebuild the grasp envelope after changing a mesh, its scale, or attachment positions.
2. Fit the native operator's hand frame, finger joints, and palm offset against the contacts, full glove clearance, and forearm direction. Check both team variants.
3. Run `tests/weapon_contact_gallery.tscn` in the renderer. Inspect both sides of the trigger hand and support hand, including the underside and back of the wrist. Review the entire gun, not just the silhouette from one side.
4. Check first person and third person in ready, ADS, crouch, recoil, reload, weapon switch, and empty/reloaded states. Test moving pump/bolt/magazine parts. Keep fingers clear of the muzzle and ejection port. A support hand leaving the weapon during reload must not drag the contact pose through the receiver.
5. Run the relevant combat test and the grip checks. Review full glove penetration and wrist angles alongside palm/fingertip errors. A small fingertip error alone does not pass this policy.
6. Keep the profile, source attribution, export inclusion, and gallery coverage in the same change. Do not silently fall back to a shared curl for a new production firearm.

The JSON file is explicitly included by the production export presets. Add new third-party model and texture sources to `docs/assets.md` and preserve their terms beside the asset.

## Reproducible tooling

The fitting reference is generated from the exact imported meshes and the native 66-bone rig. Use `scripts/art/bake_weapon_contacts.gd` to measure the model-local surface regions, then run the rendered contact gallery to capture arm reach in the actual ready pose. Pass `-- --support-only --support-reference` to the Blender fitter to refit long-gun support hands while preserving trigger hands, pistol cups, and the separately authored GPMG grip. The Blender fitting tools use the existing articulated glove's skin weights and inverse bind matrices, not a substitute hand mesh. They optimize actual distal skin patches, test the full palm/finger skin, and choose a feasible elbow direction. Keep generated measurement files in temporary storage; the reviewed profiles are the production artifact.

A fingertip bone is not necessarily the fingertip skin surface on this fitted operator. Do not use a bone-to-surface gap as a stand-in for actual glove contact. The full skin result is the acceptance measurement.

## Arm solver and final-pose ordering

The full-body arms use [GodotIK 1.3.1](https://github.com/monxa/GodotIK/releases/tag/v1.3.1), following the explicit target-basis advice in [this discussion](https://godotforums.org/d/43019-full-body-fps-player-rig-control-over-arms-issues). Configure each hand effector with `FULL_TRANSFORM`, a three-bone upper-arm/forearm/hand chain, and a forearm pole constraint. Set bone indices explicitly when constructing nodes before they enter the tree; setting a name before the controller has a skeleton does not resolve the index in this addon version.

Body/locomotion and finger posing run first, then GodotIK solves the arms. Hurtboxes and verification sample `pose_finished`, which fires after the final arm modifier. Sampling the body's earlier `modification_processed` signal would observe an intermediate pose. The analytic arm path remains available for comparison and fallback, not as a second solver writing the same chains in a frame.

Для импортированных сборок `Grip` уже находится у поверхности хвата: при bake проба правой ладони сдвигается наружу только на 5 мм. Большой общий сдвиг может выбрать соседний пояс подачи, скобу или ресивер. Подгонка таких сборок использует полную кожу, трёхмерную цель для ткани ладони и авторские контакты пальцев с полным анатомическим диапазоном сгиба, а консервативный объём пистолетного хвата не заполняет пространство спусковой скобы.

For a full reference refit: bake with `-- --contact-surfaces`, fit support hands with `--support-only --support-reference`, and seed narrow wooden fore-ends with `--reference-seed carbine` when needed. Run `refine_support_fingers.py` in Blender against the exact triangle surfaces, then use `--thumb-height-reference` to match thumb height to the other fingers, dump the independently skinned hands with `tests/weapon_grip_volume_test.py --dump-contact-skin`, then run `finalize_support_contacts.py` in Blender. The finalizer authors the real palm/finger surface points while preserving the skeletal palm target and fitted joint poses. The independent test rejects penetration, a palm that floats away from its authored support surface, and a thumb that crosses the gun or rises above the curled fingers. `thumb_roll` supplies the thumb metacarpal opposition needed to relax the thumb along the left side at the curled fingers’ height without changing bone lengths or glove scale.

## Wrist surface continuity

`operator_wrist.py` corrects the packaged soldier wrist cuffs, and `package_grab3d_soldier.py` applies it during rebuilding. The sleeve-side skin weights blend under the uniform; the visible glove collar follows the hand so a rolled support palm does not pinch the wrist into a thin neck. The bridge is capped at both ends, extends under the sleeve and finishes inside the palm; the exposed join cannot reveal an open annulus. Its palm-side taper keeps clear of compact pistol grips. The donor glove’s recessed proximal cuff is trimmed and capped; the retained palm/finger vertices and weights and the native rig stay unchanged. Run `scripts/art/check_operator_meshes.py` to check watertight topology, internal palm overlap and both teams’ wrist cross-sections under a half-turn of palm roll, then review Carbine/M14 and contrasting foregrip/pistol/reload poses in the contact gallery.

For the AK-47, `refine_support_fingers.py -- --thumb-height-reference --thumb-height-offset -0.015 --weapons ak47` keeps the support thumb lower in first-person perspective. The profile records `thumb_height_offset_m` for repeatable rebuilding. Thumb-only refinement preserves the other finger measurements and reauthors the thumb surface contact. Review both ready and ADS views after changing this offset.
