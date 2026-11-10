class_name WandererBrain
extends RefCounted

const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")
const WandererRouteGraph = preload("res://src/presentation/wanderer/wanderer_route_graph.gd")
const WandererContent = preload("res://src/presentation/wanderer/wanderer_content.gd")
const WandererImagePlacement = preload("res://src/presentation/wanderer/wanderer_image_placement.gd")

enum State {DISABLED, WALKING, DOOR_PAUSE, INSIDE, EXIT_PAUSE, SAYING, SHOWING, EXIT_WALK}

var state: int = State.DISABLED
var state_t: float = 0.0
var figure_visible: bool = false
var pos: Vector2 = Vector2.ZERO
var present_pos: Vector2 = Vector2.ZERO
var door_exterior_pos: Vector2 = Vector2.ZERO
var yaw: float = 0.0
var walk_phase: float = 0.0
var motion: float = 0.0
var bubble_text: String = ""
var bubble_alpha: float = 0.0
var bubble_kind: String = ""
var image_index: int = -1
var image_alpha: float = 0.0
var image_placement: Dictionary = {}
var quote_clock: float = 0.0
var current_house: int = -1
var last_house: int = -1
var target_house: int = -1
var cycles_completed: int = 0
var route_progress_m: float = 0.0
var route_length_m: float = 0.0

var _params: WandererParams = null
var _graph: WandererRouteGraph = null
var _content: WandererContent = null
var _rng := RandomNumberGenerator.new()
var _events: Array = []
var _route: PackedVector2Array = PackedVector2Array()
var _route_cum: PackedFloat32Array = PackedFloat32Array()
var _leg_walk_t: float = 0.0
var _motion_smoothed: float = 0.0
var _last_quote_idx: int = -1
var _last_image_idx: int = -1
var _image_bag: PackedInt32Array = PackedInt32Array()
var _image_bag_i: int = 0
var _last_phrase_idx: int = -1
var _bubble_timer: float = 0.0
var _bubble_total: float = 0.0
var _showing_timer: float = 0.0
var _warned_disabled: bool = false
var _stepped_out: bool = false
var _leg_gate_open: bool = true
var _exit_walk_n: Vector2 = Vector2.ZERO


static func state_name(s: int) -> String:
	match s:
		State.DISABLED: return "DISABLED"
		State.WALKING: return "WALKING"
		State.DOOR_PAUSE: return "DOOR_PAUSE"
		State.INSIDE: return "INSIDE"
		State.EXIT_PAUSE: return "EXIT_PAUSE"
		State.SAYING: return "SAYING"
		State.SHOWING: return "SHOWING"
		State.EXIT_WALK: return "EXIT_WALK"
		_: return "?"


func setup(p: WandererParams, graph: WandererRouteGraph, content: WandererContent, rng: RandomNumberGenerator) -> void:
	_params = p
	_graph = graph
	_content = content
	_rng = rng
	_rebuild_image_bag()


func start() -> void:
	_events.clear()
	if _graph == null or _graph.is_disabled():
		_enter_state(State.DISABLED)
		if not _warned_disabled:
			push_warning("WandererBrain: disabled — insufficient houses")
			_warned_disabled = true
		return
	var reachable := _graph.reachable_houses()
	if reachable.size() < 2:
		_enter_state(State.DISABLED)
		return
	last_house = reachable[_rng.randi_range(0, reachable.size() - 1)]
	pos = _graph.houses[last_house].get("door_spot", Vector2.ZERO)
	_pick_target_and_route()
	quote_clock = 0.0
	_leg_walk_t = 0.0
	_stepped_out = false
	_leg_gate_open = true
	_enter_state(State.WALKING)


func tick(dt: float) -> void:
	if state == State.DISABLED:
		return
	var remaining := dt
	var guard := 0
	while remaining > 1e-6 and guard < 64:
		guard += 1
		var step := minf(remaining, 0.25)
		var used := _tick_state(step)
		remaining -= used


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _events:
		out.append(e)
	_events.clear()
	return out


func preview_placement(aspect: float) -> Dictionary:
	var h := _house(last_house)
	var n: Vector2 = h.get("normal", Vector2(0, 1))
	var door: Vector2 = h.get("door_exterior", h.get("door", Vector2.ZERO))
	return WandererImagePlacement.compute(door, n, _params, aspect)


func debug_begin_exit(house: int) -> void:
	if _graph == null or house < 0 or house >= _graph.houses.size():
		return
	last_house = house
	target_house = house
	_stepped_out = false
	var h := _house(house)
	pos = h.get("door_spot", Vector2.ZERO)
	_enter_state(State.EXIT_PAUSE)


func _tick_state(dt: float) -> float:
	match state:
		State.WALKING:
			return _tick_walking(dt)
		State.DOOR_PAUSE:
			state_t += dt
			_update_yaw_toward(-_house_normal(target_house), dt)
			_blend_motion(0.0, dt)
			if state_t >= _params.door_pause_s:
				_enter_state(State.INSIDE)
			return dt
		State.INSIDE:
			state_t += dt
			figure_visible = false
			bubble_text = ""
			bubble_alpha = 0.0
			if state_t >= _params.inside_s:
				last_house = target_house
				pos = _graph.houses[target_house].get("door_spot", Vector2.ZERO)
				door_exterior_pos = _house_door_exterior(target_house)
				var n := _house_normal(target_house)
				yaw = _yaw_of(n)
				_stepped_out = false
				_enter_state(State.EXIT_PAUSE)
			return dt
		State.EXIT_PAUSE:
			state_t += dt
			figure_visible = true
			_blend_motion(0.0, dt)
			if state_t >= _params.exit_pause_s:
				if _content.image_count() > 0:
					_enter_state(State.EXIT_WALK)
				elif _content.quote_count() > 0:
					_enter_state(State.SAYING)
				else:
					_begin_next_leg()
					_enter_state(State.WALKING)
			return dt
		State.EXIT_WALK:
			return _tick_exit_walk(dt)
		State.SAYING:
			return _tick_saying(dt)
		State.SHOWING:
			return _tick_showing(dt)
		_:
			return dt


func _tick_exit_walk(dt: float) -> float:
	figure_visible = true
	if _advance_along_route(dt, false):
		pos = present_pos
		yaw = _yaw_of(_exit_walk_n)
		if _content.quote_count() > 0:
			_enter_state(State.SAYING)
		else:
			_enter_state(State.SHOWING)
	return dt


func _tick_walking(dt: float) -> float:
	figure_visible = true
	if _route.size() < 2 or route_length_m < 1e-6:
		_enter_state(State.DOOR_PAUSE)
		return dt
	if not _leg_gate_open:
		quote_clock += dt
		_leg_walk_t += dt
		var tangent := _tangent_at(route_progress_m)
		if tangent.length_squared() < 1e-9:
			_leg_gate_open = true
		else:
			_apply_yaw_toward(tangent, dt)
		var gate_rad := deg_to_rad(_params.leg_turn_gate_deg)
		if absf(wrapf(yaw - _yaw_of(tangent), -PI, PI)) <= gate_rad:
			_leg_gate_open = true
		_blend_motion(0.0, dt)
		return dt
	if _advance_along_route(dt, true):
		_enter_state(State.DOOR_PAUSE)
	return dt


func _advance_along_route(dt: float, walking_leg: bool) -> bool:
	var v_nom := _params.walk_speed_mps
	var ease := _speed_factor()
	var v := v_nom * ease
	var ds := v * dt
	route_progress_m = minf(route_progress_m + ds, route_length_m)
	walk_phase += TAU * v * dt / _params.stride_length_m
	_blend_motion(v / maxf(v_nom, 1e-6), dt)
	if walking_leg:
		quote_clock += dt
		_leg_walk_t += dt
		pos = _sample_route(route_progress_m)
		_update_yaw_route(route_progress_m, dt)
		_maybe_quote()
		_tick_bubble_fade(dt)
	else:
		yaw = _yaw_of(_exit_walk_n)
		pos = _sample_route(route_progress_m)
	if route_progress_m >= route_length_m - 1e-4:
		if _route.size() > 0:
			pos = _route[_route.size() - 1]
		return true
	return false


func _tick_saying(dt: float) -> float:
	state_t += dt
	figure_visible = true
	_blend_motion(0.0, dt)
	var fi := _params.bubble_fade_in_s
	var fo := _params.bubble_fade_out_s
	var hold := _bubble_total - fi - fo
	if state_t < fi:
		bubble_alpha = state_t / maxf(fi, 1e-6)
	elif state_t < fi + hold:
		bubble_alpha = 1.0
	elif state_t < _bubble_total:
		bubble_alpha = 1.0 - (state_t - fi - hold) / maxf(fo, 1e-6)
	else:
		bubble_alpha = 0.0
		bubble_text = ""
		if _content.image_count() > 0:
			_enter_state(State.SHOWING)
		else:
			_begin_next_leg()
			_enter_state(State.WALKING)
	return dt


func _tick_showing(dt: float) -> float:
	state_t += dt
	figure_visible = true
	_blend_motion(0.0, dt)
	var fade := _params.image_fade_s
	var hold := _params.image_s - 2.0 * fade
	if state_t < fade:
		image_alpha = state_t / maxf(fade, 1e-6)
	elif state_t < fade + hold:
		image_alpha = 1.0
	elif state_t < _params.image_s:
		image_alpha = 1.0 - (state_t - fade - hold) / maxf(fade, 1e-6)
	else:
		image_alpha = 0.0
		image_index = -1
		cycles_completed += 1
		_begin_next_leg()
		_enter_state(State.WALKING)
	return dt


func _enter_state(next: int) -> void:
	var from := state
	if from != next:
		_events.append({"type": "state", "from": from, "to": next})
	state = next
	state_t = 0.0
	match next:
		State.WALKING:
			figure_visible = true
		State.DOOR_PAUSE:
			figure_visible = true
		State.EXIT_PAUSE:
			figure_visible = true
			if from != State.INSIDE:
				yaw = _yaw_of(_house_normal(last_house))
		State.INSIDE:
			figure_visible = false
			bubble_text = ""
			bubble_alpha = 0.0
		State.EXIT_WALK:
			figure_visible = true
			var h := _house(last_house)
			var n: Vector2 = h.get("normal", Vector2(0, 1))
			_exit_walk_n = n
			door_exterior_pos = _house_door_exterior(last_house)
			present_pos = door_exterior_pos + n * _params.present_standoff()
			var door_spot: Vector2 = h.get("door_spot", Vector2.ZERO)
			_route = PackedVector2Array([door_spot, present_pos])
			_build_route_cum()
			route_progress_m = 0.0
			yaw = _yaw_of(n)
			_stepped_out = true
		State.SAYING:
			figure_visible = true
			var qi := _pick_idx(_content.quote_count(), _last_phrase_idx)
			_last_phrase_idx = qi
			bubble_text = _content.quote(qi)
			bubble_kind = "phrase"
			_bubble_total = _params.bubble_duration(bubble_text)
			bubble_alpha = 0.0
			_events.append({"type": "bubble", "text": bubble_text, "kind": bubble_kind})
		State.SHOWING:
			figure_visible = true
			bubble_text = ""
			bubble_alpha = 0.0
			image_index = _next_image_idx()
			_last_image_idx = image_index
			var asp := _content.aspect(image_index) if _content.image_count() > 0 else 4.0 / 3.0
			var hn := _house(last_house)
			var n2: Vector2 = hn.get("normal", Vector2(0, 1))
			var door := _house_door_exterior(last_house)
			pos = present_pos if present_pos.length_squared() > 1e-6 else door + n2 * _params.present_standoff()
			yaw = _yaw_of(n2)
			image_placement = WandererImagePlacement.compute(door, n2, _params, asp)
			image_alpha = 0.0
			_events.append({"type": "image", "index": image_index, "placement": image_placement})
		State.DISABLED:
			figure_visible = false


func _begin_next_leg() -> void:
	_pick_target_and_route()
	if _stepped_out and _route.size() >= 1:
		var h := _house(last_house)
		var stoop: Vector2 = h.get("stoop", Vector2.ZERO)
		var base := _graph.route(last_house, target_house)
		_route = WandererRouteGraph.leg_from_present(base, present_pos, stoop)
		_build_route_cum()
		route_progress_m = 0.0
		_stepped_out = false
	_leg_gate_open = false
	_leg_walk_t = 0.0


func _pick_target_and_route() -> void:
	var cands := _graph.candidates_from(last_house)
	if cands.is_empty():
		_route = PackedVector2Array()
		route_length_m = 0.0
		return
	target_house = cands[_rng.randi_range(0, cands.size() - 1)]
	_route = _graph.route(last_house, target_house)
	_build_route_cum()
	route_progress_m = 0.0
	current_house = last_house


func _build_route_cum() -> void:
	_route_cum = PackedFloat32Array()
	_route_cum.append(0.0)
	var total := 0.0
	for i in range(1, _route.size()):
		total += _route[i - 1].distance_to(_route[i])
		_route_cum.append(total)
	route_length_m = total


func _sample_route(s: float) -> Vector2:
	if _route.is_empty():
		return pos
	if s <= 0.0:
		return _route[0]
	if s >= route_length_m:
		return _route[_route.size() - 1]
	for i in range(_route_cum.size() - 1):
		if s <= _route_cum[i + 1]:
			var seg := _route_cum[i + 1] - _route_cum[i]
			var t := (s - _route_cum[i]) / maxf(seg, 1e-9)
			return _route[i].lerp(_route[i + 1], t)
	return _route[_route.size() - 1]


func _tangent_at(s: float) -> Vector2:
	var look := minf(s + 0.5, route_length_m)
	var a := _sample_route(s)
	var b := _sample_route(look)
	var d := b - a
	if d.length_squared() < 1e-9 and _route.size() >= 2:
		d = _route[_route.size() - 1] - _route[0]
	if d.length_squared() < 1e-9 and _route.size() >= 2:
		d = _route[1] - _route[0]
	if d.length_squared() < 1e-9:
		d = -_exit_walk_n if _stepped_out and _exit_walk_n.length_squared() > 1e-9 else Vector2(0.0, 1.0)
	return d.normalized()


func _speed_factor() -> float:
	var s := route_progress_m
	var rem := route_length_m - s
	var m := minf(s, rem)
	return clampf(m / _params.speed_ease_m, 0.25, 1.0)


func _update_yaw_route(s: float, dt: float) -> void:
	var dir := _tangent_at(s)
	_apply_yaw_toward(dir, dt)


func _update_yaw_toward(dir: Vector2, dt: float) -> void:
	if dir.length_squared() < 1e-9:
		return
	_apply_yaw_toward(dir, dt)


func _apply_yaw_toward(dir: Vector2, dt: float) -> void:
	var target := atan2(dir.x, dir.y)
	var max_d := deg_to_rad(_params.turn_rate_deg_s) * dt
	yaw = _lerp_angle_limited(yaw, target, max_d)


func _yaw_of(n: Vector2) -> float:
	return atan2(n.x, n.y)


func _lerp_angle_limited(from: float, to: float, max_step: float) -> float:
	var delta := wrapf(to - from, -PI, PI)
	delta = clampf(delta, -max_step, max_step)
	return from + delta


func _blend_motion(target: float, dt: float) -> void:
	var rate := 1.0 / maxf(_params.idle_blend_s, 1e-6)
	_motion_smoothed = lerpf(_motion_smoothed, target, minf(1.0, rate * dt))
	motion = _motion_smoothed


func _house(h: int) -> Dictionary:
	if h < 0 or h >= _graph.houses.size():
		return {}
	return _graph.houses[h] as Dictionary


func _house_normal(h: int) -> Vector2:
	return _house(h).get("normal", Vector2(0, 1)) as Vector2


func _house_door_exterior(h: int) -> Vector2:
	var hd := _house(h)
	return hd.get("door_exterior", hd.get("door", Vector2.ZERO)) as Vector2


func _tick_bubble_fade(dt: float) -> void:
	if bubble_text.is_empty():
		bubble_alpha = 0.0
		return
	_bubble_timer += dt
	var fi := _params.bubble_fade_in_s
	var fo := _params.bubble_fade_out_s
	var hold := _bubble_total - fi - fo
	if _bubble_timer < fi:
		bubble_alpha = _bubble_timer / maxf(fi, 1e-6)
	elif _bubble_timer < fi + hold:
		bubble_alpha = 1.0
	elif _bubble_timer < _bubble_total:
		bubble_alpha = 1.0 - (_bubble_timer - fi - hold) / maxf(fo, 1e-6)
	else:
		bubble_alpha = 0.0
		bubble_text = ""


func _maybe_quote() -> void:
	if _content.quote_count() == 0:
		return
	if _leg_walk_t < _params.quote_min_walk_s:
		return
	if quote_clock < _params.quote_interval_s:
		return
	if not bubble_text.is_empty():
		return
	var qi := _pick_idx(_content.quote_count(), _last_quote_idx)
	_last_quote_idx = qi
	bubble_text = _content.quote(qi)
	bubble_kind = "quote"
	_bubble_total = _params.bubble_duration(bubble_text)
	_bubble_timer = 0.0
	bubble_alpha = 0.0
	quote_clock = 0.0
	_events.append({"type": "bubble", "text": bubble_text, "kind": bubble_kind})


func _pick_idx(n: int, last_ref: int) -> int:
	if n <= 0:
		return 0
	if n == 1:
		return 0
	var pick := _rng.randi_range(0, n - 1)
	while pick == last_ref:
		pick = _rng.randi_range(0, n - 1)
	return pick


func _rebuild_image_bag() -> void:
	_image_bag = PackedInt32Array()
	_image_bag_i = 0
	var n := _content.image_count() if _content != null else 0
	if n <= 0:
		return
	if n == 1:
		_image_bag.append(0)
		return
	for i in n:
		_image_bag.append(i)
	_shuffle_image_bag(false)


func _shuffle_image_bag(avoid_repeat: bool) -> void:
	var n := _image_bag.size()
	if n <= 1:
		return
	for i in range(n - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := _image_bag[i]
		_image_bag[i] = _image_bag[j]
		_image_bag[j] = tmp
	if avoid_repeat and n > 1 and _last_image_idx >= 0 and _image_bag[0] == _last_image_idx:
		var j := _rng.randi_range(1, n - 1)
		var tmp := _image_bag[0]
		_image_bag[0] = _image_bag[j]
		_image_bag[j] = tmp


func _next_image_idx() -> int:
	var n := _content.image_count() if _content != null else 0
	if n <= 0:
		return 0
	if n == 1:
		return 0
	if _image_bag.size() != n:
		_rebuild_image_bag()
	if _image_bag_i >= _image_bag.size():
		_shuffle_image_bag(true)
		_image_bag_i = 0
	var idx := _image_bag[_image_bag_i]
	_image_bag_i += 1
	_last_image_idx = idx
	return idx
