# Grab3D soldier player variants

The playable body, face, helmet, carrier, clothing, boots and their original 4096 × 4096 base-color, normal and metallic/roughness maps derive from [Soldier by Grab3D](https://grab3d.com/models/characters/soldier/), **CC0 1.0**. The publisher identifies the source as **AI-assisted**: a Meshy-generated base, subsequently cleaned, scaled and checked in Blender. [Original license and disclosure](grab3d/LICENSE.txt), [publisher manifest](grab3d/source_manifest.json).

The full-detail source was fitted to the native Mesh2Motion skeleton. The game models retain 774,948 triangles each after replacing the source's unarticulated hands. Base/FFA and blue use the original green camouflage; only red in team modes uses the black fabric shader. The black material desaturates/darkens clothing while preserving the original texture variation, normal/roughness maps and exposed skin. The head is separated for first-person hiding and shadow casting. The carrier is part of the source body mesh and remains visible after its ballistic plates are depleted; armor state and damage rules are unchanged.

The articulated gloves derive from [Military tactical suit (LowPolyGameReady)](https://sketchfab.com/3d-models/military-tactical-suit-lowpolygameready-ef698ce36b1545a78ce592dd3db4c7ed) by **DanlyVostok (1799danly)**, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Continuous wrist cuffs bridge each glove to the new sleeve with blended forearm/hand weights. Their geometry, UVs, textures and finger weights are adapted from the previous operator and fitted under the new sleeve cuffs. The retained original model is the [glTF edition from 3d-fps](https://github.com/cktang88/3d-fps/blob/main/public/assets/models/characters/soldier_tac.glb). This attribution applies to both game variants; the complete combined character is therefore not wholly CC0.

Both models use Mesh2Motion’s native **66-bone human skeleton**, all 40 finger bones and [14 original clips](../animations/mesh2motion/CREDITS.md). Rest transforms, hierarchy and animation data are preserved; arms/fingers use the existing weapon IK. Team outfits also apply to bots and corpses. [Build pipeline](../../scripts/art/README.md).

Legacy outfit resources remain in the repository. Their 2K fabric maps include detail from [Fabric 030](https://ambientcg.com/view?id=Fabric030), ambientCG, CC0. The material/lighting resources below are retained for the watch, gallery, legacy assets and map lighting; they do not replace Grab3D's original 4K body textures.

## Poly Haven materials and lighting

All assets below are CC0. Original download URLs, MD5 checksums and byte sizes for the new 4K files are recorded in `textures/hd/sources.json`.

- [Fabric Pattern 05](https://polyhaven.com/a/fabric_pattern_05), Rob Tuytel: 4K color, OpenGL normal and ARM maps. The scarf shader neutralizes the original pink dye while retaining 4K yarn variation; the kit uses normal/ARM detail directly. Clothing layers neutralized 4K yarn color and normal detail over the existing UV-aligned maps. ARM stores ambient occlusion, roughness and metallic in RGB.
- [Fabric Leather 02](https://polyhaven.com/a/fabric_leather_02), Rob Tuytel: 4K diffuse, normal, ARM and displacement maps. Boot uppers use the leather diffuse and normal maps with matte roughness. The protective pads use normal detail and restrained height/parallax bump; rigid kit uses subtle leather normal and roughness detail.
- [Digital Wrist Watch](https://polyhaven.com/a/digital_wrist_watch), Adrian C: watch case fitted to the left cuff of the existing skeleton.
- [Studio Small 09](https://polyhaven.com/a/studio_small_09), Sergej Majboroda: 4K HDR panorama for the reproducible operator gallery.
- [Overcast Industrial Courtyard](https://polyhaven.com/a/overcast_industrial_courtyard), Grzegorz Wronkowski: upgraded shared outdoor ambient/reflection panorama to 4K. [Map lighting](../../game/maps/lighting/CREDITS.md).
