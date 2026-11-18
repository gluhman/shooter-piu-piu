# Mesh2Motion skeleton and motion

Source: [Mesh2Motion](https://github.com/Mesh2Motion/mesh2motion-app), revision `bcb014ea25e44f76b3add78463f72d1faec16418`. Models, rigs and animations are [CC0](LICENSE-CC0.MD); the application code is MIT.

Both operator variants use the native `static/assets/human/skeleton.glb` human rig: 66 bones, including ten complete finger chains with three phalanges and an end bone each. Names, hierarchy, bind orientations and inverse binds are preserved. `rig.json` records the source revision and transforms. The source `model.glb` mannequin is retained in `reference.glb` for independent comparisons.

The following source clips are used directly, without retargeting:

- `rifle-idle`, `rifle-walk`, `rifle-run`, `sprint`
- `crouch-idle`, `crouch-walk`
- `jump-start`, `jump-air`, `jump-land`
- `rifle-reload`, `rifle-fire`
- `walk-backwards`, `strafe-left`, `strafe-right`

The upstream `AnimationUtility.clean_track_data` keeps all rotations and pelvis positions, matching Mesh2Motion’s animation browser. Original key times and values are retained. The runtime library uses the same tracks, including torso and fingers; sparse tracks hold their last key instead of interpolating across the loop boundary.

The outfit’s original anatomical vertex groups are transferred to the native Mesh2Motion joints, with rigid-attachment corrections and new inverse binds. The old 88-bone hierarchy is not present in either final model. Weapon-specific IK, firing and reload timing remain a separate gameplay layer; the complete native fire/reload sequences can be viewed in the comparison scene.

[Rebuild and verification instructions](../../../scripts/art/README.md).
