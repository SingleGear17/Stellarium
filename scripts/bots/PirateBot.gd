extends Node3D

# ============================================================
# PirateBot.gd — v4 PATCH
#
# Perubahan dari v3:
#   - set_bots_node() ditambahkan → fix path "../../Bots" yang rawan salah
#   - _scan_for_target() sekarang pakai _bots_node reference langsung
#   - _on_target_destroyed_by_us() disambung dengan benar ke signal CombatSystem
# ============================================================

enum PirateState { IDLE, HUNTING, CHASING, ATTACKING, LOOTING }

@export var bot_name: String      = "Pirate-01"
@export var max_speed: float      = 22.0
@export var acceleration: float   = 9.0
@export var rotation_speed: float = 3.5
@export var attack_range: float   = 30.0
@export var weapon_damage: float  = 25.0
@export var fire_rate: float      = 2.0
@export var scan_radius: float    = 200.0
@export var loot_time: float      = 4.0

var current_state: PirateState = PirateState.IDLE
var velocity: Vector3          = Vector3.ZERO
var current_speed: float       = 0.0
var target_ship: Node3D        = null

var _combat_sys: Node           = null
var _cargo_sys: Node            = null
var _laser_mesh: MeshInstance3D = null
var _ships_node: Node3D         = null
var _bots_node: Node3D          = null   # ← FIX: reference langsung, bukan path relatif

var _fire_timer: float = 0.0
var _scan_timer: float = 0.0
var _loot_timer: float = 0.0
var _idle_timer: float = 0.0

signal target_destroyed(pirate: Node3D, victim: Node3D)

# ============================================================
func _ready() -> void:
	_combat_sys = get_node_or_null("CombatSystem")
	_cargo_sys  = get_node_or_null("CargoSystem")

	if _combat_sys:
		_combat_sys.destroyed.connect(_on_self_destroyed)

	_build_laser_visual()
	print("[PirateBot] %s online at %s" % [bot_name, str(global_position)])

# ============================================================
func _process(delta: float) -> void:
	if _combat_sys and not _combat_sys.is_alive:
		return

	match current_state:
		PirateState.IDLE:      _state_idle(delta)
		PirateState.HUNTING:   _state_hunting(delta)
		PirateState.CHASING:   _state_chasing(delta)
		PirateState.ATTACKING: _state_attacking(delta)
		PirateState.LOOTING:   _state_looting(delta)

	_apply_movement(delta)
	_update_laser()

# ============================================================
func _state_idle(delta: float) -> void:
	_decelerate(delta)
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		current_state = PirateState.HUNTING
		_scan_timer   = 0.0

func _state_hunting(delta: float) -> void:
	_decelerate(delta)
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = 2.0
	var found = _scan_for_target()
	if found:
		target_ship   = found
		current_state = PirateState.CHASING
		print("[PirateBot] %s locked target: %s" % [bot_name, found.name])

func _state_chasing(delta: float) -> void:
	if not _is_target_valid():
		_reset_to_idle(3.0)
		return
	var dist = global_position.distance_to(target_ship.global_position)
	if dist <= attack_range:
		current_state = PirateState.ATTACKING
		_fire_timer   = 0.0
		return
	_move_toward(target_ship.global_position, delta)

func _state_attacking(delta: float) -> void:
	if not _is_target_valid():
		_reset_to_idle(2.0)
		return

	var dist = global_position.distance_to(target_ship.global_position)
	if dist > attack_range * 1.8:
		current_state = PirateState.CHASING
		return

	_orbit_target(delta)

	var dir = (target_ship.global_position - global_position).normalized()
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), rotation_speed * delta)

	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = 1.0 / fire_rate
		_shoot()

func _state_looting(delta: float) -> void:
	_decelerate(delta)
	_loot_timer -= delta
	if _loot_timer <= 0.0:
		print("[PirateBot] %s looting done" % bot_name)
		_reset_to_idle(2.0)

# ============================================================
func _shoot() -> void:
	if not _is_target_valid():
		return
	var target_cs: Node = target_ship.get_node_or_null("CombatSystem")
	if target_cs and target_cs.has_method("take_damage"):
		target_cs.take_damage(weapon_damage, self)
		# Koneksikan signal destroyed target → kita tangkap untuk looting
		if not target_cs.destroyed.is_connected(_on_target_killed):
			target_cs.destroyed.connect(_on_target_killed)
		print("[PirateBot] %s → hit %s %.0fdmg | %s" % [
			bot_name, target_ship.name, weapon_damage, target_cs.get_summary()
		])

func _on_target_killed(_killer: Node) -> void:
	# Target mati — masuk looting state
	if current_state == PirateState.ATTACKING or current_state == PirateState.CHASING:
		current_state = PirateState.LOOTING
		_loot_timer   = loot_time
		print("[PirateBot] %s enters LOOTING" % bot_name)

# ============================================================
func _orbit_target(delta: float) -> void:
	var to_target  = target_ship.global_position - global_position
	to_target.y    = 0
	var perp       = to_target.cross(Vector3.UP).normalized()
	var orbit_dir  = (perp + to_target.normalized() * 0.3).normalized()
	var orbit_speed = max_speed * 0.6
	current_speed  = move_toward(current_speed, orbit_speed, acceleration * delta)
	velocity       = orbit_dir * current_speed

# ============================================================
func _scan_for_target() -> Node3D:
	var best: Node3D     = null
	var best_dist: float = INF

	# Scan ships_node (player + semua ship di sana)
	if _ships_node:
		for ship in _ships_node.get_children():
			if ship == self: continue
			var cs = ship.get_node_or_null("CombatSystem")
			if not cs or not cs.is_alive: continue
			var d = global_position.distance_to(ship.global_position)
			if d < scan_radius and d < best_dist:
				best_dist = d
				best      = ship

	# Scan bots_node (bot miner sebagai target sekunder)
	if _bots_node:
		for bot in _bots_node.get_children():
			if bot == self: continue
			var cs = bot.get_node_or_null("CombatSystem")
			if not cs or not cs.is_alive: continue
			var d = global_position.distance_to(bot.global_position)
			if d < scan_radius and d < best_dist:
				best_dist = d
				best      = bot

	return best

# ============================================================
func _is_target_valid() -> bool:
	if not target_ship or not is_instance_valid(target_ship):
		return false
	var cs = target_ship.get_node_or_null("CombatSystem")
	if cs and not cs.is_alive:
		return false
	return true

func _on_self_destroyed(_killer: Node) -> void:
	if _laser_mesh:
		_laser_mesh.visible = false
	await get_tree().create_timer(2.0).timeout
	queue_free()

func _reset_to_idle(wait: float) -> void:
	target_ship   = null
	current_state = PirateState.IDLE
	_idle_timer   = wait

# ============================================================
func _move_toward(dest: Vector3, delta: float) -> void:
	var direction = (Vector3(dest.x, 0, dest.z) - global_position)
	direction.y   = 0
	var distance  = direction.length()
	var target_speed  = max_speed
	var brake_dist    = (current_speed * current_speed) / (2.0 * acceleration)
	if distance < brake_dist:
		target_speed = max_speed * (distance / brake_dist)
		target_speed = clamp(target_speed, 1.0, max_speed)
	current_speed = move_toward(current_speed, target_speed, acceleration * delta)
	velocity      = direction.normalized() * current_speed
	if velocity.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z), rotation_speed * delta)

func _decelerate(delta: float) -> void:
	current_speed = move_toward(current_speed, 0.0, acceleration * 2 * delta)
	velocity      = velocity.normalized() * current_speed

func _apply_movement(delta: float) -> void:
	global_position  += velocity * delta
	global_position.y = 0.0

# ============================================================
func _build_laser_visual() -> void:
	_laser_mesh      = MeshInstance3D.new()
	_laser_mesh.name = "PirateLaser"

	var cyl             = CylinderMesh.new()
	cyl.top_radius      = 0.10
	cyl.bottom_radius   = 0.02
	cyl.height          = 1.0
	cyl.radial_segments = 8
	_laser_mesh.mesh    = cyl

	var mat = StandardMaterial3D.new()
	mat.albedo_color               = Color(1.0, 0.15, 0.1, 0.35)
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.1, 0.05)
	mat.emission_energy_multiplier = 5.0
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode                 = BaseMaterial3D.BLEND_MODE_ADD
	_laser_mesh.material_override  = mat

	var inner       = MeshInstance3D.new()
	var inner_cyl   = CylinderMesh.new()
	inner_cyl.top_radius    = 0.03
	inner_cyl.bottom_radius = 0.01
	inner_cyl.height        = 1.0
	inner_cyl.radial_segments = 4
	inner.mesh = inner_cyl
	var im = StandardMaterial3D.new()
	im.albedo_color               = Color(1.0, 0.8, 0.8, 1.0)
	im.emission_enabled           = true
	im.emission                   = Color(1.0, 0.6, 0.6)
	im.emission_energy_multiplier = 8.0
	im.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	inner.material_override       = im
	_laser_mesh.add_child(inner)

	_laser_mesh.visible = false
	get_tree().current_scene.add_child.call_deferred(_laser_mesh)

func _update_laser() -> void:
	if not _laser_mesh:
		return
	if current_state != PirateState.ATTACKING or not _is_target_valid():
		_laser_mesh.visible = false
		return

	var shooting = _fire_timer <= (1.0 / fire_rate) * 0.3
	_laser_mesh.visible = shooting
	if not shooting:
		return

	var target_pos = target_ship.global_position
	var dist       = global_position.distance_to(target_pos)
	_laser_mesh.global_position = global_position.lerp(target_pos, 0.5)
	_laser_mesh.scale           = Vector3.ONE
	_laser_mesh.look_at(target_pos, Vector3.UP)
	_laser_mesh.rotate_object_local(Vector3.RIGHT, PI / 2)
	var pulse = (sin(Time.get_ticks_msec() / 1000.0 * 35.0) * 0.25) + 0.85
	_laser_mesh.scale = Vector3(pulse, dist, pulse)

# ============================================================
func set_ships_node(node: Node3D) -> void:
	_ships_node = node

func set_bots_node(node: Node3D) -> void:
	_bots_node = node   # ← PUBLIC setter, dipanggil dari World._spawn_pirate_bots()

func get_status() -> Dictionary:
	return {
		"name":   bot_name,
		"state":  PirateState.keys()[current_state],
		"target": target_ship.name if target_ship else "none",
		"hp":     _combat_sys.get_summary() if _combat_sys else "no combat",
	}
