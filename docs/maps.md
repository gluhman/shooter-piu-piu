# Карты: структура, добавление и проверка

Этот документ описывает единый контракт карт Shooter. Он нужен при создании новой карты, переносе ресурсов или изменении спавнов, навигации и лута. Границы модулей и жизненный цикл матча приведены в [устройстве проекта](development.md); решение об едином каталоге — в [ADR 001](adr/001-map-content-layout.md).

## Структура

Все материалы карт принадлежат `game/maps/`.

```text
game/maps/
  map_builder.gd             # общий фасад, регистрация и общие объекты
  procedural/                # карты, целиком строящиеся кодом
    <id>_layout.gd
  <id>/                      # authored-карта
    <id>_arena.tscn
    scripts/
    art/
    textures/
```

`map_builder.gd` — единственная точка, которая выбирает карту для матча, создаёт общие объекты мира и передаёт результаты в `Match`. Код конкретной карты не должен менять HUD, сетевое состояние или правила матча. Общие модели, оружие, бойцы и аудио остаются вне `game/maps/`.

## Выбор реализации

| Вариант | Когда применять | Размещение |
| --- | --- | --- |
| Процедурная раскладка | Геометрия зависит от размера, seed или параметров лобби | `game/maps/procedural/<id>_layout.gd` |
| Authored-сцена | Нужна вручную собранная геометрия, уникальные узлы или сложная художественная композиция | `game/maps/<id>/` |
| Гибрид | Authored-блоки дополняются повторяемыми процедурными объектами | Сцена и её ресурсы в `game/maps/<id>/`, общая сборка через фасад |

Не создавайте второй корень наподобие `levels/` и не кладите карту в `assets/`: так теряется владелец логики и смешиваются исходные материалы с игровым контрактом.

## Порядок добавления карты

1. Выберите постоянный ASCII-идентификатор и способ реализации. Переименование после релиза меняет пути `res://` и усложняет PCK-патчи.
2. Создайте папку карты или procedural layout. Положите локальные модели, текстуры, сцены и скрипты рядом с картой.
3. Зарегистрируйте карту в `MapBuilder.MAP_NAMES` и в его выборе построителя. Добавьте согласованные записи времени суток и ветра в `Match.ARENA_WEATHER`.
4. Реализуйте статическую геометрию и коллайдеры мира. Коллайдеры должны существовать до запекания навигации.
5. Добавьте стартовые и резервные точки возрождения. Их должно хватать для максимального числа участников, а точки не должны смотреть в стену, пересекаться с геометрией или лутом.
6. Разместите укрытия и точки лута так, чтобы они были достижимы через навигацию и не перекрывали пути.
7. Для каждой поддерживаемой величины карты проверьте границы, закрытые маршруты и размещение стартов. Если размер не поддерживается, ограничьте его в интерфейсе вместо неявной поломки карты.
8. Укажите происхождение моделей, текстур и звуков: добавьте запись в [каталог ассетов](assets.md), а лицензию или ссылку на автора положите рядом с ресурсом.

## Обязательные игровые свойства

- Обычные препятствия используют слой `World`. Для открытых ящиков, перил и других объектов со сложной формой слой `Movement proxies` сохраняет упрощённую коллизию для персонажей и навигации, а `Shot geometry` задаёт видимые поверхности для попаданий и проверки обзора ботов.
- Навигация строится после появления статических коллайдеров; бот обязан иметь путь к каждой разрешённой точке возрождения и луту.
- Спавн оценивает опасность по живым противникам, линии видимости и расстоянию. Карта предоставляет достаточное число альтернативных точек, а не собственный алгоритм выбора игрока.
- Дым, гранаты, пули, простреливаемые поверхности и следы попаданий используют общие подсистемы `Grenades`, `Ballistics` и `MapBuilder`.
- Карта не создаёт авторитетные боевые события сама: в сетевом матче их рассчитывает хост или выделенный сервер.

## Проверка перед объединением

1. Откройте сцену в Godot и убедитесь, что все `res://`-ссылки существуют.
2. Запустите одиночный матч на минимальном, среднем и максимальном поддерживаемом размере.
3. Проверьте точки появления: старт, смерть, быстрый респавн, несколько ботов и отсутствие застревания.
4. Проверьте навигацию: бот видит цель, преследует её, может обойти укрытие, подобрать лут и не стреляет сквозь стену или дым.
5. Пройдите карту игроком: коллизии, прыжки, приседание, лестницы/перепады, укрытия, ящики, гранаты и простреливаемые поверхности.
6. Запустите сетевой матч, где авторитет — хост или headless-сервер, и убедитесь, что все игроки видят одинаковую карту, лут, отверстия и возрождения.
7. Выполните обязательные регрессионные проверки:

   ```sh
   godot --headless --path . --script res://tests/combat_balance_test.gd
   godot --headless --path . --script res://tests/combat_lan_test.gd -- host /tmp/shooter-lan 19077
   ```

   Второй сценарий запускается тремя процессами — полная команда и роли приведены в [документации разработки](development.md#проверки).

## Форпост

Доступны размеры 20, 40 и 70 м. Вокруг ретранслятора проходят гравийные дороги и две канавы с водой и пологими переходами. На доступной территории есть холмы, за сетчатым периметром поднимается лесистый горный склон. GDT Terrain Generator строит сетку по карте высот, которая также определяет коллизии и высоты точек появления и ящиков снабжения. [Ресурсы карты](../game/maps/farpost/CREDITS.md).

## Станция

Во всех трёх размерах (20, 40 и 70 м) центральный зал открыт на всю высоту. Две палубы окружают его балконами. На следующий уровень ведут две лестницы с противоположных сторон. Боковые галереи ведут в грузовые отсеки, технические помещения и наблюдательные лаборатории с укрытиями. Цветные светильники обозначают входы. Для стальных настилов и лестниц используются разные звуки шагов. Мини-карта показывает текущую палубу. За обзорными окнами виден рельеф, построенный модулями GDT Terrain Generator. [Ресурсы карты](../game/maps/station/CREDITS.md).

Проверка `arena_layout_smoke.gd` проверяет связность спавнов и ящиков снабжения для всех размеров «Форпоста» и «Станции».

## Лесной хребет

Арена имеет фиксированный размер 100 × 100 м. Четыре угловые поляны содержат по основному маркеру старта и дополнительные позиции для больших матчей. Тропы образуют кольцо и сходятся у каменных руин. На севере проходит хребет, а в двух низинах по сторонам от руин есть канавы с мелководьем и пологими переходами.

Terrain3D 1.1.0 отображает рельеф с шагом 0,5 м, лесной почвой и нарисованными гравийными тропами. Процедурная карта высот GDT по-прежнему определяет коллизии, высоты спавнов и навигацию. Горизонтальное мелководье обрезается по высоте дна канав; берега, сужения и сухие переходы следуют тому же рельефу. Проверка `arena_layout_smoke.gd` проверяет размер, маркеры, свободные стартовые позиции, коллизии вершины и канавы и связность маршрутов до ящиков снабжения. [Ресурсы карты](../game/maps/forest_ridge/CREDITS.md).

## НПЗ

Фиксированная арена 80 × 80 м. На нижнем уровне находятся погрузочный двор, открытые ремонтные боксы и резервуары. Два пандуса с противоположных сторон ведут на технологическую эстакаду высотой 3,4 м. Эстакада выходит на восточный склон. По склону также можно пройти с обоих концов двора. Лестницы резервуаров и восточных концов трубных эстакад работают через клавишу взаимодействия. По верхним трубам можно пройти над погрузочным двором. Низкие перила можно перепрыгнуть обычным прыжком. Пули проходят через просветы и проверяют материал при попадании в стойку, обшивку или контейнер.

- **Царь горы.** Три площадки находятся во дворе, на эстакаде и на склоне. На каждой есть укрытие сбоку от центра.
- **Захват флага.** Флаги находятся в противоположных торцах двора. Насосная установка прерывает прямую видимость между стойками, а эстакада и склон дают обходы.
- **Обезвреживание.** Одна площадка находится во дворе, другая на эстакаде. Защита стартует ближе к площадкам, а две стороны эстакады позволяют менять направление атаки.

Материалы НПЗ используют мировую трипланарную проекцию PBR, смешивание двух масштабов против повторения, макровариации цвета, грязь у земли, ржавые потёки и износ фасок. Металлические панели имеют небольшие геометрические фаски внутри прежнего коллайдера. Процедурные пятна грязи не участвуют в коллизиях. Terrain3D сохраняет бетон в 2K-массивах с mipmaps и ослабленным повторением; Forest, Village and Forest Bastion use 1K arrays.

Два ограниченных объёма VoxelGI обслуживают ремонтные боксы. Открытая эстакада использует непрямой свет общего шаблона: крупный внешний объём VoxelGI убран после визуальной проверки из-за заметной границы освещения на дворе. Геометрия запечена, освещение реагирует на солнце и местные светильники. Переключатель непрямого освещения отключает эти объёмы. В открытом дворе сохранён общий визуальный шаблон. Для повторного запекания после изменений статической геометрии запусти `godot --path . --script res://scripts/bake_refinery_lighting.gd -- --bake-refinery` с графическим Forward+. Скрипт использует матовые материалы-посредники для пользовательских шейдеров и временную сетку грунта; результаты сохраняет в `game/maps/refinery/art/lighting/`. Эти данные входят в игру, запекание при запуске матча не требуется. `tests/refinery_graphics_test.gd` проверяет рендер, переключатель GI, 2K-грунт и совместимость пробития; `-- --performance` добавляет короткий замер.

[Источники моделей, материалов, дневной HDRI и видео](../game/maps/refinery/CREDITS.md).

## Раскладки для режимов с целями

Режимы с целями строятся поверх тех же сцен и генераторов, что и бой насмерть. Сохраняются здания, проходы, этажи, исходные укрытия, материалы и HDRI. У каждого режима и размера свои координаты площадок, спавнов и дополнительных укрытий в `objective_placements.gd`. В режимах с целями процедурные укрытия собираются с фиксированным seed. В контейнерных аренах они обходят площадки, чтобы проверенные маршруты сохранялись при новом матче.

Средний и большой варианты доступны на десяти аренах. У НПЗ один фиксированный вариант для каждого режима. Лесной хребет сохраняет поле 100 × 100 м, а размеры задают разные расстановки целей и команд. Маленькие варианты, «Малый офис» и учебный полигон исключены. Площадь каждой горы увеличена на 50%. Одно невысокое укрытие стоит сбоку в пределах зоны, оставляя центр и обходы открытыми. Дополнительные укрытия используют материалы и модели карт, в том числе ящики Станции, деревянные ящики посёлка и леса, песчаник Dust II и бетонные барьеры.

`tests/objective_map_test.gd` проверяет коллизии спавнов, пути до целей и время перемещения на той же навигационной сетке, которую использует матч. Для проверки баланса реальные игроки или боты должны разыграть матчи с обеих сторон.

## Выпуск

Новая карта, заметный набор ассетов или несовместимое изменение её путей требуют новой полной базы по правилам [релизов и PCK-патчей](releases.md). Обычный PCK-hotfix не должен случайно включать ресурсы карты: перед публикацией сверяйте состав и размер артефакта.

## Shared Forest Ridge visual template

`game/maps/lighting/forest_ridge_visuals.tres` saves the original Forest Ridge runtime lighting and effects: ambient fill, sun intensity and softness, AgX, SSAO, SSR/SSIL/SDFGI, glow, fog and color grading. `visual_template.gd` applies only these property groups after each map configures its own environment. The preset contains no sky, HDRI, background properties, sky rotation or camera profile.

Every map retains its original background, background brightness, sky orientation, time of day and camera exposure. This includes Breakwater's freight panorama, Station's night sky, Farpost's overcast sky, Refinery's hilltop panorama, Office's dark color background and the original dynamic skies on other maps. A background without a sky uses color ambient fill. Local fixtures, bounce probes and gameplay wind remain map-owned. Graphics menu controls still apply.

Run `godot --headless --path . --script res://tests/map_visual_template_test.gd` to check every map and background preservation. Run without `--headless` and add `-- --screenshots` for rendered screenshots at `/tmp/piupiu-forest-template-XX.png`.

## Terrain3D: Forest, Village and Refinery

`terrain_3d_surface.gd` builds native Terrain3D height, control and color regions from the maps' existing deterministic half-meter heightfields. Forest paints gravel trails and darker ditch beds; Refinery paints concrete in the yard and gravel on paths and slopes; Village uses its existing soil textures. Existing textures are packed into cached albedo/height and normal/roughness arrays at runtime: 2048 px for Refinery, 1024 px for Forest, Village and Forest Bastion. No demo content is required.

Terrain3D collision is disabled: the original static terrain collision remains authoritative for navigation, shots and gameplay. Spawns, supplies, map sizes, construction seeds and height sampling retain their existing contracts. Village switches to its original locally refined mesh while excavations are present, preserving trench collars and collision; clearing excavations restores Terrain3D. The distant Village plane and Refinery backdrop remain map-owned.

Run `godot --path . --script res://tests/terrain_3d_map_test.gd -- --screenshots` with Forward+ for rendered checks of Forest, all three Village sizes and Refinery. Captures are saved as `/tmp/terrain3d-*.png`, including a close view of Forest water. Also run `tests/village_layout_test.gd`, `tests/arena_layout_smoke.gd` and `tests/fieldworks_test.gd` headlessly for navigation, collision and excavation regressions.

## Terrain3D mesh grass on outdoor maps

All twelve outdoor maps use the shared `foliage/terrain_grass.gd` installer. Existing Forest, Forest Bastion, Village, Refinery, Farpost and container-yard planting masks feed Terrain3D's native instancer; Dust II, Workshop, Breakwater and the training range receive sparse perimeter patches. Office and Station receive no grass. Forest, Forest Bastion, Village, Refinery and Farpost use jittered 18 cm planting grids clipped to existing grass masks, with short overlapping blades forming lawns and only occasional tall accents. Terrain3D ground rendering remains limited to the previously converted maps; the other maps use a grass-only Terrain3D host with terrain render layers disabled and their existing ground surfaces retained.

The runtime uses opaque blade brushes on all outdoor maps, with denser boundary patches on industrial maps. The two reusable [brush assets](../game/maps/foliage/CREDITS.md) are short grass (20 cm) and tall grass (70 cm), with local scale variation and taller tufts grouped using seeded noise. Industrial and desert vegetation uses smaller tufts; Dust II adds a dry tint. Root and overhead raycasts reject props, cliffs and covered interiors; the lawn brushes also follow grassy slopes. A 2.4 m radius around starting positions stays clear. Grass is decorative, has no collision, and is skipped on headless/dedicated servers. Existing navigation and terrain collision stay authoritative.

For the runtime blade lawn, load `dense_grass_short.tres` / `dense_grass_tall.tres`. The short scene contains a 32-blade near mesh and a 32-blade LOD using identical roots and tips with straight triangular leaves. Terrain3D switches mesh at 32 m and culls beyond 95 m. Root-to-tip colour and volume normals remain anchored before deformation. Shadows and specular highlights are disabled. The short brush uses 96 triangles instead of the previous 180; the far brush uses 32.

For the retained photo-textured brushes and editor painting, load `res://game/maps/foliage/grass_brushes.tres` into a Terrain3D asset library, or add either `grass_short.tscn` or `grass_tall.tscn` as a mesh asset in the Meshes dock. Select the asset and use Terrain3D's mesh brush; the prepared objects have their roots at the origin.

Run `godot --path . --script res://tests/terrain_grass_test.gd -- --screenshots` to verify both brush objects, native instance counts, all outdoor maps, clear spawns and indoor exclusions. Close-up captures are saved to `/tmp/terrain-grass-XX.png`.

Forest ditch water uses shoreline-locked waves, depth tint, Fresnel lighting, refraction and a bounded pool of eight expanding footstep ripples. Moving players and bots disturb submerged areas; standing actors do not continuously emit ripples. Water remains decorative and follows the original clipped banks and dry crossings. Run `tests/forest_water_test.gd` with a rendering display to verify shoreline exclusions, actor wakes and visible animation.

The lawn brushes use 7–14 mm tapered blades with a muted olive palette and occasional straw-coloured tips. Forest and Refinery ground tint uses a restrained green/olive balance instead of the earlier saturated yellow-green. Planting masks, collision and navigation are retained. The lawn grid is tightened from 25 cm to 18 cm (Forest Bastion previously used 50 cm).

Grass has no specular highlights. Terrain3D ground layers use a +0.30 roughness adjustment and 0.65 normal-map depth to keep dry soil matte and reduce isolated white sun-reflection dots. Existing indirect-lighting settings remain active.

On Metal, Forest, Village and Refinery bypass the glow pass to avoid reproduced intermittent white-orb artifacts; temporal upscaling and indirect lighting stay enabled. Returning to another map restores its shared glow profile. Grass tip colour is anchored to undeformed geometry, with consistent lighting on both sides of fine blades.

## Лесной бастион — только «Царь горы»

ID 13, фиксированные 100 × 100 м. Уровни земли: 0, 4, 8 и 12 м. Противоположные угловые базы содержат по пять стартов; маршрут к вершине симметричен. Двенадцать широких подъёмов чередуются вокруг террас со смещением 45° между соседними уровнями, позволяя подняться без прыжков. Четыре каменных тоннеля имеют отдельные полы, своды и физические коллизии. Своды существуют только ниже Terrain3D; открытые заглублённые выходы поднимаются на террасы 4 и 8 м. До вершины 12 м тоннелей нет; последний подъём проходит снаружи. Края отверстий используют грунтовые воротники и скосы по образцу траншей класса поддержки, с объёмными стенками и мировой трипланарной текстурой. Вокруг проходов нативная сетка с крупными отверстиями заменяется локальным грунтом с шагом 12,5 см; его поверхность и коллизия совпадают. Входы и выходы скрыты в скалах и имеют смещённые укрытия. Мини-карта показывает наземные тропы серым цветом, тоннели — жёлтым. Два кольцевых маршрута связывают широкие подъёмы: на каждом уровне есть четыре варианта, соседние уровни смещены на 45°. Подходы от баз огибают скальные экраны, а столкновения деревьев зеркальны для двух команд.

В лесу на вершине находится одна постоянная зона для всех составов команд. Каменные стены высотой 0,9 м оставляют проходы к флагу. Двенадцать ящиков стоят рядом со скалами на всех уровнях. Три верхних ящика дают РПГ, две аптечки и броню; отключённое набором оружие заменяется бронёй. Авторитет припасов, захвата и респавна остаётся на хосте. Другие режимы исключают карту из выбора и случайной ротации.

Используется общий визуальный шаблон и существующие CC0-материалы Poly Haven: Rocky Terrain 02, Rock Boulder Dry, лесная подстилка и Kloofendal Overcast. [Источники](../game/maps/forest_hill/CREDITS.md). Дальний лес и горный силуэт декоративны. Нативный Terrain3D отображает полуметровую карту высот и отверстия; коллизии и навигация используют совпадающие статические сетки. При запекании погребённые своды исключаются из walkable-геометрии, чтобы боты не выбирали наружную поверхность крыши.

`tests/forest_hill_test.gd` проверяет режимы, стартовые базы, высоты, свободные проходы, физическое прохождение четырёх тоннелей, навигацию, доступность припасов и захват вершины. Без `--headless` сохраняет обзор, вершину и тоннель в `/tmp/forest-hill-*.png`. Для быстрого визуального просмотра без повторного прохождения маршрутов добавьте `-- --preview`. `forest_hill_lan_test.gd` проверяет три ENet-пира, включая позднего наблюдателя.

Скалы «Лесного бастиона» используют точную статическую треугольную коллизию исходной модели с тем же масштабом и смещением, что и видимая сетка. Коробочных movement/shot-прокси у них нет; геометрия загружается и на headless-сервере, а одинаковые формы кешируются по варианту и размеру. `tests/forest_hill_rock_test.gd` сравнивает реальные лучевые попадания с исходными треугольниками всех 58 скал, включая пустые углы их габаритов и все 16 верхних камней. Запуск без `--headless` также сохраняет игровые виды для визуальной проверки.

## Shared surface finish

`materials/surface_finish.gd` installs map-owned opaque material overrides after map/objective construction. Imported resource files stay unchanged. Existing albedo, normal, roughness, metallic, AO channels, tint and UV projection are retained. World-triplanar materials use two matching texture scales and a broad colour variation to hide repetition; authored UV/atlas models retain their UV layout. Metal and masonry get subtle dirt; rust is restricted to metal and is stronger on industrial maps. Eligible BoxMesh geometry gets inward bevels inside the original collision volume. Glass, foliage cutouts, luminous surfaces and existing specialised shaders retain their materials. Refinery keeps its dedicated finish.

The pass preserves the existing local lighting: Office and Breakwater retain their baked VoxelGI, outdoor maps use the shared sky/SSIL profile, and Refinery retains its two repair-bay volumes. No outdoor GI bounding box is added across an open yard. Each map keeps its original sky, hour and camera exposure, and the Metal glow exclusion remains active on the affected Terrain3D maps.

Run `tests/map_surface_review.gd` with a graphical renderer for the 14-map review and bullet-hole/UV checks. It saves overview and grass views in `/tmp/map-finish-XX-*.png`. Use `-- --maps 11 --performance` for a focused fixed-view measurement. `tests/terrain_grass_test.gd` checks all outdoor brushes, LODs, instance counts and spawn clearances. [Sources and credits](../game/maps/materials/CREDITS.md).
