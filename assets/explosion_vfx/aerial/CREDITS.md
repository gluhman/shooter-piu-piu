# Aerial explosion flipbook

Colour atlas and paired optical-flow map: [Arnklit, Godot Particle Flipbook Smoothing](https://github.com/Arnklit/godot_particle_flipbook_smoothing/tree/27a378247e7689b6f276ba2f1a1cb2ef97de33bb), CC0 1.0 Universal (bundled LICENSE.txt). Upstream credits the original sequence to Unity Labs Paris / Thomas Iche, from [Unity’s free VFX sequences](https://unity.com/blog/engine-platform/free-vfx-image-sequences-flipbooks). The 2048×2048 atlas contains 25 frames on a 5×5 grid. These are baked simulated fire/smoke sprites, not runtime volumetric fluid simulation.

Technique reference: [shady poly — Make Realistic Explosions in Godot!](https://www.youtube.com/watch?v=ySGnLmqvj8c). The implementation uses paired optical-flow frame blending, nonlinear playback, thermal colour, image-derived smoke shading/backlight, soft scene-depth intersections and a separate heat-refraction pass. No paid project files or code from the tutorial were downloaded.

`masks.png` is derived locally by `scripts/prepare-explosion-masks.gd`: R heat estimate, G pseudo-depth, B luminance, A coverage. These are image-based estimates rather than the tutorial’s simulation-rendered depth/normal passes. Existing PYROLUX Lite supplies ground-only dust, thin sparks and the brief blast light under its bundled MIT license. Gameplay blast damage, radius, fuse and networking are unchanged.

Source hashes (SHA-256):

- `explosion.png`: `b926336696561bbac6801ded500ff2b070756d58246bfab648154b6e940398d7`
- `flow.png`: `f9138166331aa2854f7d755f438044053291ffd5303de8b11daf2a142e4bcf41`

The current presentation uses a seven-second rise-and-dissipate sequence: fast fireball, slower rolling smoke, buoyant lift and expansion, then a final 1.6-second fade. Playback stops short of the atlas tail so the smoke does not dissolve at ground level before lifting.
