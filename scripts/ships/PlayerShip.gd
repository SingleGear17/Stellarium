extends CharacterBody3D

# ============================================================
# PlayerShip.gd — v4: COMBAT ATTACK SYSTEM ADDED
# Tambahan dari v3:
#   - State ATTACKING baru
#   - target_enemy: Node3D → ship/pirate yang mau diserang
#   - _weapon_laser: laser merah terpisah dari mining laser
#   - Right-click pada ship/pirate → serang
#   - Weapon: damage, fire_rate, weapon_range
#   - Signal enemy_targeted(enemy) → untuk HUD nanti
# ============================================================

enum State { IDLE, MOVING, MINING, ATTACKING }

@export var max_speed: float       = 20.0
@export var acceleration: float    = 8.0
@export var rotation_speed: float  = 3.0
@export var ship_name: String      = "Frigate MK-I"

# --- Weapon stats (set dari World.gd berdasarkan ship class) ---
@export var weapon_damage: float   = 20.0
@export var weapon_range: float    = 40.0
@export var fire_rate: float       = 1.5   # tembakan per detik

var current_state: State  = State.IDLE
var target_position: Vector3 = Vector3.ZERO
var current_speed: float  = 0.0

var target_asteroid: Node3D = null
var target_enemy: Node3D    = null   # ← TARGET SERANG

const MINING_RANGE: float = 15.0
const MINING_YIELD: float = 10.0

var _mesh: Node3D                    = null
var _engine_trail: GPUParticles3D    = null
var _selection_ring: MeshInstance3D  = null
var _laser_mesh: MeshInstance3D      = null   # mining laser (biru)
var _weapon_laser: MeshInstance3D    = null   # weapon laser (merah)
var _cargo_sys: Node                 = null
var _combat_sys: Node                = null

var _fire_timer: float = 0.0

signal enemy_targeted(enemy: Node3D)
signal enemy_lost()

# ============================================================
func _ready() -> void:
	var col = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 2.0
	col.shape = sphere
	add_child(col)
	target_position = global_position
	_mesh           = get_node_or_null("Mesh")
	_engine_trail   = get_node_or_null("EngineTrail")
	_selection_ring = get_node_or_null("SelectionRing")
	_cargo_sys      = get_node_or_null("CargoSystem")
	_combat_sys     = get_node_or_null("CombatSystem")

	if _combat_sys:
		_combat_sys.destroyed.connect(_on_destroyed)
	if _selection_ring:
		_selection_ring.visible = false

	_build_mining_laser()
	_build_weapon_laser()
	print("[PlayerShip] %s initialized" % ship_name)

# ============================================================
func _process(delta: float) -> void:
	match current_state:
		State.IDLE:
			_decelerate(delta)
			_hide_lasers()

		State.MOVING:
			_handle_movement(delta)
			_handle_rotation(delta)
			_hide_lasers()

		State.MINING:
			_decelerate(delta)
			_handle_mining(delta)

		State.ATTACKING:
			_handle_attacking(delta)

	_update_engine_effect()

# ============================================================
# PUBLIC — dipanggil dari World.gd saat klik
# ============================================================
func move_to(world_position: Vector3) -> void:
	target_position   = world_position
	target_position.y = 0
	target_asteroid   = null
	target_enemy      = null
	current_state     = State.MOVING
	emit_signal("enemy_lost")

func move_to_mine(asteroid: Node3D) -> void:
	target_asteroid   = asteroid
	target_position   = asteroid.global_position
	target_position.y = 0
	target_enemy      = null
	current_state     = State.MOVING
	emit_signal("enemy_lost")

func attack_target(enemy: Node3D) -> void:
	# Dipanggil dari World._handle_right_click kalau klik ship musuh
	target_enemy    = enemy
	target_asteroid = null
	current_state   = State.ATTACKING
	_fire_timer     = 0.0
	emit_signal("enemy_targeted", enemy)
	print("[PlayerShip] Targeting: %s" % enemy.name)

# ============================================================
func _handle_movement(delta: float) -> void:
	var direction = (target_position - global_position)
	direction.y   = 0
	var distance  = direction.length()

	if target_asteroid != null and distance <= MINING_RANGE:
		current_state = State.MINING
		velocity = Vector3.ZERO
		return

	if distance < 0.5:
		current_state = State.IDLE
		velocity = Vector3.ZERO
		return

	var target_speed = max_speed
	var brake_distance = (current_speed * current_speed) / (2 * acceleration)
	if distance < brake_distance:
		target_speed = max_speed * (distance / brake_distance)
		target_speed = clamp(target_speed, 1.0, max_speed)

	current_speed = move_toward(current_speed, target_speed, acceleration * delta)
	velocity = direction.normalized() * current_speed
	move_and_slide()
	global_position.y = 0

# ============================================================
func _handle_attacking(delta: float) -> void:
	# Validasi target masih hidup
	if not _is_enemy_valid():
		_reset_attack()
		return

	var dist = global_position.distance_to(target_enemy.global_position)

	# Kalau target lari keluar range, kejar dulu
	if dist > weapon_range * 1.5:
		# Gerak mendekati
		var dir   = (target_enemy.global_position - global_position)
		dir.y     = 0
		var brake = (current_speed * current_speed) / (2.0 * acceleration)
		var tspd  = max_speed if dist > brake else max_speed * (dist / brake)
		current_speed    = move_toward(current_speed, clamp(tspd, 1.0, max_speed), acceleration * delta)
		velocity         = dir.normalized() * current_speed
		global_position += velocity * delta
	else:
		# Dalam range — orbit ringan
		_orbit_enemy(delta)

	# Selalu hadap musuh
	var face_dir = (target_enemy.global_position - global_position).normalized()
	face_dir.y   = 0
	if face_dir.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(face_dir.x, face_dir.z), rotation_speed * delta)

	# Tembak kalau dalam range
	if dist <= weapon_range:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_timer = 1.0 / fire_rate
			_shoot()

	_update_weapon_laser(dist <= weapon_range)

func _orbit_enemy(delta: float) -> void:
	var to_enemy = target_enemy.global_position - global_position
	to_enemy.y   = 0
	var perp     = to_enemy.cross(Vector3.UP).normalized()
	var orbit_dir = (perp + to_enemy.normalized() * 0.2).normalized()
	var orbit_spd = max_speed * 0.5
	current_speed    = move_toward(current_speed, orbit_spd, acceleration * delta)
	velocity         = orbit_dir * current_speed
	global_position += velocity * delta

func _shoot() -> void:
	if not _is_enemy_valid():
		return
	var enemy_cs: Node = target_enemy.get_node_or_null("CombatSystem")
	if enemy_cs and enemy_cs.has_method("take_damage"):
		enemy_cs.take_damage(weapon_damage, self)
		print("[PlayerShip] HIT %s for %.0f | %s" % [
			target_enemy.name, weapon_damage, enemy_cs.get_summary()
		])

func _is_enemy_valid() -> bool:
	if not target_enemy or not is_instance_valid(target_enemy):
		return false
	var cs = target_enemy.get_node_or_null("CombatSystem")
	if cs and not cs.is_alive:
		return false
	return true

func _reset_attack() -> void:
	target_enemy  = null
	current_state = State.IDLE
	if _weapon_laser:
		_weapon_laser.visible = false
	emit_signal("enemy_lost")
	print("[PlayerShip] Target lost / destroyed")

# ============================================================
func _decelerate(delta: float) -> void:
	if current_speed > 0:
		current_speed    = move_toward(current_speed, 0.0, acceleration * 2 * delta)
		velocity         = velocity.normalized() * current_speed
		global_position += velocity * delta

func _handle_rotation(delta: float) -> void:
	if velocity.length() < 0.1:
		return
	var target_rotation = atan2(velocity.x, velocity.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)

# ============================================================
func _handle_mining(delta: float) -> void:
	if not is_instance_valid(target_asteroid) or target_asteroid.state == 2:
		current_state = State.IDLE
		return

	var dir_to_ast = (target_asteroid.global_position - global_position).normalized()
	var look_rot   = atan2(dir_to_ast.x, dir_to_ast.z)
	rotation.y     = lerp_angle(rotation.y, look_rot, rotation_speed * delta)

	if not _laser_mesh:
		return

	_laser_mesh.visible = true
	var ast_pos = target_asteroid.global_position
	var dist    = global_position.distance_to(ast_pos)

	_laser_mesh.global_position = global_position.lerp(ast_pos, 0.5)
	_laser_mesh.scale = Vector3.ONE
	_laser_mesh.look_at(ast_pos, Vector3.UP)
	_laser_mesh.rotate_object_local(Vector3.RIGHT, PI / 2)

	var time_sec = Time.get_ticks_msec() / 1000.0
	var pulse    = (sin(time_sec * 30.0) * 0.3) + 0.8
	_laser_mesh.scale = Vector3(pulse, dist, pulse)

	var extracted = target_asteroid.mine(MINING_YIELD * delta)
	if extracted > 0 and _cargo_sys != null and _cargo_sys.has_method("add_ore"):
		_cargo_sys.add_ore(target_asteroid.ore_type, extracted)

func _hide_lasers() -> void:
	if _laser_mesh:  _laser_mesh.visible  = false
	if _weapon_laser: _weapon_laser.visible = false

# ============================================================
# LASER VISUALS
# ============================================================
func _build_mining_laser() -> void:
	_laser_mesh      = MeshInstance3D.new()
	_laser_mesh.name = "MiningLaser"

	var cyl             = CylinderMesh.new()
	cyl.top_radius      = 0.12
	cyl.bottom_radius   = 0.02
	cyl.height          = 1.0
	cyl.radial_segments = 8
	_laser_mesh.mesh    = cyl

	var mat = StandardMaterial3D.new()
	mat.albedo_color               = Color(0.1, 0.6, 1.0, 0.3)
	mat.emission_enabled           = true
	mat.emission                   = Color(0.1, 0.8, 1.0)
	mat.emission_energy_multiplier = 4.0
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode                 = BaseMaterial3D.BLEND_MODE_ADD
	_laser_mesh.material_override  = mat

	var inner         = MeshInstance3D.new()
	var inner_cyl     = CylinderMesh.new()
	inner_cyl.top_radius    = 0.04
	inner_cyl.bottom_radius = 0.01
	inner_cyl.height        = 1.0
	inner_cyl.radial_segments = 4
	inner.mesh = inner_cyl
	var im = StandardMaterial3D.new()
	im.albedo_color               = Color(1.0, 1.0, 1.0, 0.9)
	im.emission_enabled           = true
	im.emission                   = Color(0.8, 0.95, 1.0)
	im.emission_energy_multiplier = 8.0
	im.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	inner.material_override       = im
	_laser_mesh.add_child(inner)

	_laser_mesh.visible = false
	get_tree().current_scene.add_child.call_deferred(_laser_mesh)

func _build_weapon_laser() -> void:
	_weapon_laser      = MeshInstance3D.new()
	_weapon_laser.name = "WeaponLaser"

	var cyl             = CylinderMesh.new()
	cyl.top_radius      = 0.08
	cyl.bottom_radius   = 0.015
	cyl.height          = 1.0
	cyl.radial_segments = 6
	_weapon_laser.mesh  = cyl

	var mat = StandardMaterial3D.new()
	mat.albedo_color               = Color(1.0, 0.2, 0.1, 0.35)
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.1, 0.05)
	mat.emission_energy_multiplier = 5.0
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode                 = BaseMaterial3D.BLEND_MODE_ADD
	_weapon_laser.material_override = mat

	var inner       = MeshInstance3D.new()
	var ic          = CylinderMesh.new()
	ic.top_radius   = 0.025
	ic.bottom_radius = 0.005
	ic.height       = 1.0
	ic.radial_segments = 4
	inner.mesh      = ic
	var im          = StandardMaterial3D.new()
	im.albedo_color               = Color(1.0, 0.9, 0.9, 1.0)
	im.emission_enabled           = true
	im.emission                   = Color(1.0, 0.7, 0.7)
	im.emission_energy_multiplier = 8.0
	im.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	inner.material_override       = im
	_weapon_laser.add_child(inner)

	_weapon_laser.visible = false
	get_tree().current_scene.add_child.call_deferred(_weapon_laser)

func _update_weapon_laser(firing: bool) -> void:
	if not _weapon_laser or not _is_enemy_valid():
		if _weapon_laser: _weapon_laser.visible = false
		return

	# Flash efek — visible hanya 30% dari durasi fire cycle
	var flash = _fire_timer <= (1.0 / fire_rate) * 0.3
	_weapon_laser.visible = firing and flash

	if not _weapon_laser.visible:
		return

	var target_pos = target_enemy.global_position
	var dist       = global_position.distance_to(target_pos)

	_weapon_laser.global_position = global_position.lerp(target_pos, 0.5)
	_weapon_laser.scale           = Vector3.ONE
	_weapon_laser.look_at(target_pos, Vector3.UP)
	_weapon_laser.rotate_object_local(Vector3.RIGHT, PI / 2)

	var pulse = (sin(Time.get_ticks_msec() / 1000.0 * 35.0) * 0.25) + 0.85
	_weapon_laser.scale = Vector3(pulse, dist, pulse)

# ============================================================
func _update_engine_effect() -> void:
	if _engine_trail:
		_engine_trail.emitting     = current_speed > 1.0
		var amount_ratio           = current_speed / max_speed
		_engine_trail.amount_ratio = clamp(amount_ratio, 0.1, 1.0)

func set_selected(selected: bool) -> void:
	if _selection_ring:
		_selection_ring.visible = selected

func _on_destroyed(_killer) -> void:
	print("[PlayerShip] %s destroyed!" % ship_name)
	if _laser_mesh:   _laser_mesh.queue_free()
	if _weapon_laser: _weapon_laser.queue_free()
	queue_free()

func get_ship_data() -> Dictionary:
	return {
		"position":  global_position,
		"velocity":  velocity,
		"speed":     current_speed,
		"state":     State.keys()[current_state],
		"ship_name": ship_name,
	}
