# Arena props

The following assets are from Poly Haven and are available under [CC0](https://polyhaven.com/license).

- [Old Military Crate](https://polyhaven.com/a/old_military_crate) by Jack Mava. The game uses the hinged lid and an empty interior with embedded 2K textures.
- [Shrub 02](https://polyhaven.com/a/shrub_02) by Rico Cilliers. Three variants are combined into small bushes.
- [Grass Medium 01](https://polyhaven.com/a/grass_medium_01) by Rico Cilliers and Rob Tuytel. Selected tufts are placed in clusters.

The foliage GLBs use embedded 1K textures. The foliage diffuse textures include the original opacity masks.

Dust II uses the scrap skip from [Abandoned Junkyard](https://ptdesigns.itch.io/abandoned-junkyard) by PtDesigns, released under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). The model uses embedded 2K textures.

Верхние контейнеры используют красный, оранжевый и чёрный варианты LOD2 из [Containers Asset Pack](https://oxygen3d.itch.io/game-ready-containers-asset-pack) от Oxygen. Модели разделены на панели, чтобы пробоины отображались на стороне попадания. Подготовленный GLB хранится локально в `assets/arena_props/oxygen/stacked_containers.glb`.

### Архивные ресурсы «Цеха № 3»

В предыдущей версии карты использовались модели из [PSX Ultra Mid Budget](https://slopmaster.itch.io/psx-ultra-mid-budget) от SlopMaster. Описание набора разрешает использование в играх и ограничивает распространение отдельных моделей. [Ресурсы обновлённой карты](workshop/CREDITS.md).

Для сборки с этими моделями скопируйте в папку следующие файлы из каталога `GLB` соответствующего архива.

| Архив | Файлы |
| --- | --- |
| `PSX_PostSoviet_60.zip` | `SM_Concrete_Block_FBS.glb`, `SM_Kiosk_Soyuzpechat.glb`, `SM_Transformer_TP.glb` |
| `PSX_PostSoviet_Factory_53.zip` | `SM_Control_Console.glb`, `SM_Drill_Press.glb`, `SM_Drum_Solvent.glb`, `SM_Lathe_1K62.glb`, `SM_Safety_Railing.glb`, `SM_Tool_Cabinet.glb` |

При импорте GLB в Godot для встроенных текстур можно выбрать **Embed as Basis Universal**. Если GLB отсутствует, карта использует простое укрытие того же размера.

Котельная использует модели и текстуры из [PSX Asylum Free Sampler](https://zenthrall.itch.io/psx-asylum-free-sample) от Zenthrall Games. Лицензия набора разрешает использование в готовой игре. Исходные файлы хранятся в той же локальной папке, а копия условий входит в архив автора.

- Из раздела `Phase_06_Maintenance_Basement` используются `Boiler_FireTube_Rusted.glb`, `Furnace_Incinerator_Lit.glb`, `ElectricalPanel_Switchboard_Burnt.glb` и `Pipe_Large_Straight_2m.glb`.
- Из каталога `Textures/Industrial` используются `T_Ind_BoilerBrick.png` и `T_Ind_FloorWet.png`.
