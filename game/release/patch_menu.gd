extends AcceptDialog

const UPDATE_SERVER := "http://51.250.79.77/shooter/"
const UPDATE_MANIFEST := UPDATE_SERVER + "manifest.json"
const GITHUB_RELEASE := "https://api.github.com/repos/gluhman/shooter-piu-piu/releases/latest"
const GITHUB_RELEASES := "https://api.github.com/repos/gluhman/shooter-piu-piu/releases?per_page=20"
const SPARKLE_HELPER := "../Helpers/Shooter Updater.app"
const DIALOG_SIZE := Vector2i(680, 420)

var _choose: Button
var _check: Button
var _download: Button
var _full: Button
var _full_candidate: Dictionary = {}
var _status_scroll: ScrollContainer
var _status: Label
var _picker: FileDialog
var _http: HTTPRequest
var _candidate: Dictionary = {}
var _download_started := 0
var _download_total := 0
var _download_version := ""


func _ready() -> void:
	title = "Обновление игры"
	min_size = Vector2i(620, 220)
	max_size = Vector2i(720, 700)
	ok_button_text = "Закрыть"
	_choose = add_button("Выбрать .pck", true)
	_check = add_button("Проверить обновления", true)
	_download = add_button("Скачать и установить", true)
	_choose.pressed.connect(_picker_open)
	_check.pressed.connect(_find_update)
	_download.pressed.connect(_download_update)
	_download.hide()
	_full = add_button("Обновить приложение" if _has_native_updater() else "Скачать новую сборку", true)
	_full.pressed.connect(_download_full)
	_full.hide()
	get_label().hide()
	_status_scroll = ScrollContainer.new()
	_status_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_status_scroll)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_scroll.add_child(_status)
	_picker = FileDialog.new()
	_picker.title = "Выберите патч Shooter"
	_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_picker.access = FileDialog.ACCESS_FILESYSTEM
	_picker.use_native_dialog = true
	_picker.add_filter("*.pck", "Патч Shooter")
	add_child(_picker)
	_picker.file_selected.connect(_install_local)
	_http = HTTPRequest.new()
	_http.use_threads = true
	add_child(_http)


func open() -> void:
	if not visible:
		_candidate.clear()
		_download.hide()
		_full.hide()
		_set_status("Текущая версия: %s\nGitHub: не проверен\n\nУстановка патча перезапустит игру." % ShooterRelease.version)
		popup_centered(DIALOG_SIZE)


func _picker_open() -> void:
	_picker.popup_centered_ratio(0.65)


func _install_local(source: String) -> void:
	_set_busy(true, "Проверяем файлы патча…")
	await get_tree().process_frame
	var path := ShooterRelease.make_patch_slot()
	if path.is_empty():
		_set_busy(false, "Не удалось создать папку патча.")
		return
	var error := ShooterRelease.copy_patch(source, path)
	_finish_install(path, error)


func _find_update() -> void:
	_candidate.clear()
	_download.hide()
	_full.hide()
	_full_candidate.clear()
	_set_busy(true, "Проверяем обновления…")
	var response := await _request(UPDATE_MANIFEST, "", 64 * 1024, 20.0)
	if response.code == 200:
		var manifest: Variant = JSON.parse_string(response.body.get_string_from_utf8())
		if manifest is Dictionary:
			_candidate = _patch_from_manifest(manifest)
	if _candidate.is_empty():
		_set_busy(true, "GitHub: проверяем обновления…")
		response = await _request(GITHUB_RELEASE, "", 128 * 1024, 20.0)
		if response.code == 200:
			var release: Variant = JSON.parse_string(response.body.get_string_from_utf8())
			if release is Dictionary:
				_candidate = _patch_from_release(release)
	var full_response := await _request(GITHUB_RELEASES, "", 2 * 1024 * 1024, 10.0)
	if full_response.code == 200:
		var releases: Variant = JSON.parse_string(full_response.body.get_string_from_utf8())
		if releases is Array:
			_full_candidate = _latest_full_build(releases)
	_full.visible = _has_native_updater() or not _full_candidate.is_empty()
	_download.visible = not _candidate.is_empty()
	var message := "GitHub: доступен\nБаза: %s\n\nНовых патчей нет." % ShooterRelease.base_version
	if not _candidate.is_empty():
		message = "GitHub: доступен\nНайден патч %s · %s" % [_candidate.version, _format_bytes(_candidate.size)]
		if not _candidate.notes.is_empty():
			message += "\n\nЧто нового:\n" + _release_notes(_candidate.notes).left(700)
		message += "\n\nПосле установки игра перезапустится."
	if not _full_candidate.is_empty():
		message += "\n\nДоступна полная сборка %s · %s." % [_full_candidate.version, _format_bytes(_full_candidate.size)]
		if not _has_native_updater():
			message += " После загрузки откройте DMG и замените Shooter.app."
	_set_busy(false, message)


func _latest_full_build(releases: Array) -> Dictionary:
	var pattern := RegEx.create_from_string("^v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.0$")
	var base := ShooterRelease.base_version.split(".")
	var best := Vector2i(int(base[0]), int(base[1]))
	var candidate: Dictionary = {}
	for release: Variant in releases:
		if not release is Dictionary or release.get("draft", false) or release.get("prerelease", false):
			continue
		var parsed := pattern.search(str(release.get("tag_name", "")))
		if parsed == null:
			continue
		var series := Vector2i(int(parsed.get_string(1)), int(parsed.get_string(2)))
		if series.x < best.x or (series.x == best.x and series.y <= best.y):
			continue
		var version := parsed.get_string().trim_prefix("v")
		var filename := "Shooter-%s.dmg" % version
		var expected_url := "https://github.com/gluhman/shooter-piu-piu/releases/download/v%s/%s" % [version, filename]
		for asset: Dictionary in release.get("assets", []):
			if asset.get("name", "") == filename and asset.get("browser_download_url", "") == expected_url:
				best = series
				candidate = {"version": version, "url": expected_url, "size": int(asset.get("size", 0))}
				break
	return candidate


func _updater_path() -> String:
	return OS.get_executable_path().get_base_dir().path_join(SPARKLE_HELPER).simplify_path()


func _has_native_updater() -> bool:
	return ShooterRelease.supports_patches() and int(OS.get_version().get_slice(".", 0)) >= 12 \
		and DirAccess.dir_exists_absolute(_updater_path())


func _download_full() -> void:
	if _has_native_updater():
		if OS.create_process("/usr/bin/open", [_updater_path()]) < 0:
			_set_status("Не удалось открыть установщик обновлений.")
		return
	if OS.shell_open(_full_candidate.url) != OK:
		_set_status("Не удалось открыть загрузку сборки.")
		return
	_set_status("Загрузка открыта в браузере. Когда DMG скачается, откройте его, закройте игру и замените Shooter.app.")


func _patch_from_manifest(manifest: Dictionary) -> Dictionary:
	if str(manifest.get("base_version", "")) != ShooterRelease.base_version:
		return {}
	var version := str(manifest.get("version", ""))
	var pck := str(manifest.get("pck", ""))
	var cfg := str(manifest.get("cfg", ""))
	if not ShooterRelease.can_install_version(version) or not _is_safe_release_path(pck) or not _is_safe_release_path(cfg):
		return {}
	return {
		"version": version,
		"pck": UPDATE_SERVER + pck,
		"cfg": UPDATE_SERVER + cfg,
		"size": int(manifest.get("size", 0)),
		"notes": str(manifest.get("notes", "")).strip_edges(),
	}


func _patch_from_release(release: Dictionary) -> Dictionary:
	var version := str(release.get("tag_name", "")).trim_prefix("v")
	if not ShooterRelease.can_install_version(version):
		return {}
	var pck := ""
	var cfg := ""
	var size := 0
	for asset: Dictionary in release.get("assets", []):
		var name := str(asset.get("name", ""))
		var url := str(asset.get("browser_download_url", ""))
		if name == "Shooter-%s.pck" % version:
			pck = url
			size = int(asset.get("size", 0))
		elif name == "Shooter-%s.pck.cfg" % version:
			cfg = url
	if pck.is_empty() or cfg.is_empty():
		return {}
	return {"version": version, "pck": pck, "cfg": cfg, "size": size,
		"notes": str(release.get("body", "")).strip_edges()}


func _is_safe_release_path(path: String) -> bool:
	if path.is_empty() or path.begins_with("/") or path.contains("://"):
		return false
	for part in path.split("/", false):
		if part == "." or part == "..":
			return false
	return true


func _download_update() -> void:
	_set_busy(true, "GitHub: доступен\nПодготавливаем патч %s…" % _candidate.version)
	var path := ShooterRelease.make_patch_slot()
	if path.is_empty():
		_set_busy(false, "Не удалось создать папку патча.")
		return
	var response := await _request(_candidate.cfg, path + ".cfg", 64 * 1024, 30.0)
	if response.code == 200:
		_download_version = _candidate.version
		_download_total = int(_candidate.size)
		_download_started = Time.get_ticks_msec()
		response = await _request(_candidate.pck, path, 1024 * 1024 * 1024, 600.0)
	_download_started = 0
	if response.code != 200:
		_finish_install(path, "Не удалось скачать патч. Попробуйте ещё раз.")
		return
	_set_busy(true, "Проверяем скачанный патч…")
	await get_tree().process_frame
	_finish_install(path, "")


func _request(url: String, path: String, limit: int, timeout: float) -> Dictionary:
	_http.download_file = path
	_http.body_size_limit = limit
	_http.timeout = timeout
	if _http.request(url, ["Accept: application/json"] if path.is_empty() else []) != OK:
		return {"code": 0}
	var response: Array = await _http.request_completed
	return {"code": response[1] if response[0] == HTTPRequest.RESULT_SUCCESS else 0, "body": response[3]}


func _finish_install(path: String, error: String) -> void:
	if error.is_empty():
		error = ShooterRelease.activate_patch(path)
	if not error.is_empty():
		ShooterRelease.discard_patch_slot(path)
		_set_busy(false, error)


func _set_busy(busy: bool, message: String) -> void:
	_set_status(message)
	_choose.disabled = busy
	_check.disabled = busy
	_download.disabled = busy
	_full.disabled = busy
	get_ok_button().disabled = busy


func _set_status(message: String) -> void:
	_status.text = message
	_status_scroll.scroll_vertical = 0


func _release_notes(notes: String) -> String:
	return notes.replace("\n\nЧто нового:\n", "\n").trim_prefix("Что нового:\n").strip_edges()


func _process(_delta: float) -> void:
	if _download_started == 0:
		return
	var downloaded := _http.get_downloaded_bytes()
	var elapsed := maxf(0.001, float(Time.get_ticks_msec() - _download_started) / 1000.0)
	var total := _download_total if _download_total > 0 else _http.get_body_size()
	var progress := ""
	if total > 0:
		progress = " · %.0f%%" % (100.0 * float(downloaded) / float(total))
	_set_status("GitHub: доступен\nСкачивание %s%s\n%s из %s · %s/с" % [_download_version, progress, _format_bytes(downloaded), _format_bytes(total), _format_bytes(int(float(downloaded) / elapsed))])


func _format_bytes(value: int) -> String:
	if value <= 0:
		return "—"
	if value < 1024 * 1024:
		return "%.1f КБ" % (float(value) / 1024.0)
	return "%.1f МБ" % (float(value) / (1024.0 * 1024.0))
