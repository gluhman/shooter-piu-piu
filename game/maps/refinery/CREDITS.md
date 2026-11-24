# Ресурсы НПЗ

- [GDT Terrain Generator 1.1.0](https://godotengine.org/asset-library/asset/5160). Для склона, уступов и дальних холмов используются модули карты высот и сетки. [Лицензия MIT](../forest_ridge/art/gdt/LICENSE).
- [Hilltop Construction](https://polyhaven.com/a/hilltop_construction) автора Greg Zaal. Панорама 4K используется для дневного неба и освещения. [Лицензия CC0](https://polyhaven.com/license).
- [Concrete Floor Worn 001](https://polyhaven.com/a/concrete_floor_worn_001), [Container Side](https://polyhaven.com/a/container_side), [Metal Plate](https://polyhaven.com/a/metal_plate) и [Blue Metal Plate](https://polyhaven.com/a/blue_metal_plate). Бетон и сталь используют карты 4K для цвета, нормалей и ARM. Грузовые контейнеры используют сборку и материалы «Контейнерного двора».
- Крупные валуны и мелкие камни используют [Rock Boulder Dry](https://polyhaven.com/a/rock_boulder_dry) с картами цвета, нормалей и ARM 4K. Мировая трипланарная развёртка сохраняет масштаб текстуры на камнях разных размеров. Почва, гравий и модели камней общие с [Лесным хребтом](../forest_ridge/CREDITS.md). Электрические шкафы и инструментальные ящики общие со [Станцией](../station/CREDITS.md). Деревья и деревянные ящики взяты из [Лесного посёлка](../../../assets/arena_props/village/CREDITS.md), тележка из [Цеха № 3](../../../assets/arena_props/workshop/CREDITS.md).

## Обновление материалов и освещения

- [This Is How to Make Game Textures With AI — Can It Code?](https://www.youtube.com/watch?v=_rMMP7GPgt4): публичное описание и главы использованы как ориентир для трипланарной проекции, скрытия повторения, грязи и износа кромок. Существующие лицензированные PBR-карты переиспользованы; материалы из Patreon и изображения из видео не копировались.
- [Lighting Comparison in Godot 4 | VoxelGI vs LightMapGI — LoopDev](https://www.youtube.com/watch?v=FAk3MLd8YB4): ориентир для локального непрямого освещения. Выбран VoxelGI для меняющегося солнца; [ограничения пользовательских шейдеров при запекании](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_voxel_gi.html) учтены отдельными материалами-посредниками.
- `weathered_surface.gdshader`, `grime_patch.gdshader`, геометрические фаски, светильники и данные запекания — оригинальная реализация проекта. Новых сторонних текстур и HDRI не добавлено.
