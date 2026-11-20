# RPG-7

Launcher model: **Ng1994**, [3D Model of RPG-7](https://ng1994.itch.io/rpg), downloaded as `Rpg.blend`. The author offers the model for games, animations, and visualizations and adaptation to game engines. The download contains no separate license document. The model is not claimed to be CC0; preserve the author's attribution and published terms, and do not redistribute it as a standalone asset pack.

Preparation for Shooter: retained authored bevel/subdivision detail, normalized the launcher to metre scale with a -Z bore, added attachment markers, rounded remaining machined edges, and exported `rpg.glb` (380,312 triangles including the loaded rocket). The loaded warhead and separate `rocket.glb` flight mesh are project-authored. The launcher model uses the original source geometry rather than an image-generated approximation.

Original-resolution **4096 × 4096 PBR textures**, CC0, from Poly Haven:

- [Metal Plate 02](https://polyhaven.com/a/metal_plate_02): diffuse, OpenGL normal, and AO/roughness/metallic maps.
- [American Walnut Veneer](https://polyhaven.com/a/american_walnut_veneer): diffuse, OpenGL normal, and AO/roughness/metallic maps.

Materials use anisotropic filtering and physical-scale triplanar mapping. Full-resolution textures are retained. Gunshot/reload audio reuses the project's existing launcher recordings; see `assets/weapon_audio/CREDITS.md` and `assets/arsenal/CREDITS.md`.
