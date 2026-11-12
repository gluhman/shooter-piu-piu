# Анимации бойца

[Universal Animation Library Standard от Quaternius](https://quaternius.com/packs/universalanimationlibrary.html) распространяется по лицензии [CC0 1.0](LICENSE.txt).

В `operator_locomotion.res` сохранены адаптированные для модели бойца клипы `Idle_Loop`, `Walk_Loop`, `Jog_Fwd_Loop`, `Sprint_Loop`, `Crouch_Idle_Loop`, `Crouch_Fwd_Loop`, `Jump_Start`, `Jump_Loop` и `Jump_Land`. Библиотека анимирует таз и ноги. Положение бойца определяет физика, а руки следуют за точками хвата оружия.

Локальная сборка дополнительно использует восемь направлений ходьбы и восемь направлений бега из [Human Basic Motions FREE](https://kevdev.itch.io/basic-motions-free) Кевина Иглесиаса. Исходная поза взята из [Human Character Dummy](https://kevdev.itch.io/human-character-dummy). Ключи таза и ног перенесены на скелет бойца, а циклы выровнены по фазе шага. Подготовленная библиотека хранится в `assets/animations/local/operator_directions.res`. Условия использования опубликованы на [сайте автора](https://www.keviniglesias.com/#license).

Видимая реакция бойца на попадание использует [Physical Hit Reactions Lite](https://dangalg.itch.io/physical-hit-reactions-lite-godot) Дэна Гала. Модификатор настроен на кости бойца Shooter и получает точку и направление из подтверждённого события урона. [Лицензия MIT](../../addons/hit_reactions_lite/LICENSE.md).
