# Terrain3D grass brush objects

Derived from the existing `assets/arena_props/grass.glb`: Poly Haven [Grass Medium 01](https://polyhaven.com/a/grass_medium_01), by Rico Cilliers and Rob Tuytel, [CC0](https://polyhaven.com/license).

The original embedded diffuse/opacity, OpenGL normal and roughness images are extracted unchanged. The small-b and tall-a tuft meshes are centered in X/Z, rooted at Y=0 and scaled to 0.20 m and 0.70 m. `grass.gdshader` adds root-anchored wind, per-instance color, alpha scissor and leaf backlighting. No collision is included.

- `grass_short.tscn` / `grass_tall.tscn`: reusable mesh objects.
- `grass_short.tres` / `grass_tall.tres`: Terrain3D mesh brush assets.
- `grass_brushes.tres`: Terrain3D asset library containing both brushes.
- `grass_short.res` / `grass_tall.res`: prepared, normalized mesh resources.

Rebuild the mesh objects and material with `godot --headless --path . --script res://scripts/prepare-terrain-grass.gd`. The checked-in brush resources reference those stable scene paths.

## Dense lawn brushes

All outdoor maps use original procedurally authored tapered blade meshes (`dense_grass_short` / `dense_grass_tall`) and `dense_grass.gdshader`. The short brush contains 32 blades, rooted at Y=0 with a maximum height of 20 cm; the 70 cm brush supplies occasional taller accents. No external mesh, texture or shader code was copied for these brushes.

Technique reference: [StayAtHomeDev grass tutorial](https://www.youtube.com/watch?v=3ftcGTp-Se8), including instancing, root-to-tip gradients, world-space colour variation and two-sided lighting. [Creator project page](https://stayathomedev.itch.io/stylized-grass-shader). Terrain integration reference: [Gamefromscratch Terrain3D 1.1.0 overview](https://www.youtube.com/watch?v=kD6GCH1odnk). The existing Terrain3D addon remains at 1.1.0 under its bundled MIT license.

Regenerate with `godot --headless --path . --script res://scripts/prepare-dense-grass.gd`. The runtime uses Terrain3D mesh instancing, root-anchored wind and distance culling with grass shadows disabled.

Grass geometry is refined to 7–14 mm leaf width with a stronger natural bend. The supplied meadow photograph informed the olive-green and dry-straw palette; it is a visual reference and is not shipped as a texture.

Dry-tip colour is sampled from undeformed geometry before wind or distance fading. Soft upward volume normals keep the lighting consistent between the front and back of each fine blade.

## Denser lawn and volume shading

Visual reference: [How I made better foliage than 99% of games — kodiakwhale](https://www.youtube.com/watch?v=GOfttJQ-FGw), grass section from 0:19 and tree section from 2:48. Public preview frames were reviewed; the colour/normal treatment is adapted to this project's thin meadow grass and existing palette. No tutorial assets or shader code were copied.

The lawn grid is 18 cm; Farpost gets a deterministic, mask-clipped infill. The near short brush has 32 blades / 96 triangles, and the native far LOD contains 32 matching roots/tips / 32 triangles. Curves simplify at 32 m; final culling is at 95 m with shader sinking from 65 to 90 m. The shader uses root-anchored colour patches, a mild travelling gust, base occlusion and soft volume normals. The original 7–14 mm blade width is retained. Pine needle cards use `canopy.gdshader` with the same volume-lighting idea and the existing Forest texture atlas.

[Terrain3D 1.1.0 mesh LOD API](https://terrain3d.readthedocs.io/en/stable/api/class_terrain3dmeshasset.html).
