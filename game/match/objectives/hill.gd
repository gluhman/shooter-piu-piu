extends RefCounted

var active := 0
var next := -1
var order: Array[int] = [0, 1, 2]
var rotation := 45 * 60
var team := -1
var progress := 0
var absence := 0


func setup(seed_value: int, preset: int, fixed_first: int) -> void:
	if preset == 0:
		order = [0]
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		if rng.randi_range(0, 1) == 1:
			order = [0, 2, 1]
		if fixed_first >= 0:
			while order[0] != fixed_first:
				order.push_back(order.pop_front())
	active = order[0]


func step(ctx, actors: Array) -> void:
	if not ctx.overtime and ctx.left > 0 and order.size() > 1:
		rotation -= 1
		if rotation == 8 * 60:
			next = order[(order.find(active) + 1) % order.size()]
			ctx.notify("Следующая гора %d через 8 с" % (next + 1))
		if rotation == 0:
			active = next
			next = -1
			rotation = 45 * 60
			progress = 0
			ctx.notify("Открылась гора %d" % (active + 1))
	var present := 0
	for actor in actors:
		if ctx.in_zone(actor, active):
			present |= 1 << actor.team_id()
	var occupant := [-1, 0, 1, -2][present] as int
	if occupant != team:
		if occupant == -2:
			ctx.notify("Зона оспаривается")
		elif occupant >= 0:
			ctx.notify("Начался захват зоны", occupant, "Ваша команда захватывает зону", "Соперник захватывает зону")
		else:
			ctx.notify("Зона свободна")
	if occupant != team or occupant < 0:
		progress = 0
	team = occupant
	var was_tied: bool = ctx.scores.x == ctx.scores.y
	var prior_lead: int = ctx.leader()
	if team >= 0:
		progress += 1
		if progress == 60:
			progress = 0
			ctx.scores[team] += 1
			for actor in actors:
				if actor.team_id() == team and ctx.in_zone(actor, active):
					ctx.add_stat(actor, 0)
			if ctx.scores[team] >= ctx.target or (ctx.overtime and (was_tied or team != prior_lead and ctx.leader() == team)):
				ctx.finish("Контроль зоны")
				return
	var trailer: int = 1 - ctx.leader() if ctx.leader() >= 0 else -1
	if ctx.left == 0 and not ctx.overtime:
		if trailer < 0 or present & (1 << trailer):
			ctx.overtime = true
			ctx.left = 45 * 60
			ctx.notify("Овертайм")
			next = -1
		else:
			ctx.finish("Время вышло")
	elif ctx.overtime:
		if trailer >= 0 and not (present & (1 << trailer)):
			absence += 1
		else:
			absence = 0
		if absence >= 180 or ctx.left == 0:
			ctx.finish("Овертайм")


func view() -> Dictionary:
	return {"active": active, "next": next, "occupancy": team, "absence": absence}
