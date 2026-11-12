#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

[[ "$(uname -s)" == Darwin ]] || fail 'Сборка Shooter.app требует macOS.'

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_dir="$project_dir/releases"
version="$(sed -nE 's/^config\/version="([^"]+)"$/\1/p' "$project_dir/project.godot")"
version_pattern='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
[[ "$version" =~ ^$version_pattern$ ]] || fail 'Укажи версию X.Y.Z в project.godot.'

archive_base=false
base_pack=
case "$#:${1:-}" in
    0:) ;;
    1:--archive-base)
        archive_base=true
        archive="$release_dir/Shooter-$version-base.pck"
        [[ ! -e "$archive" && ! -e "$archive.engine" ]] ||
            fail 'База этой версии уже сохранена. Для нового выпуска увеличь версию.'
        ;;
    2:--patch)
        [[ -f "$2" && -f "$2.engine" ]] || fail 'Укажи сохранённый базовый PCK с файлом .pck.engine.'
        base_pack="$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")"
        [[ "$base_pack" != *,* ]] || fail 'Путь к базовому PCK должен быть без запятых.'
        [[ "$(basename "$base_pack")" =~ ^Shooter-($version_pattern)-base\.pck$ ]] ||
            fail 'Ожидается базовый файл Shooter-X.Y.Z-base.pck.'
        base_version="${BASH_REMATCH[1]}"
        [[ "${base_version%.*}" == "${version%.*}" && "${version##*.}" -gt "${base_version##*.}" ]] ||
            fail 'Патч должен увеличивать Z при тех же X.Y.'
        patch_name="Shooter-$base_version-to-$version.pck"
        [[ ! -e "$release_dir/$patch_name" && ! -e "$release_dir/$patch_name.cfg" ]] ||
            fail 'Патч этой версии уже существует.'
        ;;
    *) fail 'Использование: build-macos.sh [--archive-base | --patch путь-к-базовому.pck]' ;;
esac

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
engine_version="$("$godot" --version)"
if [[ -n "$base_pack" && "$(<"$base_pack.engine")" != "$engine_version" ]]; then
    fail 'Для патча требуется та же версия Godot, что и для базовой сборки.'
fi

build_dir="$project_dir/.shooter-build"
output="$project_dir/Shooter.app"
local_template="$(dirname "$project_dir")/macos-4.7.2.stable.zip"
if [[ -r "$local_template" ]]; then
    output="$(dirname "$project_dir")/Builds/Shooter.app"
fi
mkdir -p "$(dirname "$output")"
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
rsync -a "$project_dir/assets" "$project_dir/game" "$project_dir/project.godot" \
    "$project_dir/default_bus_layout.tres" "$project_dir/export_presets.cfg" "$snapshot/"
rsync -a "$project_dir/levels" "$snapshot/"
if [[ -r "$local_template" ]]; then
    ln -s "$local_template" "$build_dir/$(basename "$local_template")"
    sed -i '' '1,/^\[preset\.1\]$/s|^custom_template/release=""$|custom_template/release="res://../macos-4.7.2.stable.zip"|' "$snapshot/export_presets.cfg"
fi
mkdir "$snapshot/addons"
for addon in sky_3d spatial_audio_3d hit_reactions_lite pyrolux_fx godot_mcp_toolkit \
    phantom_camera; do
    rsync -a "$project_dir/addons/$addon" "$snapshot/addons/"
done
for plugin in gut road-generator vfx_animaiton_player; do
    sed -i '' "s|, \"res://addons/$plugin/plugin.cfg\"||g" "$snapshot/project.godot"
done
printf '%s\n' "$version" > "$snapshot/game/release/version.txt"
VERSION="$version" perl -0pi -e 's/^application\/short_version=.*$/application\/short_version="$ENV{VERSION}"/m' "$snapshot/export_presets.cfg"
VERSION="$version" perl -0pi -e 's/^application\/version=.*$/application\/version="$ENV{VERSION}"/m' "$snapshot/export_presets.cfg"

printf 'Импорт ресурсов Godot\n'
if ! "$godot" --headless --path "$snapshot" --editor --import >"$build_dir/import.log" 2>&1 ||
    grep -Eq 'SCRIPT ERROR|Parse Error|Failed loading resource' "$build_dir/import.log"; then
    tail -n 80 "$build_dir/import.log" >&2
    fail 'Не удалось импортировать ресурсы.'
fi

if [[ -n "$base_pack" ]]; then
    patch="$build_dir/$patch_name"
    printf 'Экспорт патча %s → %s\n' "$base_version" "$version"
    if ! "$godot" --headless --path "$snapshot" --export-patch macOS "$patch" --patches "$base_pack" >"$build_dir/export.log" 2>&1 ||
        grep -q 'ERROR:' "$build_dir/export.log" || [[ ! -s "$patch" ]]; then
        tail -n 60 "$build_dir/export.log" >&2
        fail 'Не удалось экспортировать патч.'
    fi
    base_hash="$(shasum -a 256 < "$base_pack")"
    patch_hash="$(shasum -a 256 < "$patch")"
    printf '[patch]\nbase_version="%s"\nversion="%s"\nbase_sha256="%s"\nsha256="%s"\n' \
        "$base_version" "$version" "${base_hash%% *}" "${patch_hash%% *}" > "$patch.cfg"
    mkdir -p "$release_dir"
    mv "$patch" "$patch.cfg" "$release_dir/"
    printf 'Патч и файл .pck.cfg сохранены в %s\n' "$release_dir"
    exit 0
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
plist="$built/Contents/Info.plist"
[[ "$(plutil -extract CFBundleShortVersionString raw "$plist")" == "$version" &&
   "$(plutil -extract CFBundleVersion raw "$plist")" == "$version" ]] ||
    fail 'Версия приложения расходится с project.godot.'

if $archive_base; then
    mkdir -p "$release_dir"
    cp "$built/Contents/Resources/shoot-container.pck" "$build_dir/base.pck"
    printf '%s\n' "$engine_version" > "$build_dir/base.engine"
    mv "$build_dir/base.pck" "$archive"
    mv "$build_dir/base.engine" "$archive.engine"
    printf 'База сохранена в %s\n' "$archive"
fi

if [[ -e "$output" ]]; then
    mv "$output" "$backup"
fi
mv "$built" "$output"
printf 'Собрано %s\n' "$output"
