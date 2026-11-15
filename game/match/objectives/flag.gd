extends RefCounted

enum { HOME, CARRIED, DROPPED }
const CAPTURE_TICKS := 2 * 60
var flags: Array[Dictionary] = []
var capture_ticks := Vector2i.ZERO


func setup(centers: PackedVector3Array) -> void:
	for center in centers:
		flags.append({"state": HOME, "carrier": null, "at": center, "left": 0, "immune": 0,
			"carried_ticks": 0, "revealed": Vector3.INF})


func _home(ctx, team: int, immunity := 0) -> void:
	var flag := flags[team]
	flag.state = HOME
	flag.carrier = null
	flag.at = ctx.centers[team]
	flag.left = 0
	flag.immune = immunity
	flag.revealed = Vector3.INF


func drop(ctx, actor: Node3D) -> void:
	for team in 2:
		var flag := flags[team]
		if flag.carrier != actor:
			continue
		capture_ticks[1 - team] = 0
		var at: Vector3 = ctx.drop_floor(actor.gameplay_feet_position())
		if at.is_finite():
			flag.state = DROPPED
			flag.carrier = null
			flag.at = at
			flag.left = (12 if ctx.preset < 2 else 15) * 60
			ctx.notify("Флаг упал", team, "Ваш флаг упал", "Носитель уронил флаг соперника")
		else:
			_home(ctx, team)
			ctx.notify("Флаг вернулся на базу", team, "Ваш флаг вернулся на базу", "Флаг соперника вернулся на базу")


func step(ctx, actors: Array) -> void:
	for team in 2:
		var flag := flags[team]
		flag.immune = maxi(0, flag.immune - 1)
		if flag.state == CARRIED:
			flag.carried_ticks += 1
			var carrier: Node3D = flag.carrier
			if flag.carried_ticks >= 45 * 60 and (flag.carried_ticks - 45 * 60) % 600 == 0:
				var point := carrier.global_position
				flag.revealed = Vector3(snappedf(point.x, 4.0), point.y, snappedf(point.z, 4.0))
			elif ctx.tick % 6 == 0:
				for actor in actors:
					if actor.team_id() == team and ctx.can_see(actor, carrier):
						flag.revealed = carrier.global_position
						break
			continue
		var returned := false
		if flag.state == DROPPED:
			flag.left -= 1
			var returner: Node3D = ctx.nearest(actors, flag.at, team, 1.25)
			if flag.left == 0 or returner != null:
				if returner:
					ctx.add_stat(returner, 1)
				_home(ctx, team)
				ctx.notify("Флаг вернулся на базу", team, "Ваш флаг вернулся на базу", "Флаг соперника вернулся на базу")
				returned = true
		if returned or flag.immune > 0:
			continue
		var thief: Node3D = ctx.nearest(actors, flag.at, 1 - team, 1.25)
		if thief:
			flag.state = CARRIED
			flag.carrier = thief
			flag.carried_ticks = 0
			flag.revealed = Vector3.INF
			ctx.notify("Флаг подобран", team, "Соперник забрал ваш флаг", "Ваша команда забрала флаг соперника")
	var was_tied: bool = ctx.scores.x == ctx.scores.y
	for team in 2:
		var enemy := flags[1 - team]
		var can_capture: bool = enemy.state == CARRIED and flags[team].state == HOME 			and actors.has(enemy.carrier) and ctx.in_zone(enemy.carrier, team)
		if not can_capture:
			capture_ticks[team] = 0
			continue
		capture_ticks[team] += 1
		if capture_ticks[team] >= CAPTURE_TICKS:
			capture_ticks[team] = 0
			ctx.scores[team] += 1
			ctx.add_stat(enemy.carrier, 0)
			_home(ctx, 1 - team, 120)
			ctx.notify("Флаг захвачен", team, "Ваша команда захватила флаг соперника", "Соперник захватил ваш флаг", "capture")
			if ctx.scores[team] >= ctx.target or (ctx.overtime and was_tied):
				ctx.finish("Флаг доставлен")
				return
	var leading: int = ctx.leader()
	if ctx.left == 0 and not ctx.overtime:
		if leading < 0 or flags[leading].state != HOME:
			ctx.overtime = true
			ctx.left = 30 * 60
			ctx.notify("Овертайм")
		else:
			ctx.finish("Время вышло")
	elif ctx.overtime and (ctx.left == 0 or leading >= 0 and flags[leading].state == HOME):
		ctx.finish("Овертайм")


func view(team: int, peer := -1) -> Dictionary:
	var visible_flags: Array = []
	for index in 2:
		var flag := flags[index]
		var at: Vector3 = Vector3.INF
		var carrier_id := 0
		var mounted: bool = flag.state == CARRIED and team >= 0
		var allied := mounted and team == 1 - index
		if flag.state == HOME or (flag.state == DROPPED and team == index):
			at = flag.at
		elif mounted:
			# The world model follows the replicated actor and is occluded by the scene.
			# HUD markers still use the last spotted position for an opposing carrier.
			carrier_id = flag.carrier.score_id()
			at = flag.carrier.global_position if allied else flag.revealed
		visible_flags.append({"state": flag.state, "at": at, "left": flag.left, "carrier": carrier_id,
			"allied_carrier": allied, "mounted": mounted})
	var local_ticks := 0
	if team >= 0 and visible_flags[1 - team].allied_carrier and visible_flags[1 - team].carrier == peer:
		local_ticks = capture_ticks[team]
	return {"flags": visible_flags,
		"capture": local_ticks, "capture_total": CAPTURE_TICKS}
