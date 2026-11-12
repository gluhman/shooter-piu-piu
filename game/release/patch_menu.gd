extends AcceptDialog

const UPDATE_SERVER := "http://51.250.79.77/shooter/"
const UPDATE_MANIFEST := UPDATE_SERVER + "manifest.json"
const DIALOG_SIZE := Vector2i(680, 420)

var _choose: Button
var _check: Button
var _download: Button
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
		_set_status("Текущая версия: %s\nСервер обновлений: не проверен\n\nУстановка патча перезапустит игру." % ShooterRelease.version)
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
	_set_busy(true, "Проверяем сервер обновлений…")
	var response := await _request(UPDATE_MANIFEST, "", 64 * 1024, 20.0)
	if response.code != 200:
		_set_busy(false, "Сервер обновлений: недоступен (HTTP %d).\n\nМожно выбрать файл патча вручную." % response.code)
		return
	var manifest: Variant = JSON.parse_string(response.body.get_string_from_utf8())
	if not manifest is Dictionary:
		_set_busy(false, "Сервер обновлений: получен некорректный манифест.")
		return
	_candidate = _patch_from_manifest(manifest)
	_download.visible = not _candidate.is_empty()
	var message := "Сервер обновлений: доступен\nБаза: %s\n\nНовых патчей нет." % ShooterRelease.base_version
	if not _candidate.is_empty():
		message = "Сервер обновлений: доступен\nНайден патч %s · %s" % [_candidate.version, _format_bytes(_candidate.size)]
		if not _candidate.notes.is_empty():
			message += "\n\nЧто нового:\n" + _release_notes(_candidate.notes).left(700)
		message += "\n\nПосле установки игра перезапустится."
	_set_busy(false, message)


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


func _is_safe_release_path(path: String) -> bool:
	if path.is_empty() or path.begins_with("/") or path.contains("://"):
		return false
	for part in path.split("/", false):
		if part == "." or part == "..":
			return false
	return true


func _download_update() -> void:
	_set_busy(true, "Сервер обновлений: доступен\nПодготавливаем патч %s…" % _candidate.version)
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
	_set_status("Сервер обновлений: доступен\nСкачивание %s%s\n%s из %s · %s/с" % [_download_version, progress, _format_bytes(downloaded), _format_bytes(total), _format_bytes(int(float(downloaded) / elapsed))])


func _format_bytes(value: int) -> String:
	if value <= 0:
		return "—"
	if value < 1024 * 1024:
		return "%.1f КБ" % (float(value) / 1024.0)
	return "%.1f МБ" % (float(value) / (1024.0 * 1024.0))
