# Ассеты Shooter

Каталог показывает, где используются ресурсы и где искать условия их распространения. Подробные сведения об авторах, исходных файлах и доработках хранятся в `CREDITS.md` и файлах лицензий рядом с ресурсами.

## Модели, анимации и карты

| Ресурс | Использование | Источник и условия |
| --- | --- | --- |
| Tactical Operator | Модель игрока и ботов, форма, защитные накладки и часы на левом рукаве | [DanlyVostok, ambientCG и Poly Haven](../assets/operator/CREDITS.md). Модель CC BY 4.0, дополнительные материалы и часы CC0 |
| Universal Animation Library | Стойка, движение, присед и прыжок бойцов | [Quaternius, CC0](../assets/animations/CREDITS.md) |
| Human Character Dummy и Human Basic Motions FREE | Исходная поза и восемь направлений ходьбы и бега в локальной сборке | [Кевин Иглесиас и условия использования](../assets/animations/CREDITS.md). Подготовленная библиотека лежит в `assets/animations/local/` |
| Classic Weapons Pack | Модели огнестрельного оружия, выстрелы и перезарядка | [Stein Games, CC0](../assets/classic_weapons/CREDITS.md). [Отдельные материалы AK-47](../assets/ak47/CREDITS.md) |
| Расширение арсенала | Восемь основных стволов, раздельные магазины и помпа, карты окклюзии и HDR-отражения | [3DAssets.dev, Poly Haven и Stein Games](../assets/weapon_expansion/CREDITS.md), CC0 |
| Арсенал | Модели оружия, гранат и бронежилета, материалы металла и дерева | [Модели проекта, материалы Poly Haven и звук BigSoundBank](../assets/arsenal/CREDITS.md) |
| Desert Eagle и нож | Модели от первого лица и предметы подбора с PBR-материалами | [SirDraco65 и Poly Haven, CC0](../assets/weapon_models/CREDITS.md) |
| HDR-панорама двора | Рассеянный свет и отражения на открытых картах Sky3D | [Poly Haven, CC0](../game/maps/lighting/CREDITS.md) |
| Лесной хребет | Рельеф GDT Terrain Generator, скалы, папоротники, лесная подстилка и текстуры елей Poly Haven | [Источники и лицензии карты](../game/maps/forest_ridge/CREDITS.md) |
| Материалы Dust II | Песчаник стен и арок, гравий для грунта и пандусов | [Poly Haven, CC0](../assets/map_textures/dust2/CREDITS.md). Карты цвета 4K, нормали и шероховатость 2K |
| Предметы окружения | Военный ящик, кусты, трава и кузов для металлолома | [Poly Haven и PtDesigns, CC0](../assets/arena_props/CREDITS.md) |
| Containers Asset Pack | Верхние контейнеры и панели со следами попаданий | [Oxygen и схема подключения](../assets/arena_props/CREDITS.md). Подготовленный GLB лежит в `assets/arena_props/oxygen/` |
| Цех № 3 | Индустриальные модели и PBR-материалы складов, погрузочная тележка и оборудование | [Ресурсы карты](../assets/arena_props/workshop/CREDITS.md) |

## Звук и эффекты

| Ресурс | Использование | Источник и условия |
| --- | --- | --- |
| Impact Sounds и ветер Dust II | Шаги, звуки попаданий и зацикленный фон карты | [Kenney и dhallcomposer, CC0](../assets/match_audio/CREDITS.md) |
| Записи выстрелов и механики | Выстрелы от первого лица, затворы и перезарядка | [Авторы, исходные записи и лицензии](../assets/weapon_audio/CREDITS.md) |
| Текстуры дыма взрыва | Кадры дыма и карты нормалей для выстрела гранатомёта | [Duarte David и порт memo1918, MIT](../assets/explosion_vfx/LICENSE.txt) |
| PYROLUX Lite | Вспышка, огненное облако, дым, пыль, искры и ударное кольцо осколочной гранаты. У взрыва в воздухе нет слоя пыли с поверхности | [gennai](https://gennai.itch.io/pyrolux-lite), [исходный код и пресет](https://github.com/kai777123/godot-4-free-vfx/tree/15b8e21925841b10fa3e19aab99fff1038c1486b/fire), [MIT](../addons/pyrolux_fx/LICENSE.txt). Плотность, яркость и время дыма настроены в [сцене осколочного взрыва](../game/combat/frag_explosion.tscn) |
| Дымовая граната | Облако и зона перекрытия обзора сдвигаются по ветру Sky3D, скорость и направление заданы для каждой карты | Реализация Shooter. Общий вектор ветра для дыма использован как приём из [Free Smoke VFX от gennai](https://gennai.itch.io/free-smoke-vfx-godot-4) |
| Ресурсы меню | Фон, музыкальная петля и звуки интерфейса | [Папка ресурсов](../assets/menu). Для этих файлов в репозитории нет сведений об авторах и лицензиях |

## Плагины

| Плагин | Использование | Источник и условия |
| --- | --- | --- |
| Заставка в стиле Half-Life 2 | Полный авторский ролик длительностью 11,93 секунды с дорожкой Vandoorea. Пропускается по Esc | [enderprism](https://endxrprism.itch.io/hl2-godot-splash-screen), [логотип spzi](https://spzi.itch.io/godotsource), [лицензия и авторы](../game/ui/startup/HL2-SPLASH-LICENSE.txt) |
| Godot Awesome Splash | Тёмная стартовая заставка Shooter с адаптацией эффекта Dark. Логотип Shooter виден при открытии окна и во время ожидания ресурсов после видеозаставки. Тот же логотип используется на экране загрузки арены | [Duong Vi Tuan](https://duongvituan.itch.io/godot-awesome-splash), [MIT](../game/ui/startup/LICENSE.txt) |
| Sky3D | Небо, облака и время суток | [Лицензия](../addons/sky_3d/LICENSE.txt), [сторонние текстуры](../addons/sky_3d/ThirdParty.md) |
| SpatialAudio3D | Пространственное звучание, приглушение стенами и отражения | [Ревизия, лицензия и параметры](../addons/spatial_audio_3d/README.md) |
| Physical Hit Reactions Lite | Реакции бойцов на попадания поверх анимации | [Дэн Гал и описание интеграции](../assets/animations/CREDITS.md), [MIT](../addons/hit_reactions_lite/LICENSE.md) |

## Кандидаты из новых пакетов

Подключённые ресурсы и редакторские инструменты описаны ниже. Остальные пакеты остаются кандидатами для отдельных задач.

| Пакет | Где пригодится в Shooter |
| --- | --- |
| Tree3D | Деревья внутри «Лесного посёлка». Сетка подготовлена заранее, экземпляры сгруппированы через MultiMesh, коллизии только у стволов. Нативная библиотека использовалась при подготовке сетки. [Документация Tree3D](https://github.com/JekSun97/gdTree3D) |
| RoadGenerator | Готовая сетка перекрёстка используется на средней и большой версиях «Лесного посёлка». Аддон для трассировки дорог включён в редакторе. [Документация RoadGenerator](https://github.com/TheDuckCow/godot-road-generator) |
| GUT | Включён в редакторе. В `tests/gut/` есть тесты спада урона и защиты брони. Сетевые сценарии проверяются отдельным стендом с реальными клиентами ENet. [Документация GUT](https://github.com/bitwes/Gut) |
| VFX AnimationPlayer, Juicee | VFX AnimationPlayer включён для покадровой настройки частиц в редакторе. Juicee остаётся кандидатом для отдельных эффектов. |
| Phantom Camera, Advanced Third Person Camera | Phantom Camera ведёт обзорный пролёт за таблицей результатов. При старте нового раунда снова используется камера игрока. Advanced Third Person Camera остаётся кандидатом для будущего режима наблюдателя. |
| Resolution Scaler | Прототип динамического разрешения. Пакет напрямую меняет масштаб 3D-рендера по FPS. Для Shooter нужно учитывать действующие настройки FSR и масштаба, ограничивать диапазон и проверять плавность на Dust II. |
| GodotSteam | Кандидат для приглашений и лобби. Для интеграции нужны Steam App ID, настройка Steamworks и проверка двух аккаунтов. Обычная сборка сохраняет ENet. [Документация GodotSteam](https://godotsteam.com) |
| PopcornFX | Кандидат для конкретного эффекта, который не получается собрать на текущих частицах Godot и PYROLUX Lite. Папка занимает около 911 МиБ. [Документация PopcornFX](https://documentation.popcornfx.com/PopcornFX/v2.25/plugins/godot-plugin/index.html) |
| Any AudioManager, Audio Service, Settings Menu Lite | Образцы реализации. В Shooter уже есть пространственный звук и собственные настройки. Settings Menu Lite использует тот же путь `user://settings.cfg`, Audio Service написан на C#. |
| Physics Arsenal / PhysKit, Event Bus Deluxe | Отдельные примеры. Сцены Physics Arsenal в корне ссылаются на отсутствующие пути `res://Physics Arsenal/` и `res://PhysKit/`. Взять отдельную идею можно после проверки зависимостей. |
| CollisionShapeGroup3D, Script-IDE, GodotMDL, SpaceMouse Navigator, Ziva Agent | Вспомогательные инструменты. Группировка коллизий пригодится при ручной сборке карты. GodotMDL нужен для экспорта моделей в Source, SpaceMouse Navigator заявлен для Windows, Ziva пересекается с настроенным Godot MCP Toolkit. |

Локальная сборка macOS копирует игровые сцены, ассеты и необходимые аддоны в отдельный каталог экспорта. Демо и редакторские пакеты остаются в рабочей папке. При прямом экспорте из редактора действуют фильтры пресета. [Правила экспорта Godot](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html#resource-options).

Проверки GUT запускаются из корня проекта после импорта ресурсов.

```sh
godot --headless --path . --script res://addons/gut/gut_cmdln.gd -gdir=res://tests/gut -gexit
```

## Наборы и инструменты для карт

| Пакет | Применение в Shooter |
| --- | --- |
| GDT Terrain Generator и Poly Haven | Модули GDT 1.1.0 используются в рельефе «Лесного хребта» и «Форпоста». «Форпост» использует HDRI, PBR-материалы и модели Poly Haven с текстурами 2K. [Источники и лицензии «Форпоста»](../game/maps/farpost/CREDITS.md). |
| Kenney Starter Kit FPS | Использованы две модели стен, платформа и общий атлас. Модели и атлас распространяются по CC0. Из этих моделей собрана «Станция». [Исходный пакет](https://github.com/KenneyNL/Starter-Kit-FPS/tree/185fd2326d74a5cf858cffc616f87cf9696f9cc0) и [копия лицензии в репозитории](../game/maps/kenney_outpost/art/LICENSE.md). |
| Quaternius Modular Sci-Fi MegaKit | Набор CC0 для следующей интерьерной карты. У него есть модульные стены, двери и элементы окружения. В прототипе стоит проверить единый материал и простые коллайдеры для повторяющихся модулей. [Страница автора в Godot Asset Store](https://store.godotengine.org/asset/quaternius/modular-sci-fi-megakit/). |
| FuncGodot | Кандидат для карт, построенных в TrenchBroom. Импортирует MAP в Godot и сопоставляет объекты карты с игровыми сущностями. Перед подключением стоит проверить масштаб, коллизии и сохранение маркеров спавна и лута на одной тестовой арене. [Репозиторий FuncGodot](https://github.com/func-godot/func_godot_plugin). |
| Cyclops Level Builder | Кандидат для быстрого проектирования уровней внутри Godot. Блоки можно преобразовать в обычные меши и коллайдеры для экспорта. [Документация Cyclops](https://github.com/blackears/cyclopsLevelBuilder/blob/master/doc/index.md). |

Для производительности уровней сначала проверяем встроенные возможности Godot: импорт LOD, окклюзию за крупными непрозрачными стенами и MultiMesh для одинаковых объектов внутри небольших участков карты. Godot отсекает MultiMesh целиком, поэтому объединение экземпляров по всей арене может увеличить число видимых полигонов. [Оптимизация 3D](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html), [MultiMesh](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html).

## Как добавить ресурс

Поиск новых пакетов начинаем с [бесплатных ассетов для Godot на itch.io](https://itch.io/game-assets/free/tag-godot).

1. Проверь на странице автора разрешение на использование в игре и распространение исходников. Если право распространять исходники ограничено, держи их вне Git и опиши, куда положить нужные файлы.
2. Запиши рядом с ресурсом автора, ссылку на источник, лицензию, версию набора и изменения, сделанные для Shooter. Сохрани оригинальный файл лицензии, если он прилагается.
3. Обнови этот каталог. Если ассет влияет на игру или сборку, добавь изменение в [журнал версии](../CHANGELOG.md).
