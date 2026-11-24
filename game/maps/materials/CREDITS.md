# Shared map surface finish

Original project implementation adapted from the Refinery weathered material and the project's existing bullet-hole shader. Existing map textures remain under their original licenses; see [asset catalog](../../../docs/assets.md) and each map's credits. No new third-party texture or HDRI is included.

Technique references:

- [This Is How to Make Game Textures With AI — Can It Code?](https://www.youtube.com/watch?v=_rMMP7GPgt4): public description/chapters for triplanar projection, variation, grime and worn edges. The project reuses its licensed PBR maps rather than tutorial asset downloads.
- [Lighting Comparison in Godot 4 | VoxelGI vs LightMapGI — LoopDev](https://www.youtube.com/watch?v=FAk3MLd8YB4): local bounce-light comparison. Existing map-owned GI and dynamic outdoor lighting remain in place.
- [How I made better foliage than 99% of games — kodiakwhale](https://www.youtube.com/watch?v=GOfttJQ-FGw): visual grass/canopy reference; see [foliage credits](../foliage/CREDITS.md).

`surface_finish.gd`, `weathered_surface.gdshader` and `beveled_box.gd` are project-authored. Overrides are instance-owned; original mesh resources, atlas UVs and collision stay intact.
