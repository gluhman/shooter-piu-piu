extends Control
## Entire presentation is at virtual 1920x1080 resolution and scales uniformly.
## Safe area is ~32px. Does not consume mouse or keyboard events.

const C_BG = Color(0.035,0.065,0.085,0.70) # HUD backplate: exactly 70% opacity
const C_PANEL = Color(0.046,0.085,0.11,0.70)
const C_BORDER = Color(0.40,0.54,0.61,0.29)
const C_WHITE = Color(0.94,0.97,0.98,1)
const C_MUTED = Color(0.58,0.67,0.72,1)
const C_BLUE = Color(0.25,0.77,0.98,1)
const C_RED = Color(1.0,0.35,0.36,1)
const C_YELLOW = Color(1.0,0.82,0.23,1)
const C_GREEN = Color(0.65,0.91,0.50,1)

const ICONS := {
	"rifle": preload("res://assets/hud/breakwater/rifle.png"),
	"pistol": preload("res://assets/hud/breakwater/pistol.png"),
	"knife": preload("res://assets/hud/breakwater/knife.png"),
	"frag": preload("res://assets/hud/breakwater/frag.png"),
	"flash": preload("res://assets/hud/breakwater/flash.png"),
	"medkit": preload("res://assets/hud/breakwater/medkit.png"),
	"shield": preload("res://assets/hud/breakwater/shield.png"),
	"skull": preload("res://assets/hud/breakwater/skull.png"),
	"headset": preload("res://assets/hud/breakwater/headset.png"),
	"wifi": preload("res://assets/hud/breakwater/wifi.png"),
	"smg": preload("res://assets/hud/breakwater/smg.png"),
	"shotgun": preload("res://assets/hud/breakwater/shotgun.png"),
	"sniper": preload("res://assets/hud/breakwater/sniper.png"),
	"lmg": preload("res://assets/hud/breakwater/lmg.png"),
	"dmr": preload("res://assets/hud/breakwater/dmr.png"),
	"target": preload("res://assets/hud/breakwater/target.png"),
}

var data: Dictionary = {}
var scoreboard_visible := false
var damage_direction := 0.0
var damage_left := 0.0
var kill_left := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	resized.connect(queue_redraw)


func _data(key: String, fallback: Variant) -> Variant:
	return data.get(key, fallback)


func view_scale() -> float:
	return minf(size.x / 1920.0, size.y / 1080.0)


func view_origin() -> Vector2:
	return (size - Vector2(1920, 1080) * view_scale()) * 0.5


func _draw() -> void:
	if data.is_empty():
		return
	draw_set_transform(view_origin(), 0.0, Vector2.ONE * view_scale())
	if scoreboard_visible:
		draw_set_transform(Vector2.ZERO)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.016, 0.027, 0.037, 0.72))
		draw_set_transform(view_origin(), 0.0, Vector2.ONE * view_scale())
		_draw_scoreboard()
		return
	_draw_compass()
	_draw_network()
	_draw_killfeed()
	_draw_status()
	if bool(_data("alive", false)):
		_draw_minimap_frame()
		_draw_team_scores()
		_draw_ammo()
		_draw_equipment()
	if damage_left > 0.0:
		var angle := damage_direction
		var center := Vector2(960, 540) + Vector2(0, -150).rotated(angle)
		var shape := PackedVector2Array([center + Vector2(0, -19).rotated(angle),
			center + Vector2(-18, 10).rotated(angle), center + Vector2(18, 10).rotated(angle)])
		draw_colored_polygon(shape, Color(C_RED, minf(1.0, damage_left * 2.5)))
	if kill_left > 0.0:
		_icon("skull", 944, 628, 32, C_YELLOW)
		_txt("УСТРАНЕНИЕ", 960, 682, 19, C_YELLOW, HORIZONTAL_ALIGNMENT_CENTER, 220)


func _draw_minimap_frame() -> void:
	_rect(29, 26, 290, 272, C_BG)
	draw_rect(Rect2(29, 26, 290, 272), C_BORDER, false, 1.4)
	_rect(29, 26, 5, 272, C_BLUE)
	_txt(_data("map_name", ""), 47, 52, 17, C_WHITE, HORIZONTAL_ALIGNMENT_LEFT, 225)
	_txt("N", 289, 52, 16, C_MUTED)

func _rect(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(x,y,w,h), c)

func _line(x: float, y: float, x2: float, y2: float, c: Color, width: float=1.0) -> void:
	draw_line(Vector2(x,y),Vector2(x2,y2),c,width,true)

func _txt(value: Variant, x: float, baseline_y: float, size_px: int=20, color: Color=C_WHITE, align: HorizontalAlignment=HORIZONTAL_ALIGNMENT_LEFT, maxw: float=-1.0) -> void:
	var svalue := str(value)
	# Treat x as the visual anchor, not left edge of an alignment width.
	var left_x := x
	if maxw > 0.0 and align == HORIZONTAL_ALIGNMENT_CENTER: left_x -= maxw*0.5
	if maxw > 0.0 and align == HORIZONTAL_ALIGNMENT_RIGHT: left_x -= maxw
	draw_string_outline(_font,Vector2(left_x,baseline_y),svalue,align,maxw,size_px,2,Color(0,0,0,0.47))
	draw_string(_font,Vector2(left_x,baseline_y),svalue,align,maxw,size_px,color)

func _icon(name: String, x: float, y: float, size_px: float, color: Color=C_WHITE) -> void:
	if ICONS.has(name) and ICONS[name] != null:
		draw_texture_rect(ICONS[name],Rect2(x,y,size_px,size_px),false,color)

func _bar(x: float,y: float,w: float,h: float,frac: float,c: Color) -> void:
	_rect(x,y,w,h,Color(0.22,0.31,0.36,0.67))
	_rect(x,y,w*clampf(frac,0.0,1.0),h,c)

func _score_font_size(score_value: int) -> int:
	# Reserve a 70px number column. Works for 1 to 5 digits without colliding
	# with the bars or the right edge of the 290x107 score panel.
	var digits := str(score_value).length()
	return 34 if digits <= 2 else 28 if digits == 3 else 21 if digits == 4 else 18

func _draw_team_scores() -> void:
	var mode := str(_data("mode","tdm"))
	# Aligned within x=29..319 / y=308..415 (no text or bar overflows).
	_rect(29,308,290,107,Color(0.025,0.05,0.065,0.70))
	draw_rect(Rect2(29,308,290,107),C_BORDER,false,1.0)
	_txt("СЧЁТ" if mode != "ffa" else "ЛИЧНЫЙ СЧЁТ",44,328,13,C_MUTED)
	if mode == "ffa":
		_line(44,336,303,336,C_BORDER)
		var kills := int(_data("kills",0))
		var deaths := int(_data("deaths",0))
		_txt("УБИЙСТВА",46,355,12,C_MUTED)
		_txt("СМЕРТИ",216,355,12,C_MUTED)
		_txt(kills,46,399,_score_font_size(kills),C_WHITE)
		var limit := int(_data("score_limit", 0))
		if limit > 0:
			_txt("/ %d" % limit,119,396,15,C_MUTED)
		_txt(deaths,301,398,_score_font_size(deaths),C_RED,HORIZONTAL_ALIGNMENT_RIGHT,75)
	else:
		var bs := int(_data("team_blue_score",0))
		var rs := int(_data("team_red_score",0))
		var cap := maxf(1.0, float(_data("score_limit", 0)))
		if cap == 1.0:
			cap = maxf(cap, maxf(bs, rs))
		var own := bs if int(_data("local_team", 0)) == 0 else rs
		var opposing := rs if int(_data("local_team", 0)) == 0 else bs
		var state := "НИЧЬЯ" if own == opposing else ("ПОБЕЖДАЕМ" if own > opposing else "ПРОИГРЫВАЕМ")
		_txt(state,303,328,11,C_YELLOW,HORIZONTAL_ALIGNMENT_RIGHT,112)
		_line(44,335,303,335,C_BORDER)
		# Number column: x=46..111. Bar/label column: x=119..295.
		_txt(bs,46,369,_score_font_size(bs),C_WHITE)
		_txt(rs,46,407,_score_font_size(rs),C_WHITE)
		_bar(119,343,174,7,float(bs)/cap,C_BLUE)
		_bar(119,381,174,7,float(rs)/cap,C_RED)
		_txt("СИНИЕ",119,366,13,C_BLUE)
		_txt("КРАСНЫЕ",119,404,13,C_RED)

func _draw_compass() -> void:
	_rect(648, 18, 630, 61, C_BG)
	var heading := float(_data("heading_deg", 0.0))
	var first_tick := ceili((heading - 90.0) / 15.0) * 15
	for degree in range(first_tick, first_tick + 180, 15):
		var offset := float(degree) - heading
		var x := 961.0 + offset * 3.1
		if absf(offset) < 13.0:
			continue
		var actual := posmod(degree, 360)
		var major := actual % 45 == 0
		_line(x, 24, x, 36 if major else 30, C_MUTED, 1.5 if major else 1.0)
		if major:
			_txt(_heading_label(actual), x, 58, 14, C_WHITE, HORIZONTAL_ALIGNMENT_CENTER, 58)
	_rect(924, 18, 74, 39, Color(0.10, 0.14, 0.16, 0.70))
	_txt(posmod(roundi(heading), 360), 961, 48, 25, C_YELLOW, HORIZONTAL_ALIGNMENT_CENTER, 70)
	_line(961, 55, 961, 69, C_YELLOW, 3)
	_txt(_data("clock", ""), 961, 102, 21, C_WHITE, HORIZONTAL_ALIGNMENT_CENTER, 150)


func _heading_label(degrees: int) -> String:
	var dirs := {0:"N",45:"NE",90:"E",135:"SE",180:"S",225:"SW",270:"W",315:"NW"}
	return str(dirs.get(degrees,str(degrees)))

func _draw_network() -> void:
	var online := bool(_data("online", false))
	var left := 1645.0 if online else 1732.0
	_rect(left, 27, 1888.0 - left, 52, C_BG)
	draw_rect(Rect2(left, 27, 1888.0 - left, 52), C_BORDER, false)
	_icon("headset", left + 15, 37, 26, C_WHITE)
	_txt(_data("alive_players", 0), left + 49, 62, 19, C_WHITE)
	if online:
		_icon("wifi", 1750, 38, 24, C_GREEN)
		_txt(_data("ping", "—"), 1782, 61, 19, C_WHITE)
	_txt(_data("network", ""),1868,60,15,C_YELLOW,HORIZONTAL_ALIGNMENT_RIGHT,54)

func _draw_killfeed() -> void:
	var feed: Array = _data("kill_feed",[])
	if feed.is_empty(): return
	_txt("ЛЕНТА УБИЙСТВ",43,470,13,C_MUTED)
	for i in range(mini(feed.size(),5)):
		var row: Dictionary = feed[i]
		var y := 480+i*34
		_rect(32,y,402,29,Color(0.025,0.055,0.074,0.70))
		_rect(32,y,3,29,C_BLUE if str(row.get("team","blue"))=="blue" else C_RED)
		_txt(str(row.get("killer","")),43,y+21,17,C_BLUE if str(row.get("team","blue"))=="blue" else C_RED,HORIZONTAL_ALIGNMENT_LEFT,148)
		_icon("skull",201,y+5,20,C_MUTED)
		_txt(str(row.get("victim","")),239,y+21,17,C_WHITE,HORIZONTAL_ALIGNMENT_LEFT,183)

func _draw_status() -> void:
	_txt(_data("medkit_hint", ""), 45, 908, 17, C_YELLOW)
	_rect(30,926,355,120,C_BG)
	draw_rect(Rect2(30,926,355,120),C_BORDER,false)
	_rect(30,926,5,120,C_BLUE)
	var health := int(_data("health",0))
	var max_health := maxi(1,int(_data("max_health",1)))
	var armor := int(_data("armor",0))
	var max_armor := maxi(1,int(_data("max_armor",1)))
	_txt("ЗДОРОВЬЕ",52,951,14,C_MUTED)
	_txt(health,52,1002,47,C_WHITE)
	_txt("/ %d" % max_health,142,995,16,C_MUTED)
	_bar(53,1020,145,9,float(health)/max_health,C_GREEN if health>30 else C_RED)
	_line(217,946,217,1029,C_BORDER)
	_icon("shield",228,948,28,C_BLUE)
	_txt("БРОНЯ",264,970,14,C_MUTED)
	_txt(armor,263,1006,33,C_WHITE)
	_txt("/ %d" % max_armor, 323, 1004, 15, C_MUTED)
	_bar(229,1020,140,9,float(armor)/max_armor,C_BLUE)

func _draw_ammo() -> void:
	_rect(1421,925,467,121,C_BG)
	draw_rect(Rect2(1421,925,467,121),C_BORDER,false)
	_rect(1421,925,5,121,C_YELLOW)
	_txt(_data("weapon_name", ""),1440,953,21,C_WHITE)
	_txt(_data("fire_mode", ""),1441,975,14,C_MUTED)
	_txt(_data("weapon_status", ""),1441,1000,14,C_YELLOW)
	_txt(_data("accuracy", ""),1441,1024,14,C_MUTED)
	_icon(str(_data("weapon_icon","rifle")),1608,940,43,C_WHITE)
	if int(_data("magazine_max", 0)) == 0:
		return
	_line(1667,943,1667,1030,C_BORDER)
	var ammo := int(_data("magazine", 0))
	var cap := maxi(1, int(_data("magazine_max", 0)))
	_txt(ammo,1691,1000,52,C_RED if ammo<=maxi(3,cap/5) else C_WHITE)
	_txt("/ %d" % cap,1693,947,12,C_MUTED)
	_line(1787,948,1787,1007,C_BORDER)
	_txt(_data("reserve", 0),1801,987,27,C_MUTED)
	_txt("ЗАПАС",1802,1009,12,C_MUTED)
	_bar(1690,1023,173,8,float(_data("reload_progress",0.0)) if bool(_data("reloading",false)) else float(ammo)/cap,C_BLUE if bool(_data("reloading",false)) else C_YELLOW if ammo>cap/5 else C_RED)

func _draw_equipment() -> void:
	var slots: Array = _data("equipment_slots", [])
	for i in slots.size():
		var item: Dictionary = slots[i]
		var x := 1897.0 - (slots.size() - i) * 106.0
		_rect(x, 817, 97, 89, C_BG)
		draw_rect(Rect2(x, 817, 97, 89), C_BORDER, false)
		_txt(item.label, x + 48, 836, 12, C_MUTED, HORIZONTAL_ALIGNMENT_CENTER, 90)
		_icon(item.icon, x + 20, 841, 34, C_WHITE if int(item.count) > 0 else C_MUTED)
		_txt(item.count, x + 75, 866, 18, C_WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 23)
		_rect(x + 14, 879, 69, 19, Color(0.18, 0.28, 0.32, 0.70))
		_txt(item.key, x + 48, 893, 12, C_WHITE, HORIZONTAL_ALIGNMENT_CENTER, 66)

func _draw_scoreboard() -> void:
	_rect(380,152,1160,772,Color(0.036,0.064,0.082,0.98))
	draw_rect(Rect2(380,152,1160,772),C_BORDER,false,2)
	_rect(380,152,1160,6,C_YELLOW)
	_txt("ТАБЛИЦА МАТЧА",412,208,28,C_WHITE)
	_txt("TAB — ЗАКРЫТЬ",1495,207,16,C_MUTED,HORIZONTAL_ALIGNMENT_RIGHT,200)
	_txt(_data("clock", ""),960,207,25,C_YELLOW,HORIZONTAL_ALIGNMENT_CENTER,120)
	var rows: Array = _data("scoreboard_rows",[])
	if str(_data("mode", "tdm")) == "ffa":
		_draw_scoreboard_ffa(rows)
		return
	var groups := ["blue","red"]
	for team_idx in range(2):
		var team: String = groups[team_idx]
		var yy := 253+float(team_idx)*311
		var col: Color = C_BLUE if team=="blue" else C_RED
		_rect(412,yy,1096,42,Color(col.r,col.g,col.b,0.21))
		_rect(412,yy,5,42,col)
		_txt("СИНИЕ" if team=="blue" else "КРАСНЫЕ",432,yy+29,21,C_WHITE)
		_txt(_data("team_blue_score",0) if team=="blue" else _data("team_red_score",0),1480,yy+32,27,col,HORIZONTAL_ALIGNMENT_RIGHT,90)
		_txt("ИГРОК",439,yy+76,15,C_MUTED)
		for j in range(2):
			_txt(["УБИЙСТВА","СМЕРТИ"][j],1038+j*138,yy+76,14,C_MUTED)
		var matching: Array = []
		for row in rows:
			if row.get("team", "") == team:
				matching.append(row)
		for i in range(mini(5,matching.size())):
			var p: Dictionary = matching[i]
			var row_y := yy+108+i*34
			if bool(p.get("self", false)):
				_rect(429, row_y - 22, 1059, 31, Color(1, 1, 1, 0.095))
			_txt(str(p.get("name","?")),440,row_y,17,C_YELLOW if bool(p.get("self",false)) else C_WHITE,HORIZONTAL_ALIGNMENT_LEFT,560)
			for j in range(2):
				_txt(str(p.get(["kills","deaths"][j],0)),1044+j*138,row_y,18,C_WHITE)

func _draw_scoreboard_ffa(raw_rows: Array) -> void:
	# Free-for-all has one ranking table (up to 10 participants), not two teams.
	# Values are supplied by the trusted match state; this is presentation only.
	var rows := raw_rows.duplicate()
	rows.sort_custom(func(a, b): return (int(a.get("kills",0)) > int(b.get("kills",0))) or (int(a.get("kills",0)) == int(b.get("kills",0)) and int(a.get("deaths",0)) < int(b.get("deaths",0))))
	_rect(412,248,1096,43,Color(0.16,0.25,0.29,0.75))
	_rect(412,248,5,43,C_YELLOW)
	var limit := int(_data("score_limit", 0))
	_txt("ДО %d УБИЙСТВ" % limit if limit > 0 else "БЕЗ ЛИМИТА УБИЙСТВ",435,277,19,C_WHITE)
	var two_columns := rows.size() > 10
	var column_width := 540.0 if two_columns else 1065.0
	for column in (2 if two_columns else 1):
		var x := 427.0 + column * 550.0
		_txt("ИГРОК", x + 90, 329, 14, C_MUTED)
		_txt("У", x + column_width - 140, 329, 14, C_MUTED)
		_txt("С", x + column_width - 74, 329, 14, C_MUTED)
	for i in mini(20, rows.size()):
		var player: Dictionary = rows[i]
		var x := 427.0 + (550.0 if i >= 10 else 0.0)
		var y := 371.0 + (i % 10) * 43.0
		var local := bool(player.get("self", false))
		if local or i % 2 == 0:
			_rect(x, y - 27, column_width, 39, Color(0.45,0.37,0.10,0.22) if local else Color(0.17,0.25,0.29,0.23))
		_txt(i + 1, x + 18, y, 19, C_YELLOW if i < 3 else C_MUTED)
		_txt(player.get("name", "?"), x + 90, y, 19, C_YELLOW if local else C_WHITE,
			HORIZONTAL_ALIGNMENT_LEFT, column_width - 250)
		_txt(player.get("kills", 0), x + column_width - 140, y, 19, C_WHITE)
		_txt(player.get("deaths", 0), x + column_width - 74, y, 19, C_WHITE)
