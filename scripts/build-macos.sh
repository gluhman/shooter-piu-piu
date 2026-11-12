#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

[[ "$(uname -s)" == Darwin ]] || fail 'Сборка Shooter.app требует macOS.'

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot="${GODOT_BIN:-}"
if [[ -n "$godot" ]]; then
    godot="$(command -v "$godot")" || fail 'GODOT_BIN должен указывать на исполняемый файл Godot.'
else
    for candidate in godot godot4 /Applications/Godot.app/Contents/MacOS/Godot "$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
        if godot="$(command -v "$candidate")"; then
            break
        fi
    done
fi
[[ -n "$godot" ]] || fail 'Godot не найден. Укажи путь через GODOT_BIN.'

build_dir="$project_dir/.shooter-build"
output="$project_dir/Shooter.app"
backup="$build_dir/previous.app"
mkdir "$build_dir" || fail "Не удалось создать $build_dir. Проверь, идёт ли другая сборка."

cleanup() {
    if [[ -d "$backup" && ! -e "$output" ]]; then
        if ! mv "$backup" "$output"; then
            printf 'Предыдущая сборка сохранена в %s\n' "$backup" >&2
            return
        fi
    fi
    rm -rf -- "$build_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

snapshot="$build_dir/project"
mkdir "$snapshot"
rsync -a --exclude '/.git' --exclude '/.godot/' --exclude '/.shooter-build/' \
    --exclude '/Shooter.app/' "$project_dir/" "$snapshot/"

printf 'Импорт ресурсов Godot\n'
if ! "$godot" --headless --path "$snapshot" --editor --import >"$build_dir/import.log" 2>&1 ||
    grep -Eq 'SCRIPT ERROR|Parse Error|Failed loading resource' "$build_dir/import.log"; then
    tail -n 80 "$build_dir/import.log" >&2
    fail 'Не удалось импортировать ресурсы.'
fi

built="$build_dir/Shooter.app"
printf 'Экспорт приложения macOS\n'
if ! "$godot" --headless --path "$snapshot" --export-release macOS "$built" >"$build_dir/export.log" 2>&1 ||
    grep -q 'ERROR:' "$build_dir/export.log"; then
    grep -E 'ERROR:|Error:|error:' "$build_dir/export.log" >&2 || tail -n 30 "$build_dir/export.log" >&2
    fail 'Не удалось экспортировать Shooter.app.'
fi

codesign --verify --deep --strict "$built"
architectures=" $(lipo -archs "$built/Contents/MacOS/shoot-container") "
[[ "$architectures" == *' arm64 '* && "$architectures" == *' x86_64 '* ]] ||
    fail 'В сборке отсутствует поддержка Apple Silicon или Intel.'

if [[ -e "$output" ]]; then
    mv "$output" "$backup"
fi
mv "$built" "$output"
printf 'Собрано %s\n' "$output"
