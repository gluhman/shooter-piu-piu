# Weapon sound recordings

The Desert Eagle report uses the supplied MP3 of [Desert Eagle Gunshot](https://pixabay.com/sound-effects/film-special-effects-desert-eagle-gunshot-14622/) by elliotlp, distributed by Pixabay under its [Content License](https://pixabay.com/service/license-summary/). The [original Freesound release](https://freesound.org/people/elliotlp/sounds/330634/) is CC0. The game uses a mono WAV conversion with adjusted gain.

The remaining recordings are licensed under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). The clips were trimmed, mixed to mono, level matched, and faded for gameplay.

- Desert Eagle action from [Desert Eagle .50AE slide release](https://freesound.org/people/vabadus/sounds/151070/) by vabadus.
- Shotgun report from [Saiga 12k Gunshot](https://freesound.org/people/Kobrakon47/sounds/569309/) by Kobrakon47.
- Shotgun pump from [Pump Action Shotgun](https://freesound.org/people/awrmacd/sounds/387190/) by awrmacd.

## First-person gunfire

The player uses stereo 48 kHz PCM edits of the recordings below. Edits isolate the discharge, balance the attack and tail, and add short reflections where the source has a short decay. For weapons without a matching recording, the table names the substitute.

| Weapon | Recording and author |
| --- | --- |
| Desert Eagle | [Desert Eagle .50, AugustSandberg](https://freesound.org/people/AugustSandberg/sounds/231243/) |
| Shotgun | [R11-48 Shotgun Blast, craigsmith](https://freesound.org/people/craigsmith/sounds/486055/) |
| AK-47 | [AK-47 single shot, ninebilly](https://freesound.org/people/ninebilly/sounds/520934/) |
| M1911 | [1911 Comedian Pistol, nioczkus](https://freesound.org/people/nioczkus/sounds/388208/) |
| MAC-10 | [Layered automatic rifle single shot, seroutonin//deprived](https://freesound.org/s/855655/) |
| MP5 | [MP5A3 in doorway, Franki-01234](https://freesound.org/people/Franki-01234/sounds/201667/), first discharge |
| M700 | [Sniper Shot, LeMudCrab](https://freesound.org/people/LeMudCrab/sounds/163460/), high-powered rifle |
| TEC-9 | [9MM, Pop Shot, AudioWay](https://freesound.org/people/AudioWay/sounds/470198/) |
| Lever Action | [.357 Magnum Revolver Gunshot, Shark_Anthony](https://freesound.org/people/Shark_Anthony/sounds/683186/) |
| M14 | [Izhmash Saiga MK-106, areniporgen](https://freesound.org/people/areniporgen/sounds/696023/), .308 rifle |
| M1 Garand | [Rifle Shot (M1 Garand), Rijam](https://freesound.org/people/Rijam/sounds/385785/) |
| M249 SAW | [Machine Gun 002 single shot, pgi](https://freesound.org/people/pgi/sounds/212607/), designed machine-gun effect |
| RPG-7 | [rpg launcher three shots.wav, klangfabrik](https://freesound.org/people/klangfabrik/sounds/249298/), first exterior launch |
| M79 | [Grenade Launcher, LeMudCrab](https://freesound.org/people/LeMudCrab/sounds/163458/), 40 mm launcher discharge |

All first-person sources are published under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

## RPG-7 launch

`first_person/rpg.wav` and `rpg_fire.wav` are dedicated edits of **rpg launcher three shots.wav** by **klangfabrik**, published 18 September 2014 on [Freesound](https://freesound.org/people/klangfabrik/sounds/249298/) under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). The author's description identifies three exterior RPG/anti-tank launcher firings.

Retrieved 20 November 2026 from the public [HQ MP3 preview](https://cdn.freesound.org/previews/249/249298_181941-hq.mp3). Source MP3 SHA-256: `ab11dd57d26ff89578644628ef3f587e594b89200ff440fe58075fd4b0c5c219`.

Preparation: decoded the preview to 48 kHz PCM16 stereo; isolated the first launch, 0.098–2.498 seconds, retaining its attack and exhaust/reverberation tail without the later launches; removed DC/sub-bass, applied a mild 140 Hz body lift, added click-prevention fades, and peak-normalized to −1.2 dBFS. The local clip remains stereo; the world clip is a mono downmix for positional panning and occlusion. Both are 2.4 seconds, with looping disabled. The recording contains the launch event; impact explosions remain separate gameplay events.

Rebuild with NumPy:

```sh
afconvert -f WAVE -d LEI16@48000 /path/to/249298_181941-hq.mp3 /tmp/rpg-source.wav
python3 scripts/art/prepare_rpg_audio.py /tmp/rpg-source.wav
```
