# Grab3D soldier integration

The current playable soldier is built with `fit_grab3d_soldier.py` (Blender) and `package_grab3d_soldier.py` (Python). It preserves the original 4K PBR maps and detailed body geometry, fits the limbs to the native 66-bone skeleton, separates the first-person head, and replaces the source hands with the previous operator’s articulated gloves. Packaging restores exact native bind matrices and copies the 14 original clips from the checked-in Mesh2Motion reference.

Inputs are retained outside the Godot project at `../art/player/`: `soldier_highpoly.blend` and `game_backup/operator_blue.glb`. The former is the prepared CC0 Grab3D source; the latter is the preserved glove donor before replacement. External donor images are resolved from `assets/operator/textures/`. The legacy recipe below can recreate the donor. Keep the source license/disclosure with exported assets.

```sh
blender --background --disable-autoexec --python scripts/art/fit_grab3d_soldier.py
python3 scripts/art/package_grab3d_soldier.py
python3 scripts/art/check_operator_meshes.py
# Reimport in the open editor, then:
godot --headless --path . --script res://tests/operator_model_test.gd
godot --headless --path . --script res://tests/operator_stance_test.gd
godot --headless --path . --script res://tests/mesh2motion_fidelity_test.gd
```

Blender outputs `../art/player/soldier_game_rig.blend` and an intermediate GLB. Packaging writes both `assets/operator/variants/operator_*.glb`; runtime `soldier.gdshader` retains green camouflage for base/FFA and blue, and applies black only to red in team modes. Vertex alpha stores the exposed-skin region, not opacity. `OperatorEyes` is a hidden skinned camera anchor. `ArmorState` tracks internal ballistic plates; the integrated carrier stays visible after armor is spent.

Validation on Godot 4.7.2 / Apple M5 Pro: 774,948 triangles per variant, five surfaces, normalized weights, articulated fingers, all original 4K maps, and 14 × 31 animation samples for both variants. `tests/operator_gallery.tscn` exercises real match actors, walking, crouching, three weapons, strafing and reloading. These geometry counts are not a performance benchmark.

# Legacy operator/glove donor pipeline

The checked-in models use Mesh2Motion’s native **66-bone human / all-fingers** skeleton. The old Mixamo rig is only an intermediate for recovering the source outfit geometry; it is not exported into either playable model.

Rebuilding requires Godot 4.7.2, Blender 4.5.1, Python 3 and Node 22.23 or newer. Run from the project root with `godot` and `blender` pointing to the installed applications. Intermediate files live in `/tmp`.

```sh
operator_project="$PWD"
python3 scripts/art/fetch_polyhaven.py
godot --headless --path . --script res://scripts/art/normalize_operator.gd
python3 scripts/art/build_operator_variants.py

git clone https://github.com/Mesh2Motion/mesh2motion-app.git /tmp/piupiu-mesh2motion
git -C /tmp/piupiu-mesh2motion checkout bcb014ea25e44f76b3add78463f72d1faec16418
cp scripts/art/rig_operator_mesh2motion.mjs scripts/art/mesh2motion_ts_loader.mjs /tmp/piupiu-mesh2motion/
cd /tmp/piupiu-mesh2motion
npm ci
node --experimental-loader ./mesh2motion_ts_loader.mjs ./rig_operator_mesh2motion.mjs
cd "$operator_project"
blender --background --factory-startup --python scripts/art/refine_operator_mesh.py
blender --background --factory-startup --python scripts/art/create_operator_kit.py
python3 scripts/art/apply_mesh2motion_rig.py
python3 scripts/art/check_operator_meshes.py
# With the interactive editor closed, import the new resources:
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://scripts/art/build_operator_motion.gd
```

Reuse the pinned checkout when repeating the recipe. With the editor open, use its targeted resource reimport instead of a second editor process.

`normalize_operator.gd` recovers meter-scale source vertices, UVs, normals and anatomical vertex groups. `build_operator_variants.py` assembles temporary geometry in `/tmp/piupiu-operator-input`; these are not game assets.

`rig_operator_mesh2motion.mjs` loads the upstream `static/assets/human/skeleton.glb`, keeping all 66 joint names, parents, local frames and inverse binds. It unposes the outfit geometry with dual-quaternion blending and anatomical segment-length fitting, then transfers the artist’s anatomical vertex groups to the native joints, with rigid-equipment corrections. Anatomical groups prevent the sleeve/clavicle and neighboring-finger leakage seen with proximity-only weighting on this layered outfit. Hard pads retain their anatomical side even when a strap crosses the model midline; they follow calf/forearm joints; patches follow their own anatomical attachment, not the pelvis. All ten fingers retain three phalanges and their end bones. The ankle and toe frames need different orientation corrections: rotating the toe frame like the ankle folds the boot toe underneath itself. The fitted trousers taper around the native leg axes instead of retaining the source outfit's wider leg spacing.

`refine_operator_mesh.py` welds coincident garment vertices, preserves UV seams and skin groups, and adds one subdivision level for smooth sleeves, hands and clothing. `create_operator_kit.py` then authors the cap, continuous blue goggles, headset, webbing and boot soles/laces directly in the **native bind frame**. Chest attachments inherit barycentric weights from the fitted vest surface. Local equipment contact occlusion is baked into vertex colors using 24 hemisphere rays per unique surface point; it does not replace the dynamic lighting or map GI. `apply_mesh2motion_rig.py` shares identical vertex corners and removes superseded buffers without reducing detail.

The 14 animation files come directly from `static/assets/human/animations`. `AnimationUtility.clean_track_data` is the same cleaning step used by Mesh2Motion’s animation browser: it retains every rotation track and pelvis position. There is **no motion retargeting, resampling, torso replacement, horizontal pelvis lock or jump-height clamp** in the conversion. The original key times and values are packaged into both models and the Godot library. Sparse tracks clamp at their ends like Three.js; Godot’s cross-boundary interpolation is disabled. GLB import uses 120 fps (a multiple of the source’s 24 fps), disables lossy animation optimization and retains immutable tracks.

`apply_mesh2motion_rig.py` writes both playable GLBs, `rig.json` provenance and the unchanged source mannequin with the same animations as `reference.glb`. The mannequin is a test asset. The runtime library preserves source motion before aiming, terrain correction, weapon IK and hit reactions. Weapon-specific firing/reload timing remains controlled by the existing weapon system; the native source fire/reload clips are available in both models and the comparison scene.

Body UV albedos remain 2K; shared Poly Haven fabric/leather detail color, normal, ARM and height maps and the HDRIs are 4K. The fabric and scarf shaders neutralize the original fabric’s pink albedo while retaining 4K yarn detail. Boots use a distinct leather material and modeled soles/lacing. Keep the original model and its attribution. Godot imports generated LODs, shadow meshes, named skins, mipmaps and regenerated tangents.

```sh
godot --headless --path . --script res://tests/mesh2motion_fidelity_test.gd
godot --headless --path . --script res://tests/operator_model_test.gd
godot --path . res://tests/operator_rig_comparison.tscn
godot --path . res://tests/operator_gallery.tscn
```

The fidelity test compares hierarchy, bind frames and 31 phases of every clip for both GLBs and the runtime library against the independently imported source mannequin. The comparison scene plays the source and both models at the same phase without gameplay modifiers, under the studio HDRI with shadows and SSAO. Space pauses, left/right select a clip, and B toggles the skeleton overlay. `check_operator_meshes.py` verifies normalized skin weights, indivisible pad triangles, intact boot volume and baked contact occlusion. The gallery uses actual game actors, weapons and all-finger IK under Poly Haven Studio Small 09.

Also run combat, shot collision, fieldworks and training-range tests. `operator_corpse_lan_test.gd` accepts `-- host|client SHARED_DIR PORT`; run both processes with the same directory and loopback port to verify production corpse RPCs. `combat_lan_test.gd` similarly uses host/shooter/observer roles. The native skeleton changes corpse pose arrays, so protocol 20 is required.

Static environment bounce lighting is rebuilt with the graphical Forward+ renderer using `scripts/bake_arena_lighting.gd`. See [animation notes](../../docs/animation.md) and [model attribution](../../assets/operator/CREDITS.md).
