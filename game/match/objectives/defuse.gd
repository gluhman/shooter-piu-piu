extends RefCounted

enum { PREP, LIVE, PLANTED, RESULT }
var phase := PREP
var round_index := 0
var attack := 0
var initial_attack := 0
var carrier: Node3D
var dropped := Vector3.INF
var planted := Vector3.INF
var site := -1
var sites := 1
var holder: Node3D
var hold_target := -1
var hold_ticks := 0
var round_reason := ""
var live_counts := Vector2i.ZERO
var carrier_assigned := false
var done := false
var generation := 0


func setup(ctx, first_side: int) -> void:
	initial_attack = first_side
	sites = 1 if ctx.preset < 2 else 2
	begin(ctx)


func begin(ctx) -> void:
	generation += 1
	attack = initial_attack if round_index < 4 or round_index == 8 else 1 - initial_attack
	phase = PREP
	ctx.left = 5 * 60
	carrier = null
	carrier_assigned = false
	dropped = Vector3.INF
	planted = Vector3.INF
	site = -1
	cancel()
	round_reason = ""
	ctx.reset_defuse_round()


func cancel(actor: Node3D = null) -> void:
	if actor != null and holder != actor:
		return
	holder = null
	hold_target = -1
	hold_ticks = 0


func drop(ctx, actor: Node3D) -> void:
	cancel(actor)
	if carrier != actor:
		return
	carrier = null
	ctx.notify("", attack, "Перехватите упавший заряд", "")
	dropped = ctx.drop_floor(actor.gameplay_feet_position())
	if not dropped.is_finite():
		dropped = ctx.spawn_pool(attack)[0]


func action(ctx, actor: Node3D) -> int:
	if not ctx.eligible(actor, false) or not ctx.grounded(actor):
		return -1
	if phase == LIVE and actor == carrier:
		for index in sites:
			if ctx.in_zone(actor, index):
				return index
	elif phase == PLANTED and actor.team_id() != attack and actor.gameplay_feet_position().distance_to(planted) <= 1.5:
		if ctx.line_clear(actor.aim_center(), planted + Vector3.UP * 0.1):
			return 2
	return -1


func _end(ctx, winner: int, reason: String, cue := "") -> void:
	ctx.scores[winner] += 1
	phase = RESULT
	round_reason = reason
	ctx.notify(reason, -1, "", "", cue)
	ctx.left = 4 * 60
	carrier = null
	cancel()
	var completed := round_index + 1
	done = (completed <= 8 and maxi(ctx.scores.x, ctx.scores.y) == 5) or completed == 10


func step(ctx, actors: Array) -> void:
	live_counts = Vector2i.ZERO
	for actor in actors:
		live_counts[actor.team_id()] += 1
	if phase == PREP:
		if not carrier_assigned:
			var attackers: Array = actors.filter(func(actor): return actor.team_id() == attack)
			if not attackers.is_empty():
				var side_round := round_index % 4 if round_index < 8 else 4
				carrier = attackers[side_round % attackers.size()]
				carrier_assigned = true
		if ctx.left == 0:
			phase = LIVE
			ctx.left = [50, 55, 65, 75][ctx.preset] * 60
			for actor in actors:
				actor.cancel_spawn_protection()
		return
	if phase == RESULT:
		if ctx.left == 0:
			if done:
				ctx.finish(round_reason)
			else:
				round_index += 1
				begin(ctx)
		return
	if phase == LIVE and carrier == null and dropped.is_finite():
		carrier = ctx.nearest(actors, dropped, attack, 1.1)
		if carrier:
			dropped = Vector3.INF
			ctx.notify("", attack, "Ваша команда подобрала заряд", "")
	if holder != null and (not ctx.wants_interact(holder) or action(ctx, holder) != hold_target):
		ctx.clear_interact(holder)
		cancel()
	if holder == null:
		for actor in actors:
			if ctx.wants_interact(actor):
				var target := action(ctx, actor)
				if target >= 0:
					holder = actor
					hold_target = target
					break
	if holder != null:
		hold_ticks += 1
		if hold_target == 2 and hold_ticks >= 5 * 60:
			ctx.add_stat(holder, 1)
			_end(ctx, 1 - attack, "Заряд обезврежен", "defuse")
			return
		if hold_target != 2 and hold_ticks >= 3 * 60:
			ctx.add_stat(holder, 0)
			site = hold_target
			planted = ctx.drop_floor(holder.gameplay_feet_position())
			if not planted.is_finite():
				planted = ctx.centers[site]
			phase = PLANTED
			ctx.notify("Заряд установлен на точке %s" % ["A", "B"][site], -1, "", "", "plant")
			ctx.left = [25, 27, 30, 32][ctx.preset] * 60
			carrier = null
			cancel()
	if phase == PLANTED:
		if ctx.left == 0:
			ctx.effect(planted)
			_end(ctx, attack, "Заряд сработал")
		elif live_counts[1 - attack] == 0:
			_end(ctx, attack, "Защитники выбыли")
	elif live_counts[attack] == 0 or ctx.left == 0:
		_end(ctx, 1 - attack, "Установка сорвана")
	elif live_counts[1 - attack] == 0:
		_end(ctx, attack, "Защитники выбыли")


func view(team: int, peer: int) -> Dictionary:
	var friendly := team == attack
	return {"generation": generation, "phase": phase, "round": round_index + 1, "attack": attack, "site": site, "sites": sites,
		"planted": planted, "drop": dropped if friendly else Vector3.INF,
		"carrier": carrier.score_id() if carrier != null and friendly else 0,
		"carrying": carrier != null and friendly, "living": live_counts, "reason": round_reason,
		"hold": float(hold_ticks) / (300.0 if hold_target == 2 else 180.0) if holder != null and holder.score_id() == peer else 0.0}
