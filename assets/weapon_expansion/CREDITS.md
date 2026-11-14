# Weapon expansion

The eight CC0 models are from the [3DAssets.dev Mega Weapon Pack](https://3dassets.dev/packs/mega-weapon-pack). The full-resolution meshes were reoriented and scaled for the game, with separate animated parts and custom wrist, muzzle, sight and reload markers.

| Weapon | Source model | Triangles |
| --- | --- | ---: |
| Carbine | Short Carbine | 42,484 |
| Bullpup | Bullpup Rifle | 45,284 |
| Compact SMG | Folding Stock SMG | 31,500 |
| Breacher | Pump Shotgun | 37,080 |
| Longshot | Chassis Sniper, Scoped | 94,284 |
| Scout | Semi Auto Marksman, Scoped | 77,072 |
| Squad LMG | Drum Fed Squad Gun | 52,952 |
| GPMG | General Purpose Machine Gun | 47,548 |

The 2K material maps are from Poly Haven, all CC0. [Metal Plate 02](https://polyhaven.com/a/metal_plate_02) supplies steel finishes. [American Walnut Veneer](https://polyhaven.com/a/american_walnut_veneer) supplies wood. [Rubber Tiles](https://polyhaven.com/a/rubber_tiles) supplies fine grain and scuffs for polymer and rubber surfaces. These sets provide color, normal and roughness maps. Each weapon retains its custom 1K UV2 ambient-occlusion bake.

[PAV Studio 03](https://polyhaven.com/a/pav_studio_03) by Grzegorz Wronkowski, CC0, supplies a 1K HDR reflection pass on weapon surfaces. Direct lighting and shadows come from the active arena.

## Replacement sights

- **Bullpup** uses the CC0 [3DAssets.dev Reflex Sight](https://3dassets.dev/assets/mega-weapon-pack-reflex-sight-27c159a4). The housing was widened and fitted with a transparent amber window and a centered emitter for first-person aiming.
- **Compact SMG** and **GPMG** use original Blender sight assemblies modeled from the supplied in-game references. Compact SMG has an open notch and protected front blade. GPMG has a raised aperture, separate rear ears, and a guarded front post.
- All three assemblies use the project's 2K [Metal Plate 02](https://polyhaven.com/a/metal_plate_02) color, normal and roughness maps. The reflex window and emitter use game materials.

The Ogg clips are from the project's [Classic Weapons Pack sound archive](../classic_weapons/CREDITS.md). Report pairs use different source takes or perspectives. Existing effects cover handling where the archive lacks a matching clip. The reports are level-matched and the long takes have shortened tails for sustained fire.

| Weapon | Local report | Positional report | Reload and action |
| --- | --- | --- | --- |
| Carbine | 556 Ext Med1p 002 | M16 fire 01 | AK-102 fast reload 01 |
| Bullpup | 556 Ext Med1p 005 | G36C fire 01 | AK-102 fast reload 03 |
| Compact SMG | MPX Fire 1 | MPX Fire 3 (mono mix) | MPX empty reload 01 |
| Breacher | Existing R11-48 shotgun | Existing Saiga 12k | Existing shell insert and pump |
| Longshot | 762 Ext Med1p 006 | 762 Ext Close 006 | Existing M700 reload and bolt |
| Scout | 762 Ext Med1p 003 | FAL fire 3p close 01 | Existing M14 reload |
| Squad LMG | 762 Ext Med1p 007 | 762 Ext Close 007 | AK-102 empty reload 02 |
| GPMG | 762 Ext Med1p 001 | M14 fire 05 | Existing M14 reload |

Both GPMG reports are pitched down three semitones and equalized for a deeper tone.

See [weapon audio credits](../weapon_audio/CREDITS.md) for the Breacher's reused Freesound recordings.
