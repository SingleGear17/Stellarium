extends Node3D

# ============================================================
# BotMiner.gd — FIXED: Venture laser world-space offset
# ============================================================

enum BotState {
	IDLE,
	MOVING_TO_ASTEROID,
	MINING,
	MOVING_TO_STATION,
	DUMPING,
}

@export var bot_name: String          = "Bot-Miner-01"
@export var max_speed: float          = 12.0
@export var acceleration: float       = 5.0
@export var rotation_speed: float     = 2.0
@export var mining_range: float       = 12.0
@export var mining_yield: float       = 4.0
@export var station_position: Vector3 = Vector3.ZERO

var current_state: BotState  = BotState.IDLE
var velocity: Vector3        = Vector3.ZERO
var current_speed: float     = 0.0
var target_position: Vector3 = Vector3.ZERO
var target_asteroid: Node3D  = null

var _cargo_sys: Node             = null
var _mesh: Node3D                = null
var _laser_mesh: MeshInstance3D  = null
var _asteroids_node: Node3D      = null

# laser_offset: kalau Vector3.ZERO → pakai world-space (venture mode)
# kalau non-zero → pakai basis lokal (advent mode)
var laser_offset: Vector3 = Vector3(0.0, 0.8, 0.0)

var _idle_timer: float  = 0.0
var _dump_timer: float  = 2.0
var _scan_timer: float  = 0.0

# ============================================================
func _ready() -> void:
	_cargo_sys = get_node_or_null("CargoSystem")
	_mesh      = get_node_or_null("Mesh")
	_build_laser_visual()
	print("[BotMiner] %s online at %s" % [bot_name, str(global_position)])

# ============================================================
func _process(delta: float) -> void:
	match current_state:
		BotState.IDLE:               _state_idle(delta)
		BotState.MOVING_TO_ASTEROID: _state_move_to_asteroid(delta)
		BotState.MINING:             _state_mining(delta)
		BotState.MOVING_TO_STATION:  _state_move_to_station(delta)
		BotState.DUMPING:            _state_dumping(delta)

	_apply_movement(delta)
	_update_laser()

# ============================================================
func _state_idle(delta: float) -> void:
	_decelerate(delta)
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 2.0
		var ast = _find_best_asteroid()
		if ast:
			target_asteroid  = ast
			target_position  = ast.global_position
			target_position.y = 0
			current_state    = BotState.MOVING_TO_ASTEROID

func _state_move_to_asteroid(delta: float) -> void:
	if not is_instance_valid(target_asteroid) or target_asteroid.state == 2:
		current_state   = BotState.IDLE
		target_asteroid = null
		return
	var dist = global_position.distance_to(target_asteroid.global_position)
	if dist <= mining_range:
		current_state = BotState.MINING
		current_speed = 0.0
		velocity      = Vector3.ZERO
		return
	_move_toward(target_asteroid.global_position, delta)

func _state_mining(delta: float) -> void:
	if not is_instance_valid(target_asteroid) or target_asteroid.state == 2:
		current_state   = BotState.IDLE
		target_asteroid = null
		return
	var dir      = (target_asteroid.global_position - global_position).normalized()
	var look_rot = atan2(dir.x, dir.z)
	rotation.y   = lerp_angle(rotation.y, look_rot, rotation_speed * delta)

	if _cargo_sys and _cargo_sys.is_full():
		target_position = station_position
		current_state   = BotState.MOVING_TO_STATION
		return

	var extracted = target_asteroid.mine(mining_yield * delta)
	if extracted > 0.0 and _cargo_sys:
		_cargo_sys.add_ore(target_asteroid.ore_type, extracted)

func _state_move_to_station(delta: float) -> void:
	var dist = global_position.distance_to(station_position)
	if dist < 5.0:
		current_state = BotState.DUMPING
		_dump_timer   = 2.0
		current_speed = 0.0
		velocity      = Vector3.ZERO
		return
	_move_toward(station_position, delta)

func _state_dumping(delta: float) -> void:
	_dump_timer -= delta
	if _dump_timer <= 0.0:
		if _cargo_sys:
			_cargo_sys.clear()
		current_state = BotState.IDLE
		_scan_timer   = 1.0

# ============================================================
func _move_toward(dest: Vector3, delta: float) -> void:
	var flat_dest  = Vector3(dest.x, 0, dest.z)
	var direction  = (flat_dest - global_position)
	direction.y    = 0
	var distance   = direction.length()

	var target_speed = max_speed
	var brake_dist   = (current_speed * current_speed) / (2.0 * acceleration)
	if distance < brake_dist:
		target_speed = max_speed * (distance / brake_dist)
		target_speed = clamp(target_speed, 0.5, max_speed)

	current_speed = move_toward(current_speed, target_speed, acceleration * delta)
	velocity      = direction.normalized() * current_speed

	if velocity.length() > 0.1:
		var target_rot = atan2(velocity.x, velocity.z)
		rotation.y     = lerp_angle(rotation.y, target_rot, rotation_speed * delta)

func _decelerate(delta: float) -> void:
	current_speed = move_toward(current_speed, 0.0, acceleration * 2 * delta)
	velocity      = velocity.normalized() * current_speed

func _apply_movement(delta: float) -> void:
	global_position  += velocity * delta
	global_position.y = 0

# ============================================================
func _find_best_asteroid() -> Node3D:
	if not _asteroids_node:
		return null
	var best: Node3D     = null
	var best_dist: float = INF
	for ast in _asteroids_node.get_children():
		if not ast.has_method("mine"):
			continue
		if ast.state == 2:
			continue
		if ast.ore_remaining <= 5.0:
			continue
		var d = global_position.distance_to(ast.global_position)
		if d < best_dist:
			best_dist = d
			best      = ast
	return best

# ============================================================
# LASER — FIX VENTURE: pakai world-space origin, bukan basis lokal
# ============================================================
func _get_laser_origin() -> Vector3:
	# Kalau laser_offset adalah zero → venture mode: ambil posisi ship + Y offset saja
	# tanpa dikali basis, jadi tidak terpengaruh rotasi -90 model
	if laser_offset == Vector3.ZERO:
		return global_position + Vector3(0.0, 0.8, 0.0)
	# Advent dan ship lain: pakai basis lokal seperti biasa
	return global_position + (global_transform.basis * laser_offset)

func _build_laser_visual() -> void:
	_laser_mesh      = MeshInstance3D.new()
	_laser_mesh.name = "BotLaser"

	var cyl             = CylinderMesh.new()
	cyl.top_radius      = 0.12
	cyl.bottom_radius   = 0.02
	cyl.height          = 1.0
	cyl.radial_segments = 8
	_laser_mesh.mesh    = cyl

	var mat = StandardMaterial3D.new()
	mat.albedo_color               = Color(0.1, 1.0, 0.3, 0.3)
	mat.emission_enabled           = true
	mat.emission                   = Color(0.2, 1.0, 0.4)
	mat.emission_energy_multiplier = 4.0
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode                 = BaseMaterial3D.BLEND_MODE_ADD
	_laser_mesh.material_override  = mat

	var inner_mesh      = MeshInstance3D.new()
	var inner_cyl       = CylinderMesh.new()
	inner_cyl.top_radius    = 0.04
	inner_cyl.bottom_radius = 0.01
	inner_cyl.height        = 1.0
	inner_cyl.radial_segments = 4
	inner_mesh.mesh     = inner_cyl

	var inner_mat = StandardMaterial3D.new()
	inner_mat.albedo_color               = Color(1.0, 1.0, 1.0, 0.9)
	inner_mat.emission_enabled           = true
	inner_mat.emission                   = Color(0.8, 1.0, 0.8)
	inner_mat.emission_energy_multiplier = 8.0
	inner_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	inner_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	inner_mesh.material_override         = inner_mat

	_laser_mesh.add_child(inner_mesh)
	_laser_mesh.visible = false
	get_tree().current_scene.add_child.call_deferred(_laser_mesh)

func _update_laser() -> void:
	if not _laser_mesh:
		return
	if current_state != BotState.MINING or not is_instance_valid(target_asteroid):
		_laser_mesh.visible = false
		return

	_laser_mesh.visible = true
	var ast_pos      = target_asteroid.global_position
	var titik_tembak = _get_laser_origin()   # ← pakai helper yang fixed
	var dist         = titik_tembak.distance_to(ast_pos)

	_laser_mesh.global_position = titik_tembak.lerp(ast_pos, 0.5)
	_laser_mesh.scale           = Vector3.ONE
	_laser_mesh.look_at(ast_pos, Vector3.UP)
	_laser_mesh.rotate_object_local(Vector3.RIGHT, PI / 2)

	var time_sec = Time.get_ticks_msec() / 1000.0
	var pulse    = (sin(time_sec * 25.0) * 0.2) + 0.8
	_laser_mesh.scale = Vector3(pulse, dist, pulse)

# ============================================================
func set_asteroids_node(node: Node3D) -> void:
	_asteroids_node = node

func get_status() -> Dictionary:
	return {
		"name":  bot_name,
		"state": BotState.keys()[current_state],
		"cargo": _cargo_sys.get_summary() if _cargo_sys else "no cargo",
		"pos":   global_position,
	}
