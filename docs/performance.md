# Графика и замеры производительности

## Shared surfaces and denser lawns, 2.4.0

The graphical `tests/map_surface_review.gd` passed on all 14 maps at an actual 2560 x 1440 framebuffer, Godot 4.7.2, Metal / Forward+, Apple M5 Pro. UV projection, PBR channels, bullet holes and restoring finishes on moving/static cover were checked. The grass suite passed on all 12 outdoor maps; indoor maps retain their exclusions.

At 18 cm spacing and 32 blades per tuft instead of 25 cm / 36 blades, nominal blade density is about 1.71 times higher. Near tufts use 96 triangles instead of 180, keeping nominal near geometry cost per area similar. The far LOD uses 32 triangles and retains every blade. Forest Bastion previously used 50 cm spacing, so its density increase is larger. Large-map totals, including tall accents and planting exclusions: Forest 256,749; Bastion 174,837; Village 77,098; Refinery 57,372; Farpost 81,302.

Focused Forest LOD check: one fresh process per variant, identical density and camera, 120 frames after warmup, no bots, FSR 2.2 at 100% scale, VSync and frame cap disabled.

| Metric | Near mesh only | Native far LOD |
| --- | ---: | ---: |
| Median frame | 25.07 ms | 23.42 ms |
| p95 frame | 25.55 ms | 23.94 ms |

This short fixed-view check does not compare the old and new versions of every map or measure a full multiplayer match. The PBR finish adds fragment work; 1K terrain arrays use more memory than the old 512 px arrays. After several Terrain3D map switches, `RENDER_TEXTURE_MEM_USED` overflowed, so that counter is unsuitable for comparing memory in the sequential suite. The seven Texture RID shutdown warning remains. Editor import reported no GDScript parse errors; the Dummy renderer still reported resources in use at shutdown.

## Настройки графики

- **Качество изображения.** Масштаб 3D от 50% до 100%, билинейное масштабирование, FSR 1.0 и FSR 2.2. HUD и меню рисуются с разрешением окна. Сглаживание можно выключить или выбрать 2× MSAA, 4× MSAA, FXAA либо TAA. При FSR 2.2 отдельное сглаживание отключается.
- **Текстуры.** Анизотропная фильтрация от 2× до 16×. Обычная фильтрация доступна отдельным пунктом.
- **Освещение.** Тени солнца можно отключить, выбрать дальность 24, 36, 52 или 75 м и два или четыре каскада. По умолчанию тени рисуются до 36 м в двух каскадах. Для SSAO есть отдельный выключатель и три уровня качества.
- **Эффекты.** Уменьшенная детализация снижает число визуальных частиц попаданий и взрывов. Дымовая граната сохраняет свою зону перекрытия обзора.

FSR, TAA и SSAO в этих настройках доступны с рендерером Forward+. Настройки сохраняются между запусками. Ранее сохранённый выбор FSR 2.2 переносится в новый список масштабирования.

## Бойцы 2.3.0

Каждый вариант Grab3D Soldier содержит 774 948 треугольников в пяти поверхностях, включая скрытый треугольник привязки камеры. Тело, лицо и снаряжение сохраняют исходные 4K-карты цвета, нормалей и metallic/roughness. Перчатки используют прежнюю артикулированную геометрию. Чёрный материал сохраняет детализацию исходных текстур и цвет кожи. Материалы кэшируются на команду. При импорте включены LOD и отдельные теневые меши. GLB каждого варианта занимает около 41 MiB; риг по-прежнему содержит 66 костей и исходные разреженные ключи Mesh2Motion.

Высокополигональная геометрия увеличивает стоимость близких кадров и память по сравнению с прежними моделями. Проверка внешнего вида выполнена в Godot 4.7.2, Metal / Forward+, Apple M5 Pro, галерея двух бойцов при масштабе 3D 100%, с HDRI, SSAO и тенями. Численные FPS из прежних замеров ниже не являются замерами этой модели.

Исходные GLB до выбора LOD: базовый/синий — 149 230 треугольников, 42 поверхности и 18,3 МиБ; красный — 148 830 треугольников, 41 поверхность и 18,0 МиБ. Геометрия одежды получила сглаживание; одинаковые вершины разделяются индексами, неиспользуемые буферы удалены. Размеры не включают общие внешние текстуры. Новые текстуры и студийная HDRI занимают около 66 МиБ исходных файлов; уличная HDRI — около 25 МиБ. Эти числа не являются замером видеопамяти или числа вызовов отрисовки всего матча.

Уличная HDR-панорама повышена до 4K. Запечённые VoxelGI-объёмы офиса и турбинного зала обновлены; движущиеся бойцы используют динамические тени. В галерее обе модели проверяются с Poly Haven Studio Small 09 4K при масштабе 3D 100%, физической экспозиции, SSAO и направленном свете. Это визуальная проверка, а не замер FPS. Приведённые ниже результаты старых версий не характеризуют производительность новых моделей.

## Dust II, 2560 × 1440

Тест запускает большую Dust II с 10 ботами обычной сложности. Камера последовательно смотрит на три фиксированные позиции. После 4 с прогрева записывается 12 с времени кадров. Звук отключён через драйвер Dummy и заглушённую шину Master. VSync и лимит FPS отключены. Масштаб 3D составляет 100% от фактического буфера 2560 × 1440, сглаживание отключено, SSAO включён.

Для повторения из корня проекта запусти Godot 4.7.2 с графическим окном.

```sh
godot --path . --audio-driver Dummy --script res://tests/dust2_performance.gd
```

Для воспроизведения параметров теней 1.2.5 в 1.2.6 добавь к команде `-- same-shadows`. На macOS тест учитывает масштаб Retina и завершает прогон с ошибкой, если фактический буфер отличается от 2560 × 1440.

### Результаты на Apple M5

macOS, Godot 4.7.2, Metal и Forward+. Обе сборки измерялись одним скриптом на их экспортированных PCK. В таблице медиана трёх чередующихся прогонов для каждой версии, кроме максимального кадра и числа кадров дольше 33,3 мс. Эти два показателя приведены по всем трём прогонам.

| Показатель | 1.2.5, тени до 52 м | 1.2.6, тени до 36 м |
| --- | ---: | ---: |
| Средний FPS | 176,4 | 152,9 |
| FPS по среднему времени худшего 1% кадров | 47,5 | 24,8 |
| p95 времени кадра | 7,10 мс | 10,63 мс |
| p99 времени кадра | 16,68 мс | 17,55 мс |
| Максимальное время кадра | 387,4 мс | 378,2 мс |
| Кадры дольше 33,3 мс | 1 | 5 |
| Вызовы отрисовки на кадр | 362 | 245 |
| p95 времени физики | 6,02 мс | 3,62 мс |

Медиана числа вызовов отрисовки снизилась на 32%, p95 времени физики — на 40%. При масштабе 3D 100% средний FPS и плавность в этой серии ухудшились. В одном дополнительном прогоне 1.2.6 с прежней дальностью теней 52 м результат составил 155,9 FPS, p99 17,22 мс и максимум 378,5 мс. По этому прогону нельзя связать просадки с одной настройкой теней. Длительность GPU-кадра в этой конфигурации Metal счётчик не вернул.

Дополнительный прогон 1.2.6 с выходным разрешением 2560 × 1440, FSR 1.0 и масштабом 75% дал 143,5 FPS, p99 15,03 мс и максимальный кадр 27,35 мс. Это один прогон с внутренним разрешением около 1920 × 1080.

### Проверка 1.6.0 на исходном проекте

Тот же сценарий на Apple M5, Godot 4.7.2, Metal Forward+, 2560 × 1440, 10 ботов, звук отключён. Замеряли исходный код 1.5.1 и рабочую 1.6.0 в трёх и пяти прогонах соответственно. Таблица показывает медианы по прогонам, кроме строк с явно указанным диапазоном.

| Показатель | 1.5.1 | 1.6.0 |
| --- | ---: | ---: |
| Вызовы отрисовки на кадр | 320 | 312 |
| Средний FPS | 129,1 | 96,6 |
| Диапазон среднего FPS | 101,3–144,9 | 60,0–144,9 |
| FPS по среднему времени худшего 1% кадров | 17,5 | 41,8 |
| p95 времени кадра | 17,01 мс | 17,45 мс |
| p99 времени кадра | 17,96 мс | 18,66 мс |
| Кадры дольше 33,3 мс за прогон | 0–3 | 0–1 |
| Загрузка матча | 932 мс | 862 мс |

У машин на Dust II колёса, бамперы и фонари объединены по материалу. На одну машину приходится три поверхности деталей вместо десяти отдельных мешей. Предзагрузка Dust II запрашивает 13 текстур материалов вместо 22. Боты без видимой цели проверяют шум движения примерно каждые 0,12 с. Обнаружение зрением и реакция на попадание работают по своим интервалам.

Отрисовка требует меньше вызовов. Медианы загрузки и худшего 1% кадров улучшились, медиана среднего FPS снизилась, а разница в p95/p99 составила меньше 1 мс. Результат по FPS зависел от прогона, включая значения около 60 и 145 FPS с теми же настройками. Для сравнения частоты кадров между сборками нужны повторные замеры в одинаковых условиях. В тесте Godot также выводил предупреждения об объектах и ресурсах при выходе в обеих версиях.

### Проверка 2.2.1 на исходном проекте

На Apple M5 с 24 ГБ памяти сравнили 2.2.0 (`c7179dd`) и правки 2.2.1. По три чередующихся прогона штатным скриптом на большой Dust II с 10 ботами обычной сложности. Godot 4.7.2, Metal Forward+, буфер 2560 × 1440, масштаб 3D 100%, тени до 36 м, Dummy audio. Замер матча начинается после 4 с прогрева. В таблице медианы, кроме диапазона FPS, самого длинного кадра и суммарного числа кадров дольше 33,3 мс.

| Показатель | 2.2.0 | 2.2.1 |
| --- | ---: | ---: |
| Средний FPS | 131,0 | 120,6 |
| Диапазон среднего FPS | 88,0–143,1 | 82,2–142,6 |
| FPS по среднему времени худшего 1% кадров | 16,7 | 38,6 |
| p95 времени кадра | 10,59 мс | 11,28 мс |
| p99 времени кадра | 12,12 мс | 16,77 мс |
| Самый длинный кадр за три прогона | 659,6 мс | 68,1 мс |
| Кадры дольше 33,3 мс за три прогона | 7 | 7 |
| Загрузка матча | 1049 мс | 1132 мс |

В этой серии самые длинные рывки стали короче, но медианы среднего FPS, p95/p99 и загрузки ухудшились. Разброс между прогонами большой, поэтому степень влияния правок на частоту кадров и рывки требует повторной проверки. Счётчик GPU на Metal продолжал возвращать 0. В отдельном диагностическом запуске 2.2.0 загрузка заняла 22,6 с, из которых около 21,6 с пришлось на «Готовим первый кадр». При повторениях задержка не воспроизвелась, её причина пока не подтверждена.

На восьми моделях проверили отдельно 100 поверхностей. Внешний вид оружия сохраняет 100 базовых поверхностей, а число дополнительных студийных проходов уменьшается с 77 до 0. Те же 77 проходов доступны от первого лица. Проверены 18 аудиоресурсов нового оружия, которые теперь загружаются заранее. Тесты баллистики, сложности и движения ботов прошли. Отдельных замеров перезарядки, сетевой игры и других карт в этой серии не проводилось.

### Первый кадр в 2.2.1

До этой правки на экране загрузки игра рисовала вспышку выстрела, несколько взрывов и дым, чтобы подготовить их материалы. В Forward+ вместо этого в сцену добавляются скрытые экземпляры с теми же материалами. Подготовка оружия, лута и эффектов повторяется при изменении карты, набора оружия или влияющих на отрисовку настроек. Фоновая загрузка сцены с заставки захватывает её зависимости.

На Apple M5, Godot 4.7.2, Metal Forward+, 2560 × 1440, 10 ботов, Dummy audio измеряли время от `start_solo()` до появления выбора снаряжения. Первый заход был в новом процессе. Повторный запуск той же карты выполнялся после выхода в лобби. До изменения сделано по одному прогону на карту, после него по два. Кэш драйвера между процессами не очищался.

| Карта | Первый заход до | Первый заход после | Повторный заход до | Повторный заход после |
| --- | ---: | ---: | ---: | ---: |
| Dust II | 4,44 с | 1,17–1,21 с | 0,57 с | 0,50 с |
| НПЗ | 5,96 с | 1,54–1,63 с | 1,10 с | 0,99–1,02 с |

В дополнительной проверке Dust II одновременно запускали вспышку выстрела, осколочную, светошумовую, взрыв подствольного снаряда и дым. Счётчик компиляций при отрисовке не вырос. Самые длинные кадры за 90 кадров после запуска эффектов составили 44 и 53 мс при первом и повторном заходах. Нагрузка с полностью пустым кэшем драйвера и на других видеокартах требует отдельных замеров.

## Shared Forest Ridge effects profile

Maps use the original Forest Ridge lighting and effects preset while retaining their individual backgrounds and camera profiles. SSR and SDFGI are disabled; SSIL, SSAO and shadows respect graphics controls. Fog density is 0.0038. Earlier benchmarks describe earlier profiles; this preset has no new FPS measurements.

## Dense lawn and Forest water verification

Reproduce with Godot 4.7.2 Forward+ using `tests/terrain_grass_test.gd -- --maps 11,3,12 --screenshots` and `tests/forest_water_test.gd`. The rendered checks used Apple M5 Pro / Metal 4 at a 1600×960 window. These are correctness checks, not an FPS benchmark. In that earlier check, lawn roots were spaced 25 cm and each short tuft used 36 five-triangle blades. The current 18 cm / 32-blade geometry and LOD measurements are documented above. Terrain3D batches and distance-culls the instances; grass casts no shadows, adds no collision and is omitted on headless servers. Water keeps at most eight visual ripples, with actor sampling every 150 ms.

## Explosion presentation checks

Run `godot --path . --script tests/realistic_explosion_test.gd -- --screenshots` with Forward+. Verification uses the training range, physical daylight exposure, a 1600×960 window and Apple M5 Pro / Metal 4. It checks ground/air dispatch, independent animation state, cleanup, low-detail refraction suppression and rendered fire-to-smoke changes. This is a correctness test, not an FPS benchmark. Each blast adds one camera-facing fire/smoke quad and a short-lived refraction quad instead of many overlapping procedural fire/smoke puffs. Existing range culling and headless exclusion remain in place.

## Terrain white-dot and grass-flicker regression

The glowing dots were reproduced at 2890×1741 on Apple M5 Pro / Metal 4 using the Forest spawn view at heading 60°. With no bots or shots, the calibrated local detector found spots in 42/300 frames with FSR2 and glow enabled, 35/300 with SSIL disabled, and 0/300 with glow disabled. Disabling temporal upscaling cleared the Forest reproduction, but spatial FSR still showed spots in Refinery, so no upscaler workaround is retained.

`match.gd` bypasses glow only for Forest, Village and Refinery on Metal. FSR, antialiasing, SSIL, shadows, blast lights and the saved graphics preferences are retained. Other maps and rendering drivers retain the shared glow profile. `tests/terrain_stability_test.gd` forces FSR2, checks localized neutral bright spikes rather than whole-frame averages, refreshes graphics during each run and verifies that leaving the affected maps restores glow. Final verification found zero localized spikes in 180 frames per map (540 total), plus a 60-frame moving close-up of grass. This is a correctness test, not a performance benchmark.

The grass shader previously hashed the wind-deformed vertex position to choose dry tips. Wind and distance fading therefore changed the palette every frame. Colour selection now uses undeformed positions, and volume lighting uses the same world-up normal on both sides of each blade to prevent view-dependent brightness flips. Close-up captures are `/tmp/grass-stable-closeup-*.png`.

Blast smoke lifetime is now seven seconds with final fading after it rises. The rendered explosion test checks grenade and RPG lift above three metres while opacity remains full, late fading above five metres, independent animation state and cleanup. Longer smoke lifetime increases the number of visible clouds during repeated blasts; no new FPS benchmark is claimed.

## Forest Bastion validation

The 100 × 100 m hill uses a half-metre collision grid, locally refined 12.5 cm ground around tunnel openings, and native Terrain3D presentation, three batched fir variants and shared short/tall grass brushes. Underground floors are separate from buried arches during navigation baking; the full arches retain physics collision. Decorative mountain/forest backdrops have no collision. Headless servers skip grass, tree meshes, HDRI and high-resolution tunnel textures.

Reproduce the rendered review with Godot 4.7.2 Forward+ on Metal at 1600 × 960: `godot --path . --script res://tests/forest_hill_test.gd`. It captures the summit, an interior and an overview after walking four passages and twelve surface climbs. This is a visual/traversal check, not a hardware FPS benchmark. No FPS or memory claim is inferred from it. Existing shared graphics settings and the Terrain3D Metal glow workaround apply.

Forest Bastion rock collision is a fitted static triangle mesh shared by movement, shots and navigation. Shapes are reused for repeated variant/size pairs. Headless builds load the source rock geometry during construction to bake the same shapes as rendered clients; there are no server-only bounding boxes. No dynamic concave bodies are created.

## НПЗ: материалы и локальный VoxelGI, 2.4.0

Короткий сравнительный прогон `tests/refinery_graphics_test.gd -- --performance`: Godot 4.7.2, Metal Forward+, Apple M5 Pro, фактический буфер 2560 × 1440, FSR 2.2 при масштабе 100%, без VSync и лимита кадров, без ботов. По 90 кадров в трёх фиксированных видах после прогрева. Все новые материалы присутствуют в обоих вариантах; сравнивается переключатель непрямого освещения, а не полная старая/новая версия карты.

| Показатель | Непрямое освещение выключено | Включено |
| --- | ---: | ---: |
| Медиана кадра | 13,05 мс | 13,79 мс |
| p95 кадра | 16,02 мс | 20,77 мс |
| Средние вызовы отрисовки | 1366 | 1368 |
| Счётчик памяти текстур | 1186 МиБ | 1186 МиБ |

Это один прогон; результаты не характеризуют сетевой матч с бойцами. Два запечённых объёма subdivision 128 занимают около 1,1 МиБ на диске. Массивы грунта 2K и кэш исходных изображений увеличивают расход видеопамяти относительно прежних 512 px. При завершении графических CLI-проверок движок сообщает о семи Texture RID; ошибок шейдера и ошибок исполнения во время проверки нет. Этот shutdown-warning не следует считать доказательством отсутствия утечки при длительной игре.
