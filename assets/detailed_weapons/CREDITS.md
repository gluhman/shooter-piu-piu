# Downloaded weapon replacements

## Superseded M4A1 / Carbine

[M4a1 Weapon on Blendkit](https://www.blendkit.com/asset-gallery-detail/e9982d49-ea63-4ec3-b4e7-476e56a78ba0/), asset version `0aaa26cf-4e50-4863-97f3-7fe30e13a149`, downloaded 20 November 2026. The provider marks this asset **CC0**. Original 2048×2048 base colour, metallic, roughness and normal maps are retained. Individual magazine and charging handle remain articulated. A small machined-edge bevel and a receiver-mounted collimator were added for this game.

## M249 / GPMG

[M249 SAW Machine gun by NoBE Aubé](https://www.blendkit.com/asset-gallery-detail/6b3ab3d4-e6f7-4623-a808-0d84eccfda69/), asset version `f87e40fb-d7e7-4a49-b153-a1444dc1a044`, downloaded 20 November 2026 through the provider's free anonymous download API. Source: Godot GLB, 230,013 source polygons (741,661 exported triangles with evaluated detail), baked 2048×2048 materials. The complete authored rail, optic mounts and attachments are retained; the ammunition bag is grouped for reloading.

License: **Blendkit Royalty Free**, not CC0. See [license](https://www.blendkit.com/docs/licenses/) and [licensing FAQ](https://www.blendkit.com/docs/licenses/licensing-faq/). Use as incorporated game content; do not resell this model as a standalone asset or asset pack. Commercial game distribution must comply with the provider's restriction against easily extractable assets. This replacement is shared by the M249 and generic GPMG slots.

## Other replacement meshes

[3D Low Poly Guns Pack by Polyy.AI](https://polyyai.itch.io/3d-low-poly-guns-pack), downloaded 20 November 2026 as `3D_low_poly_guns_pack.zip`. **CC0**; original notice is [POLYY-LICENSE.txt](POLYY-LICENSE.txt). These are AI-generated stylized meshes, approximately 55,000–65,000 triangles each, with original embedded 1024×1024 PBR images. They are not 4K textures.

| Game slot | Source mesh |
| --- | --- |
| Bullpup (superseded) | bullpup_rifle |
| Compact (superseded) | compact_submachine_gun |
| Shotgun / Breacher | pump_action_shotgun, full-length / short variant |
| Longshot / Scout | bolt_action_sniper_rifle, full-length / compact variant |
| RPK | wood_furniture_assault_rifle, long variant |
| Launcher | revolving_grenade_launcher |

Conversion: `scripts/art/prepare_detailed_weapons.py`. Metres, +Y up, -Z bore; source orientations are normalized individually. Width and height are corrected independently where stylized proportions would produce oversized grips or receivers. Moving magazine and pump faces preserve source UVs. Sights remain part of their complete imported assemblies. Model-local markers describe muzzle, grips, sights and reload points; the full native gloves are refitted separately in `assets/weapon_contacts.json`.

The revolving launcher's drum and upper frame are fused in the source. This assembly remains intact during reload; a separate project-authored 40 mm round follows the loading hand. The M249's deployable stand clamp is seated against the downloaded barrel, and uses that same attachment point for mounted firing.

The oversized stylized RPG candidate was rejected. The detailed Ng1994 RPG with 4K Poly Haven materials remains in use; see `assets/rpg/CREDITS.md`. AK-47 and Desert Eagle meshes are unchanged. Authentic Stein classic weapons remain separately credited in `assets/classic_weapons/CREDITS.md`.

## User-supplied replacements, 22 November 2026

Carbine, Bullpup, Compact, TEC-9, MAC-10 and MP5 now use the user-supplied Sketchfab models. The earlier Carbine/Bullpup/Compact sources above document the superseded assemblies. Current authors, source links, licenses, optic assignments and conversion notes are in [replacement model credits](../replacement_optics/CREDITS.md). `m1_scope_base.glb` derives from the project-authored arsenal M1 with its fused optic removed; its new scope is credited there too.

## Second user-supplied batch, 22 November 2026

The following sources replace the remaining assemblies listed above. Attribution and terms are embedded in the user-supplied GLBs.

| Game slot | Source | Author | License |
| --- | --- | --- | --- |
| M1 | [M1 Garand ( US Rifle, Caliber .30, M1)](https://sketchfab.com/3d-models/m1-garand-us-rifle-caliber-30-m1-1be4bb0f8c05423abdccb50b779de6e6) | Sky_Hunter (https://sketchfab.com/Sky_Hunter) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| RPG-7 + projectile | [RPG_7](https://sketchfab.com/3d-models/rpg-7-625b550f52a04068b943837558b5a582) | Ranger_08 (https://sketchfab.com/AnilkumarG) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| M79 | [Grenade-launcher M79](https://sketchfab.com/3d-models/grenade-launcher-m79-ea54d16860c14dffaede1e50a4f19a36) | balaganila (https://sketchfab.com/balaganila) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| GPMG | [low-poly MG42](https://sketchfab.com/3d-models/low-poly-mg42-0bd5519f73a6471287798073dba523fe) | D_U (https://sketchfab.com/DU1701) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| M249 | [M249](https://sketchfab.com/3d-models/m249-b1e60faa37de4461822103fe38e5c9ce) | Dmitriy Korotkov (https://sketchfab.com/ArtDmitriyK) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| SQUAD LMG / rpk | [LMG](https://sketchfab.com/3d-models/lmg-8c24d7374ea64bdab1c30f49c69d5ed8) | DJMaesen (https://sketchfab.com/bumstrum) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| Breacher | [Tactical Pump-Action Shotgun – Game Ready 4K PBR](https://sketchfab.com/3d-models/tactical-pump-action-shotgun-game-ready-4k-pbr-fee8dc96638d462f9340f79bc9e09709) | D.Acee (https://sketchfab.com/D.Acee) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| Shotgun | [Shotgun](https://sketchfab.com/3d-models/shotgun-bec49e6f99e347cbb60e6390b2c4202c) | Jonathan Steylaerts (https://sketchfab.com/JonathanSteylaerts) | CC-BY-NC-4.0 (http://creativecommons.org/licenses/by-nc/4.0/) |
| Scout | [Steur Scout](https://sketchfab.com/3d-models/steur-scout-13cf5bc242fc41e0aa94e8995f0e3c12) | Revver (https://sketchfab.com/Revver) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| Longshot | [AR-50 .50 BMG Sniper Rifle](https://sketchfab.com/3d-models/ar-50-50-bmg-sniper-rifle-432d100da929465bb35c94af32b5a62c) | moaazhesham7 (https://sketchfab.com/moaazhesham7) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| M700 | [Remington M700](https://sketchfab.com/3d-models/remington-m700-1b051311ef524c62a92514883a57f44f) | CannonMonkey (https://sketchfab.com/CannonMonkey) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |

Conversion: `scripts/art/prepare_support_weapons.py`, using shared helpers from `prepare_replacement_weapons.py`. Source UVs/PBR textures are retained. Axes, physical scale, surface-contact markers and moving parts are authored for the game. Source display ammunition/helper meshes and duplicate RPG assemblies are omitted. The M1 clip is seated in its receiver, shotgun pumps and rifle bolts are detached, the M79 barrel has a break-action hinge, and feed boxes remain articulated. M700 and the single-shot AR-50 retain their stocks/receivers intact and use a cartridge-loading presentation instead of detaching solid stock geometry. The M249's permanently extended source bipod is replaced by the game's deployable stand.

GPMG now has its own MG42 mesh; it no longer shares the M249. SQUAD LMG retains the internal `rpk` slot. The loaded RPG warhead and flying projectile use the same supplied geometry; the projectile origin and exhaust marker follow its tip and tail. M700/Scout retain their supplied optics. The M249 red-dot housing, lens and dot are removed; its sight markers now follow the open iron-sight view. M1’s scope is centered over the bore on project-authored adapter feet. The RPG reload carries the supplied projectile to the front of the tube and inserts it along the bore before returning the support hand to its grip. Longshot and M1 use the previously supplied Night-Force and Accushot models, credited in [replacement optics](../replacement_optics/CREDITS.md). Gun statistics and ballistic tuning are unchanged.

The Jonathan Steylaerts Shotgun model is **CC BY-NC 4.0** (noncommercial). Its converted mesh and textures retain that restriction. Other models in this batch are **CC BY 4.0**. Preserve the source links, author credits and linked license notices when distributing derivatives.

GPMG now uses 4K Poly Haven metal/wood finishes and a first-person Studio Small 09 HDRI reflection pass. See [surface credits](gpmg_pbr/CREDITS.md). M249 attachment removal preserves whole source components, including its carry handle, rail and receiver.
