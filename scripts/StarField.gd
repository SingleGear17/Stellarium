extends Node3D

# ============================================================
# StarField.gd — FIXED (Titik Cahaya Presisi)
# ============================================================

@export var far_star_count: int = 600
@export var near_star_count: int = 150
@export var field_radius: float = 800.0
@export var far_parallax: float = 0.015
@export var near_parallax: float = 0.05

# Ukuran bintang diperkecil drastis agar menjadi titik, bukan kotak
@export var far_star_size: float = 0.15 
@export var near_star_size: float = 0.35 

var _far_stars: MultiMeshInstance3D = null
var _near_stars: MultiMeshInstance3D = null
var _camera: Camera3D = null
var _last_cam_pos: Vector3 = Vector3.ZERO

# ============================================================
func _ready() -> void:
	_camera = get_node_or_null("../Camera")
	if not _camera:
		_camera = get_tree().get_first_node_in_group("main_camera")

	_far_stars  = _build_layer(far_star_count,  far_star_size,  Color(0.6, 0.7, 1.0, 0.4))
	_near_stars = _build_layer(near_star_count, near_star_size, Color(0.9, 0.85, 1.0, 0.8))

	add_child(_far_stars)
	add_child(_near_stars)

	if _camera:
		_last_cam_pos = _camera.global_position
	else:
		push_warning("[StarField] Camera not found! Parallax disabled.")

# ============================================================
func _process(_delta: float) -> void:
	if not _camera:
		return
	var cam_pos   = _camera.global_position
	var cam_delta = cam_pos - _last_cam_pos
	_last_cam_pos = cam_pos

	_far_stars.position.x  -= cam_delta.x * far_parallax
	_far_stars.position.z  -= cam_delta.z * far_parallax
	_near_stars.position.x -= cam_delta.x * near_parallax
	_near_stars.position.z -= cam_delta.z * near_parallax

# ============================================================
func _build_layer(count: int, size: float, color: Color) -> MultiMeshInstance3D:
	var mmi = MultiMeshInstance3D.new()
	var mm  = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors       = true
	mm.instance_count   = count

	var quad = QuadMesh.new()
	quad.size = Vector2(size, size)
	mm.mesh = quad

	var rng = RandomNumberGenerator.new()
	rng.randomize()

	for i in range(count):
		var x = rng.randf_range(-field_radius, field_radius)
		var z = rng.randf_range(-field_radius, field_radius)
		var y = -20.0 # Dijauhkan sedikit ke bawah agar tidak bertabrakan dengan asteroid

		var t = Transform3D()
		t.origin = Vector3(x, y, z)
		mm.set_instance_transform(i, t)

		var brightness = rng.randf_range(0.2, 1.0)
		mm.set_instance_color(i, Color(
			color.r * brightness,
			color.g * brightness,
			color.b * brightness,
			color.a * brightness # Alpha dikalikan agar kedipannya natural
		))

	mmi.multimesh = mm

	var mat = StandardMaterial3D.new()
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode             = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test              = true
	mat.render_priority            = -1
	
	# KUNCI UTAMA: Blend Mode Add membuat quad bertumpuk menjadi cahaya (glowing)
	mat.blend_mode                 = BaseMaterial3D.BLEND_MODE_ADD 
	
	mmi.material_override = mat

	return mmi
