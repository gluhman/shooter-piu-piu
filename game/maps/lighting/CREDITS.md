- [Overcast Industrial Courtyard](https://polyhaven.com/a/overcast_industrial_courtyard) by Grzegorz Wronkowski, CC0. The HDR panorama is blended into the shared outdoor sky's radiance pass for ambient light and reflections.

The 2.3.0 update uses the original 4K HDR download (see `assets/operator/textures/hd/sources.json`). The existing Sky3D radiance-only blend preserves the dynamic day/night sky. Office and turbine-hall bounce volumes were rebaked with `scripts/bake_arena_lighting.gd`; these are static environment GI volumes, while moving characters retain dynamic shadows.
