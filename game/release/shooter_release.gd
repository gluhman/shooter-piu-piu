extends Node

const VERSION_FILE := "res://game/release/version.txt"
const PATCH_ARGUMENT := "--shooter-patch"
const VERSION_ARGUMENT := "--shooter-version"
const PATCH_DIR := "user://patches"
const PATCH_SELECTION := PATCH_DIR + "/active.cfg"

var version: String
var base_version: String
var patch_notice := ""
var _patch_error := ""


func _init() -> void:
	base_version = _read_version()
	version = base_version
	var args := OS.get_cmdline_user_args()
	var index := args.find(PATCH_ARGUMENT)
	if index >= 0:
		if index + 1 == args.size() or args.count(PATCH_ARGUMENT) != 1:
			_patch_error = "Укажите один абсолютный путь к PCK-патчу."
			return
		_patch_error = _load_patch(args[index + 1])
		return
	if not supports_patches():
		return
	var installed := _installed_patch()
	if installed.is_empty():
		return
	var check := _verify_patch(installed)
	if not check.error.is_empty():
		patch_notice = "Установленный патч пропущен. " + check.error
		return
	_patch_error = _mount_patch(installed, check.target)
	if not _patch_error.is_empty():
		DirAccess.remove_absolute(PATCH_SELECTION)
		patch_notice = _patch_error


func _ready() -> void:
	if not _patch_error.is_empty():
		printerr("Патч Shooter: ", _patch_error)
		get_tree().quit(1)
	elif VERSION_ARGUMENT in OS.get_cmdline_user_args():
		print("Shooter ", version)
		get_tree().quit()


func supports_patches() -> bool:
	return OS.get_name() == "macOS" and OS.has_feature("template")


func make_patch_slot() -> String:
	var directory := PATCH_DIR.path_join("%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return ""
	return ProjectSettings.globalize_path(directory.path_join("update.pck"))


func discard_patch_slot(path: String) -> void:
	if path.is_empty():
		return
	DirAccess.remove_absolute(path + ".cfg")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path.get_base_dir())


func copy_patch(source: String, destination: String) -> String:
	if not FileAccess.file_exists(source + ".cfg"):
		return "Рядом с патчем нужен его файл .pck.cfg."
	if DirAccess.copy_absolute(source, destination) != OK or DirAccess.copy_absolute(source + ".cfg", destination + ".cfg") != OK:
		return "Не удалось скопировать файлы патча."
	return ""


func activate_patch(path: String) -> String:
	var check := _verify_patch(path)
	if not check.error.is_empty():
		return check.error
	if _patch_number(check.target) <= _patch_number(version):
		return "Уже запущена эта или более новая версия."
	var output: Array = []
	var args := PackedStringArray(["--headless", "--audio-driver", "Dummy", "--", PATCH_ARGUMENT, path, VERSION_ARGUMENT])
	var result := OS.execute(OS.get_executable_path(), args, output, true)
	if result != 0 or output.is_empty() or not str(output[0]).split("\n").has("Shooter " + check.target):
		return "Не удалось запустить игру с этим патчем."
	var previous := _installed_patch()
	var selection := ConfigFile.new()
	selection.set_value("patch", "path", path)
	var temporary := path.get_base_dir().path_join("selection.tmp")
	if selection.save(temporary) != OK or DirAccess.rename_absolute(temporary, PATCH_SELECTION) != OK:
		DirAccess.remove_absolute(temporary)
		return "Не удалось сохранить выбранный патч."
	discard_patch_slot(previous)
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()
	return ""


func can_install_version(target: String) -> bool:
	return _is_hotfix(target) and _patch_number(target) > _patch_number(version)


func _installed_patch() -> String:
	var selection := ConfigFile.new()
	if selection.load(PATCH_SELECTION) != OK:
		return ""
	var path := str(selection.get_value("patch", "path", ""))
	var folder := path.get_base_dir().get_base_dir()
	if folder != ProjectSettings.globalize_path(PATCH_DIR) or path.get_file() != "update.pck":
		return ""
	return path


func _read_version() -> String:
	if FileAccess.file_exists(VERSION_FILE):
		return FileAccess.get_file_as_string(VERSION_FILE).strip_edges()
	return str(ProjectSettings.get_setting("application/config/version"))


func _load_patch(path: String) -> String:
	var check := _verify_patch(path)
	return check.error if not check.error.is_empty() else _mount_patch(path, check.target)


func _verify_patch(path: String) -> Dictionary:
	if not supports_patches():
		return {"error": "Для установки патча запустите готовый Shooter.app на macOS."}
	if not path.begins_with("/") or path.get_extension().to_lower() != "pck":
		return {"error": "Укажите абсолютный путь к файлу .pck."}
	var manifest := ConfigFile.new()
	if manifest.load(path + ".cfg") != OK:
		return {"error": "Рядом с патчем нужен читаемый файл .pck.cfg."}
	var target := str(manifest.get_value("patch", "version", ""))
	if manifest.get_value("patch", "base_version", "") != base_version or not _is_hotfix(target):
		return {"error": "Патч несовместим с базовой версией %s." % base_version}
	var executable_dir := OS.get_executable_path().get_base_dir()
	var base := executable_dir.path_join("../Resources/shoot-container.pck").simplify_path()
	if not _matches_sha256(base, str(manifest.get_value("patch", "base_sha256", ""))):
		return {"error": "Патч рассчитан на другую базовую сборку."}
	if not _matches_sha256(path, str(manifest.get_value("patch", "sha256", ""))):
		return {"error": "Контрольная сумма патча не совпадает."}
	return {"error": "", "target": target}


func _mount_patch(path: String, target: String) -> String:
	if not ProjectSettings.load_resource_pack(path):
		return "Не удалось загрузить патч."
	if _read_version() != target:
		return "Версия в патче отличается от указанной в .pck.cfg."
	version = target
	print("Shooter: загружен патч ", version)
	return ""


func _matches_sha256(path: String, expected: String) -> bool:
	return expected.length() == 64 and FileAccess.get_sha256(path) == expected


func _patch_number(value: String) -> int:
	return int(value.get_slice(".", 2))


func _is_hotfix(target: String) -> bool:
	var base := base_version.split(".")
	var next := target.split(".")
	return base.size() == 3 and next.size() == 3 and next[0] == base[0] and next[1] == base[1] \
		and next[2].is_valid_int() and str(int(next[2])) == next[2] and int(next[2]) > int(base[2])
