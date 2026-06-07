extends Node3D

# ============================================================
# World.gd — v4 PATCH
#
# Perubahan dari v3:
#   1. MODEL_SCALE — Mining turun ke Frigate range, Hauler naik
#   2. Camera adaptive — zoom based on ship class
#   3. Right-click ship/pirate → player.attack_target()
#   4. Asteroid spawn lebih besar (size_scale range naik)
#   5. PirateBot dapat bots_node reference (fix path bug)
#   6. Weapon stats di-inject ke PlayerShip dari ShipRegistry
# ============================================================

const PlayerShipScript = preload("res://scripts/ships/PlayerShip.gd")
const AsteroidScript   = preload("res://scripts/world/Asteroid.gd")
const HUDScript        = preload("res://scripts/ui/HUD.gd")
const BotMinerScript   = preload("res://scripts/bots/BotMiner.gd")
const PirateBotScript  = preload("res://scripts/bots/PirateBot.gd")
const CargoScript      = preload("res://scripts/ships/CargoSystem.gd")
const CombatScript     = preload("res://scripts/ships/CombatSystem.gd")

@onready var camera: Camera3D = $Camera

var ships_node:     Node3D    = null
var asteroids_node: Node3D    = null
var bots_node:      Node3D    = null
var pirates_node:   Node3D    = null
var ground_plane := Plane(Vector3.UP, 0.0)
var player_ship:    Node3D    = null
var hud:            CanvasLayer = null

# ============================================================
# CAMERA — adaptive per ship class
# Target camera height supaya kapal terlihat proporsional.
# Kamera orthographic SIZE ikut menyesuaikan juga.
# ============================================================
const CAMERA_CONFIG = {
	# class          height   ortho_size
	"Frigate":    [  30.0,   25.0 ],
	"Destroyer":  [  35.0,   30.0 ],
	"Cruiser":    [  45.0,   40.0 ],
	"Mining":     [  30.0,   25.0 ],   # Mining setara Frigate
	"Hauler":     [  55.0,   50.0 ],
	"Battleship": [  65.0,   60.0 ],
}
const CAMERA_DEFAULT = [ 35.0, 30.0 ]

var _cam_target_height: float = 35.0
var _cam_target_size:   float = 30.0
var _cam_lerp_speed: float    = 3.0
var camera_z_offset: float = 25.0

var _current_zoom: float = 1.0
const MIN_ZOOM: float = 0.4   # Semakin kecil = makin dekat (Zoom In)
const MAX_ZOOM: float = 2.0   # Semakin besar = makin jauh (Zoom Out)

const ASTEROID_COUNT = 30
const BELT_INNER_R   = 80.0
const BELT_OUTER_R   = 250.0
const ORE_DISTRIBUTION = [
	["silicate", 0.60],
	["ice",      0.30],
	["rare",     0.10],
]
const BOT_COUNT    = 3
const BOT_SHIP_ID  = "advent"
const PIRATE_COUNT = 2
const STATION_POS  = Vector3.ZERO

# ============================================================
# SCALE TABLE — v4
#
# ATURAN BARU:
#   Mining (advent/venture) → turun drastis, setara Frigate/Destroyer
#   Hauler (train) → naik, sedikit di bawah Battleship
#   Advent/venture dulu 3.0 → terlalu raksasa
#
# Semua masih estimasi — fine-tune setelah F5 lihat hasilnya.
# ============================================================
const MODEL_SCALE = {
	# Frigate (Player)
	"astero":    0.01,
	"condor":    0.01,
	"genesis":   0.01,
	
	# --- PIRATES (Dinaikkan 2-3x lipat biar garang) ---
	"slasher":   1.0, 
	"stinger":   0.2, 
	
	# Destroyer & Cruiser
	"fury":      0.012,
	"raptor":    0.012,
	"enforcer":  0.015,
	"zephyr":    0.015,
	
	# Hauler
	"train":     0.035,
	
	# --- BOT MINER (Dinaikkan drastis biar kelihatan nambang) ---
	"advent":    1.0,  # Dulu 0.006, sekarang 0.15!
	"venture":   1.0,
	
	# Battleship
	"andromeda": 0.025,
	"valkyrie":  0.025,
}

# ============================================================
func _ready() -> void:
	ships_node     = Node3D.new(); ships_node.name = "Ships";         add_child(ships_node)
	asteroids_node = Node3D.new(); asteroids_node.name = "Asteroids"; add_child(asteroids_node)
	bots_node      = Node3D.new(); bots_node.name = "Bots";           add_child(bots_node)
	pirates_node   = Node3D.new(); pirates_node.name = "Pirates";     add_child(pirates_node)

	camera.add_to_group("main_camera")

	_spawn_player_ship(Vector3.ZERO)
	_setup_camera_for_ship()
	_spawn_asteroid_belt()
	_spawn_bot_miners()
	_spawn_pirate_bots()
	_spawn_hud()

# ============================================================
func _process(delta: float) -> void:
	if is_instance_valid(player_ship):
		# Terapkan Z-offset agar kapal naik ke tengah layar
		var target_pos = Vector3(
			player_ship.global_position.x,
			_cam_target_height,
			player_ship.global_position.z + camera_z_offset 
		)
		camera.global_position = camera.global_position.lerp(target_pos, _cam_lerp_speed * delta)

		# Terapkan ukuran kamera dikali level zoom dari mouse scroll
		var final_cam_size = _cam_target_size * _current_zoom
		camera.size = lerp(camera.size, final_cam_size, _cam_lerp_speed * delta)

# ============================================================
func _setup_camera_for_ship() -> void:
	if not player_ship:
		return
	var ship_class = ShipRegistry.get_ship(player_ship.ship_name).get("class", "Frigate")
	var cfg        = CAMERA_CONFIG.get(ship_class, CAMERA_DEFAULT)
	_cam_target_height = cfg[0]
	_cam_target_size   = cfg[1]
	# Set langsung di awal biar ga ada pop
	camera.global_position = player_ship.global_position + Vector3(0, _cam_target_height, 0)
	camera.size            = _cam_target_size
	print("[World] Camera → class:%s height:%.0f size:%.0f" % [ship_class, _cam_target_height, _cam_target_size])

# ============================================================
func _spawn_hud() -> void:
	hud      = HUDScript.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(player_ship)

# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Panggil fungsi klik kiri
			_handle_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Panggil fungsi klik kanan
			_handle_right_click(event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Zoom In
			_current_zoom = clamp(_current_zoom - 0.1, MIN_ZOOM, MAX_ZOOM)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Zoom Out
			_current_zoom = clamp(_current_zoom + 0.1, MIN_ZOOM, MAX_ZOOM)

func _handle_left_click(screen_pos: Vector2) -> void:
	if not player_ship:
		return

	# 1. Cek klik ship musuh (Pakai fungsi matematika bawaanmu)
	var hit_enemy = _raycast_enemy(screen_pos)
	if hit_enemy:
		player_ship.attack_target(hit_enemy)
		return

	# 2. Cek klik asteroid (Pakai fungsi matematika bawaanmu)
	var hit_asteroid = _raycast_asteroid(screen_pos)
	if hit_asteroid:
		player_ship.move_to_mine(hit_asteroid)
		return

	# Setup variabel raycast
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir    = camera.project_ray_normal(screen_pos)
	var ray_end    = ray_origin + ray_dir * 1000.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = true 
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var hit_obj = result.collider
		
		# Cek kalau yang diklik musuh (Pirate)
		if hit_obj.name.begins_with("PirateBot"):
			var cs = hit_obj.get_node_or_null("CombatSystem")
			if cs and cs.is_alive:
				player_ship.attack_target(hit_obj)
				return
				
		# Cek kalau yang diklik Asteroid
		if hit_obj.has_method("mine"):
			player_ship.move_to_mine(hit_obj)
			return
			
func _handle_right_click(screen_pos: Vector2) -> void:
	if not player_ship:
		return

	# Sisa logic buat jalan kita taruh di sini
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir    = camera.project_ray_normal(screen_pos)
	var intersection = ground_plane.intersects_ray(ray_origin, ray_dir)
	
	if intersection != null:
		player_ship.move_to(intersection)
# ============================================================
# Raycast ke semua enemy (pirates dan bot miners sebagai target latihan)
# ============================================================
func _raycast_enemy(screen_pos: Vector2) -> Node3D:
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir    = camera.project_ray_normal(screen_pos)
	var closest: Node3D  = null
	var closest_dist: float = INF
	const THRESHOLD = 6.0

	var check_nodes = [pirates_node]
	# Uncomment baris bawah kalau mau bisa serang bot miner juga:
	# check_nodes.append(bots_node)

	for node_group in check_nodes:
		if not node_group:
			continue
		for ship in node_group.get_children():
			# Cek apakah masih hidup
			var cs = ship.get_node_or_null("CombatSystem")
			if cs and not cs.is_alive:
				continue
			var ship_pos   = ship.global_position
			var proj       = (ship_pos - ray_origin).dot(ray_dir)
			var closest_pt = ray_origin + ray_dir * proj
			var dist_ray   = ship_pos.distance_to(closest_pt)
			if dist_ray < THRESHOLD and proj > 0 and dist_ray < closest_dist:
				closest_dist = dist_ray
				closest      = ship

	return closest

# ============================================================
func _raycast_asteroid(screen_pos: Vector2) -> Node3D:
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir    = camera.project_ray_normal(screen_pos)
	var closest_asteroid: Node3D = null
	var closest_dist: float      = INF

	for asteroid in asteroids_node.get_children():
		if not asteroid.has_method("mine") or asteroid.state == 2:
			continue
		var ast_pos       = asteroid.global_position
		var proj          = (ast_pos - ray_origin).dot(ray_dir)
		var closest_point = ray_origin + ray_dir * proj
		var dist_to_ray   = ast_pos.distance_to(closest_point)
		var threshold     = 5.0 * asteroid.size_scale
		if dist_to_ray < threshold and proj > 0 and dist_to_ray < closest_dist:
			closest_dist     = dist_to_ray
			closest_asteroid = asteroid

	return closest_asteroid

# ============================================================
func _spawn_player_ship(spawn_pos: Vector3) -> void:
	var starter_id = ShipRegistry.get_starter_ship()
	var ship_data  = ShipRegistry.get_ship(starter_id)
	if ship_data.is_empty():
		push_error("[World] Starter ship not found!")
		return

	var root            = PlayerShipScript.new()
	root.name           = "PlayerShip_" + starter_id
	root.max_speed      = ship_data["max_speed"]
	root.acceleration   = ship_data["acceleration"]
	root.rotation_speed = ship_data["rotation_speed"]
	root.ship_name      = starter_id

	# Weapon stats — Frigate astero defaults
	# TODO: nanti ambil dari ShipRegistry kalau sudah ada weapon_damage field
	root.weapon_damage  = 20.0
	root.weapon_range   = 40.0
	root.fire_rate      = 1.5

	var cargo = CargoScript.new()
	cargo.name = "CargoSystem"
	cargo.set("max_capacity", ship_data["cargo_m3"])
	root.add_child(cargo)

	var combat = CombatScript.new()
	combat.name = "CombatSystem"
	combat.set("max_shield", ship_data["hp_shield"])
	combat.set("max_armor",  ship_data["hp_armor"])
	root.add_child(combat)

	_attach_model(root, ship_data["model"], MODEL_SCALE.get(starter_id, 0.005))

	# Selection ring
	var ring     = MeshInstance3D.new()
	ring.name    = "SelectionRing"
	var torus    = TorusMesh.new()
	torus.inner_radius = 2.2
	torus.outer_radius = 2.5
	ring.mesh    = torus
	var ring_mat = StandardMaterial3D.new()
	ring_mat.albedo_color               = Color(0.4, 0.9, 1.0, 0.8)
	ring_mat.emission_enabled           = true
	ring_mat.emission                   = Color(0.2, 0.6, 0.8)
	ring_mat.emission_energy_multiplier = 1.5
	ring.material_override = ring_mat
	ring.visible = false
	root.add_child(ring)

	ships_node.add_child(root)
	root.global_position = spawn_pos
	player_ship = root
	print("[World] Player ship spawned: %s scale=%.4f" % [starter_id, MODEL_SCALE.get(starter_id, 0.005)])

# ============================================================
func _attach_model(parent: Node3D, model_path: String, model_scale: float) -> void:
	if ResourceLoader.exists(model_path):
		var model_instance  = load(model_path).instantiate()
		model_instance.name = "Mesh"
		model_instance.scale = Vector3.ONE * model_scale
		parent.add_child(model_instance)
		print("[World] Model OK: %s @ scale %.4f" % [model_path.get_file(), model_scale])
	else:
		push_warning("[World] Model missing: " + model_path)
		var mesh_inst        = MeshInstance3D.new()
		mesh_inst.name       = "Mesh"
		var prism            = PrismMesh.new()
		prism.size           = Vector3(1.5, 0.4, 3.0)
		var mat              = StandardMaterial3D.new()
		mat.albedo_color     = Color(0.4, 0.6, 0.7)
		mat.metallic         = 0.8
		mat.roughness        = 0.3
		mesh_inst.mesh       = prism
		mesh_inst.material_override = mat
		parent.add_child(mesh_inst)

# ============================================================
func _spawn_bot_miners() -> void:
	var bot_data = ShipRegistry.get_ship(BOT_SHIP_ID)
	var rng      = RandomNumberGenerator.new()
	rng.randomize()

	var bot_models = [
		{"id": "advent",  "path": "res://assets/models/ships/Mining/advent/advent.glb"},
		{"id": "venture", "path": "res://assets/models/ships/Mining/venture/venture.glb"},
	]

	for i in range(BOT_COUNT):
		var bot          = BotMinerScript.new()
		bot.name         = "BotMiner_%02d" % i
		bot.bot_name     = "Miner-%02d" % i
		bot.max_speed    = 10.0
		bot.acceleration = 4.0
		bot.mining_range = 12.0
		bot.mining_yield = 3.0
		bot.station_position = STATION_POS
		bots_node.add_child(bot)

		var angle           = (TAU / BOT_COUNT) * i
		bot.global_position = STATION_POS + Vector3(cos(angle) * 15.0, 0, sin(angle) * 15.0)

		var cargo = CargoScript.new()
		cargo.name = "CargoSystem"
		cargo.set("max_capacity", bot_data.get("cargo_m3", 200.0) if not bot_data.is_empty() else 200.0)
		bot.add_child(cargo)

		var chosen = bot_models[rng.randi() % bot_models.size()]
		var sc     = MODEL_SCALE.get(chosen["id"], 0.006)

		if ResourceLoader.exists(chosen["path"]):
			var mdl   = load(chosen["path"]).instantiate()
			mdl.name  = "Mesh"
			mdl.scale = Vector3.ONE * sc

			# Venture: model orientasinya -90° di Y agar maju ke depan
			# laser_offset = ZERO → world-space laser origin (tidak terpengaruh rotasi model)
			if chosen["id"] == "venture":
				mdl.rotation_degrees.y = -90
				bot.laser_offset       = Vector3.ZERO
			else:
				bot.laser_offset = Vector3(0.0, 0.8, 0.0)

			bot.add_child(mdl)
		else:
			_attach_model(bot, chosen["path"], sc)

		bot.set_asteroids_node(asteroids_node)

	print("[World] %d bot miners spawned" % BOT_COUNT)

# ============================================================
func _spawn_pirate_bots() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	var pirate_models = [
		{"id": "slasher", "path": "res://assets/models/ships/Frigate/slasher/slasher.glb"},
		{"id": "stinger", "path": "res://assets/models/ships/Destroyer/stinger/stinger.glb"},
	]

	for i in range(PIRATE_COUNT):
		var cfg    = pirate_models[i % pirate_models.size()]
		var pirate = PirateBotScript.new()
		pirate.name         = "PirateBot_%02d" % i
		pirate.bot_name     = "Pirate-%02d" % i
		pirate.max_speed    = 22.0
		pirate.attack_range = 30.0
		pirate.weapon_damage = 25.0
		pirate.fire_rate    = 1.5
		pirates_node.add_child(pirate)

		var angle              = rng.randf() * TAU
		var dist               = rng.randf_range(180.0, 280.0)
		pirate.global_position = Vector3(cos(angle) * dist, 0, sin(angle) * dist)

		var combat = CombatScript.new()
		combat.name = "CombatSystem"
		combat.set("max_shield", 180.0)
		combat.set("max_armor",  150.0)
		pirate.add_child(combat)

		var cargo = CargoScript.new()
		cargo.name = "CargoSystem"
		cargo.set("max_capacity", 100.0)
		pirate.add_child(cargo)

		_attach_model(pirate, cfg["path"], MODEL_SCALE.get(cfg["id"], 0.005))

		# FIX v4: pass kedua node agar PirateBot bisa scan semua target
		pirate.set_ships_node(ships_node)
		pirate.set_bots_node(bots_node)   # ← FIX: dulu pakai path "../../Bots" yang rawan salah

	print("[World] %d pirate bots spawned" % PIRATE_COUNT)

# ============================================================
func _spawn_asteroid_belt() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	for i in range(ASTEROID_COUNT):
		var asteroid          = AsteroidScript.new()
		asteroid.name         = "Asteroid_%d" % i
		asteroids_node.add_child(asteroid)
		var angle             = rng.randf() * TAU
		var dist              = rng.randf_range(BELT_INNER_R, BELT_OUTER_R)
		asteroid.ore_type     = _pick_ore_type(rng)
		asteroid.ore_amount   = rng.randf_range(100.0, 400.0)    # lebih banyak ore
		# size_scale naik → asteroid lebih besar dan masuk akal untuk di-mine
		asteroid.size_scale   = rng.randf_range(0.8, 1.5)
		asteroid.respawn_time = 120.0
		asteroid.global_position = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

func _pick_ore_type(rng: RandomNumberGenerator) -> String:
	var roll = rng.randf()
	var cum  = 0.0
	for entry in ORE_DISTRIBUTION:
		cum += entry[1]
		if roll <= cum:
			return entry[0]
	return "silicate"
