# User-supplied weapon and optic models

Provided on 22 November 2026. Attribution below is embedded in the supplied GLBs.

| Game asset | Source | Author | License |
| --- | --- | --- | --- |
| tec9 | [tec-9](https://sketchfab.com/3d-models/tec-9-377b7dc278754029822563d56c1f986e) | Diamonddogkz (https://sketchfab.com/Diamonddogkz) | CC-BY-SA-4.0 (http://creativecommons.org/licenses/by-sa/4.0/) |
| mac10 | [Ingram Mac 10](https://sketchfab.com/3d-models/ingram-mac-10-a8d93858e7a2476db389ba3c05ca5a85) | Faheem Yusuf (https://sketchfab.com/FameProductions) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| mp5 | [MP-5](https://sketchfab.com/3d-models/mp-5-2d17bc9e70704dfb87864f2593f53418) | Buntollv (https://sketchfab.com/Buntollv) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| bullpup | [SUNDA MK2 300 Bullpup](https://sketchfab.com/3d-models/sunda-mk2-300-bullpup-1baf08fef1f745b59a7ccdee49452adc) | ErhanMatur (https://sketchfab.com/erhanmatur) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| carbine | [Ar-15](https://sketchfab.com/3d-models/ar-15-3a9d2f1ef1c64eccb3a2302164dd791b) | 3DYAROSLAV2 (https://sketchfab.com/3DYAROSLAV2) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| compact | [TPM SMG](https://sketchfab.com/3d-models/tpm-smg-b9e68645f0e048419f3fe84ebd58dd92) | TORI106 (https://sketchfab.com/TORI106) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| reflex | [Red Dot](https://sketchfab.com/3d-models/red-dot-75578b789d5744e8b9bcf289e027aa2e) | gossenX (https://sketchfab.com/gossenX) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| holographic | [Ketar co. OP-4](https://sketchfab.com/3d-models/ketar-co-op-4-6aa520b0b0e840eeab1b58565dff25c7) | HEAVY_PAYLOAD (https://sketchfab.com/heavypayload) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| aimpoint | [Aimpoint Reddot Scope](https://sketchfab.com/3d-models/aimpoint-reddot-scope-915c970ce01644bab68579cf06cddf6d) | assassin_47 (https://sketchfab.com/assassin_47) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| nightforce | [Night-Force Scope](https://sketchfab.com/3d-models/night-force-scope-8348839d996f4cf9a7443f92b92d10c8) | Steven Janes (https://sketchfab.com/Ebethrone) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |
| accushot | [Sniper scope](https://sketchfab.com/3d-models/sniper-scope-7c5b53c1964343bdb25c26c6c00a57fd) | Arbuzz747 (https://sketchfab.com/Arbuzz747) | CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/) |

Conversions: `scripts/art/prepare_replacement_weapons.py`. Source UVs and PBR maps are retained. Axes and scale are normalized; reload magazines, muzzle, grip and sight markers are authored. The TEC-9 exploded display duplicate is omitted. The AR-15's unseated magazine is aligned and placed in its magwell, and its source optics are replaced. Bullpup's source reflex assembly is replaced. M1's old fused scope is removed above the receiver; receiver, stock and grip geometry remain unchanged.

Assignments: Reflex → Carbine; Ketar OP-4 → Bullpup; Aimpoint → M14; Night-Force → M700; Accushot → M1. The holographic lens is separated and made transparent; apertures are aligned to the optical axis, and the Aimpoint's baked duplicate reticle is removed. The existing collimated reticle and scoped HUD remain active. The optics are game assemblies, with project-authored mounting adapters where needed.

The adapted TEC-9 mesh remains under CC BY-SA 4.0. Other supplied models are CC BY 4.0; retain the linked author credits and license notices when distributing these models or derivatives.
