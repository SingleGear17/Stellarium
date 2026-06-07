extends StaticBody3D

# ============================================================
# Asteroid.gd — v4 PATCH
#
# Perubahan dari v3:
#   1. Extend StaticBody3D (bukan Node3D) → bisa collision fisik
#   2. CollisionShape3D otomatis dibuat → kapal tidak bisa nembus
#   3. MASTER_SCALE naik → asteroid lebih gede, masuk akal di-mine
#   4. Micro-damage saat kapal nabrak → dihandle via signal area
#      Note: untuk micro-damage, tambahkan Area3D terpisah di ship
#      Asteroid sendiri handle via _on_body_entered()
#   5. size_scale range sudah dinaikkan dari World.gd (2.0–5.0)
#
# CATATAN SCENE TREE:
#   Asteroid sekarang butuh collision shape agar StaticBody3D bekerja.
#   Shape dibuat otomatis di _build_mesh() → SphereShape3D.
# ============================================================

enum State { IDLE, BEING_MINED, DEPLETED }

@export var ore_type: String      = "silicate"
@export var ore_amount: float     = 100.0
@export var respawn_time: float   = 120.0
@export var size_scale: float     = 1.0

# MASTER_SCALE naik dari 0.02 → 0.08
# Dikalikan size_scale (2.0–5.0) dari World, hasilnya asteroid cukup besar
const MASTER_SCALE = 0.08

# Damage per detik kalau kapal nabrak asteroid (micro-damage)
const COLLISION_DPS = 5.0

var state: State             = State.IDLE
var ore_remaining: float     = 0.0
var _respawn_timer: float    = 0.0
var _model_instance: Node3D  = null
var _collision_shape: CollisionShape3D = null
var _current_radius: float   = 3.0   # untuk lookup dari luar (mining range dll)
var _damage_area: Area3D = null

signal depleted(asteroid: Node3D)
signal respawned(asteroid: Node3D)

const ORE_MODEL_MAPPING = {
	"silicate": [
		"res://assets/models/asteroids/1/1.gltf",
		"res://assets/models/asteroids/2/2.glb",
		"res://assets/models/asteroids/3/3.glb",
		"res://assets/models/asteroids/mineral/mineral.glb"
	],
	"ice": [
		"res://assets/models/asteroids/3/3.glb"
	],
	"rare": [
		"res://assets/models/asteroids/metal/metal.glb",
		"res://assets/models/asteroids/moonstone/moonstone.glb"
	]
}

# ============================================================
func _ready() -> void:
	ore_remaining = ore_amount
	_build_collision_shape()
	_build_mesh()
	print("[Asteroid] type:%s pos:%s scale:%.2f" % [ore_type, str(global_position), size_scale])

# ============================================================
func _process(delta: float) -> void:
	if state == State.DEPLETED:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_do_respawn()

# ============================================================
func _build_collision_shape() -> void:
	if _collision_shape: _collision_shape.queue_free()
	if _damage_area: _damage_area.queue_free()
	
	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "SolidShape"
	var sphere = SphereShape3D.new()

	_current_radius = size_scale * MASTER_SCALE * 120.0
	sphere.radius = _current_radius
	_collision_shape.shape = sphere
	add_child(_collision_shape)

	_damage_area = Area3D.new()
	var damage_col = CollisionShape3D.new()
	var damage_sphere = SphereShape3D.new()
	damage_sphere.radius = _current_radius + 0.5 # Sedikit lebih besar dari fisik
	damage_col.shape = damage_sphere
	_damage_area.add_child(damage_col)
	add_child(_damage_area)
	
	_damage_area.body_entered.connect(_on_body_entered)
	
# ============================================================
func _build_mesh() -> void:
	if _model_instance:
		_model_instance.queue_free()

	var model_pool  = ORE_MODEL_MAPPING.get(ore_type, ORE_MODEL_MAPPING["silicate"])
	var rng         = RandomNumberGenerator.new()
	rng.randomize()
	var chosen_path = model_pool[rng.randi() % model_pool.size()]

	if ResourceLoader.exists(chosen_path):
		var model_resource  = load(chosen_path)
		_model_instance     = model_resource.instantiate()
		_model_instance.name = "Mesh"
		add_child(_model_instance)

		var final_scale     = size_scale * rng.randf_range(0.9, 1.2)
		_model_instance.scale = Vector3(final_scale, final_scale, final_scale) * MASTER_SCALE

		if ore_type == "ice":
			var ice_mat         = StandardMaterial3D.new()
			ice_mat.albedo_color = Color(0.60, 0.82, 1.0, 0.9)
			ice_mat.roughness   = 0.4
			ice_mat.metallic    = 0.2
			_apply_material_override_recursive(_model_instance, ice_mat)
	else:
		push_warning("[Asteroid] Model missing: " + chosen_path + " — pakai placeholder")
		_build_placeholder_mesh()

	rotation = Vector3(
		rng.randf() * TAU,
		rng.randf() * TAU,
		rng.randf() * TAU
	)

# ============================================================
func _apply_material_override_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
	for child in node.get_children():
		_apply_material_override_recursive(child, mat)

func _build_placeholder_mesh() -> void:
	_model_instance      = MeshInstance3D.new()
	_model_instance.name = "Mesh"
	var sphere           = SphereMesh.new()
	sphere.radius        = 2.0 * size_scale
	sphere.height        = 3.5 * size_scale
	sphere.radial_segments = 7
	sphere.rings         = 5
	_model_instance.mesh = sphere

	var mat          = StandardMaterial3D.new()
	match ore_type:
		"ice":   mat.albedo_color = Color(0.6, 0.82, 1.0)
		"rare":  mat.albedo_color = Color(0.7, 1.0, 0.5)
		_:       mat.albedo_color = Color(0.55, 0.50, 0.45)
	mat.roughness    = 0.8
	_model_instance.material_override = mat
	add_child(_model_instance)

# ============================================================
# MICRO-DAMAGE — dipanggil StaticBody3D saat ada body masuk collision
# ============================================================
func _on_body_entered(body: Node) -> void:
	if state == State.DEPLETED:
		return
	# Cek apakah body yang nabrak punya CombatSystem
	var cs = body.get_node_or_null("CombatSystem")
	if cs and cs.has_method("take_damage"):
		# Damage satu kali saat pertama nabrak (bukan per frame)
		# Untuk continuous damage, perlu Area3D terpisah — ini adalah "bump damage"
		var impact_dmg = COLLISION_DPS * 0.5   # 2.5 damage per benturan
		cs.take_damage(impact_dmg, self)
		print("[Asteroid] Collision! %s hit for %.1f dmg" % [body.name, impact_dmg])

# ============================================================
func mine(amount: float) -> float:
	if state != State.IDLE:
		return 0.0

	state         = State.BEING_MINED
	var extracted = min(amount, ore_remaining)
	ore_remaining -= extracted

	# Animasi menyusut
	var ratio = ore_remaining / ore_amount
	if _model_instance:
		var shrink = clamp(ratio, 0.25, 1.0)
		_model_instance.scale = Vector3.ONE * (shrink * size_scale * MASTER_SCALE)
		# Update collision shape mengikuti ukuran saat ini
		if _collision_shape and _collision_shape.shape is SphereShape3D:
			_collision_shape.shape.radius = _current_radius * shrink

	if ore_remaining <= 0.0:
		_start_depleted()
	else:
		state = State.IDLE

	return extracted

# ============================================================
func _start_depleted() -> void:
	state          = State.DEPLETED
	_respawn_timer = respawn_time
	# Disable collision saat depleted
	if _collision_shape:
		_collision_shape.disabled = true
	if _model_instance:
		_model_instance.visible = false
	emit_signal("depleted", self)
	print("[Asteroid] Depleted — respawn in %ds" % respawn_time)

func _do_respawn() -> void:
	ore_remaining = ore_amount
	state         = State.IDLE
	if _collision_shape:
		_collision_shape.disabled = false
		if _collision_shape.shape is SphereShape3D:
			_collision_shape.shape.radius = _current_radius
	if _model_instance:
		_model_instance.visible = true
	_build_mesh()
	emit_signal("respawned", self)

# ============================================================
func get_info() -> Dictionary:
	return {
		"ore_type":      ore_type,
		"ore_remaining": ore_remaining,
		"ore_total":     ore_amount,
		"state":         State.keys()[state],
		"position":      global_position,
	}
