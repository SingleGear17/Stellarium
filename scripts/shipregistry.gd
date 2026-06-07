extends Node

# ============================================================
# ShipRegistry.gd
# Stellarium: Echoes of Monolith
# Autoload singleton — akses dari mana saja via ShipRegistry.xxx
# ============================================================

const SHIP_DATA = {

	# ── FRIGATE ─────────────────────────────────────────────
	"astero": {
		"class": "Frigate",
		"model": "res://assets/models/ships/Frigate/astero/astero.gltf",
		"max_speed": 28.0,
		"acceleration": 10.0,
		"rotation_speed": 4.0,
		"hp_shield": 150.0,
		"hp_armor": 100.0,
		"cargo_m3": 50.0,
		"base_price_mlc": 0,
		"role": "combat",
		"description": "Nimble combat frigate. Default starter ship."
	},
	"condor": {
		"class": "Frigate",
		"model": "res://assets/models/ships/Frigate/condor/condor.gltf",
		"max_speed": 32.0,
		"acceleration": 12.0,
		"rotation_speed": 5.0,
		"hp_shield": 120.0,
		"hp_armor": 80.0,
		"cargo_m3": 30.0,
		"base_price_mlc": 800,
		"role": "scout",
		"description": "Fast scout frigate. Low tank, high mobility."
	},
	"genesis": {
		"class": "Frigate",
		"model": "res://assets/models/ships/Frigate/genesis/genesis.gltf",
		"max_speed": 24.0,
		"acceleration": 9.0,
		"rotation_speed": 3.5,
		"hp_shield": 200.0,
		"hp_armor": 150.0,
		"cargo_m3": 80.0,
		"base_price_mlc": 1200,
		"role": "combat",
		"description": "Heavy frigate. Tankier but slower."
	},
	"slasher": {
		"class": "Frigate",
		"model": "res://assets/models/ships/Frigate/slasher/slasher.glb",
		"max_speed": 35.0,
		"acceleration": 14.0,
		"rotation_speed": 5.5,
		"hp_shield": 100.0,
		"hp_armor": 70.0,
		"cargo_m3": 20.0,
		"base_price_mlc": 1500,
		"role": "interceptor",
		"description": "Pure speed. Catches anything, tanks nothing."
	},

	# ── CRUISER ─────────────────────────────────────────────
	"enforcer": {
		"class": "Cruiser",
		"model": "res://assets/models/ships/Cruiser/enforcer/enforcer.gltf",
		"max_speed": 18.0,
		"acceleration": 6.0,
		"rotation_speed": 2.5,
		"hp_shield": 500.0,
		"hp_armor": 400.0,
		"cargo_m3": 200.0,
		"base_price_mlc": 8000,
		"role": "combat",
		"description": "Heavy combat cruiser. Fleet backbone."
	},
	"zephyr": {
		"class": "Cruiser",
		"model": "res://assets/models/ships/Cruiser/zephyr/zephyr.gltf",
		"max_speed": 22.0,
		"acceleration": 7.0,
		"rotation_speed": 3.0,
		"hp_shield": 380.0,
		"hp_armor": 300.0,
		"cargo_m3": 350.0,
		"base_price_mlc": 7000,
		"role": "combat",
		"description": "Balanced cruiser. Good all-rounder."
	},

	# ── DESTROYER ───────────────────────────────────────────
	"fury": {
		"class": "Destroyer",
		"model": "res://assets/models/ships/Destroyer/fury/fury.glb",
		"max_speed": 22.0,
		"acceleration": 8.0,
		"rotation_speed": 3.5,
		"hp_shield": 280.0,
		"hp_armor": 220.0,
		"cargo_m3": 100.0,
		"base_price_mlc": 3500,
		"role": "combat",
		"description": "Anti-frigate specialist. High tracking guns."
	},
	"raptor": {
		"class": "Destroyer",
		"model": "res://assets/models/ships/Destroyer/raptor/raptor.gltf",
		"max_speed": 20.0,
		"acceleration": 7.5,
		"rotation_speed": 3.2,
		"hp_shield": 320.0,
		"hp_armor": 260.0,
		"cargo_m3": 120.0,
		"base_price_mlc": 4000,
		"role": "combat",
		"description": "Fleet destroyer. Balanced firepower."
	},
	"stinger": {
		"class": "Destroyer",
		"model": "res://assets/models/ships/Destroyer/stinger/stinger.glb",
		"max_speed": 25.0,
		"acceleration": 9.0,
		"rotation_speed": 4.0,
		"hp_shield": 240.0,
		"hp_armor": 180.0,
		"cargo_m3": 80.0,
		"base_price_mlc": 3800,
		"role": "interceptor",
		"description": "Fast destroyer. Hunts down frigates."
	},

	# ── HAULER ──────────────────────────────────────────────
	"train": {
		"class": "Hauler",
		"model": "res://assets/models/ships/Hauler/train/train.gltf",
		"max_speed": 12.0,
		"acceleration": 3.0,
		"rotation_speed": 1.5,
		"hp_shield": 300.0,
		"hp_armor": 500.0,
		"cargo_m3": 2000.0,
		"base_price_mlc": 12000,
		"role": "logistics",
		"description": "Massive cargo hauler. Slow, high value target."
	},

	# ── MINING ──────────────────────────────────────────────
	"advent": {
		"class": "Mining",
		"model": "res://assets/models/ships/Mining/advent/advent.glb",
		"max_speed": 10.0,
		"acceleration": 3.0,
		"rotation_speed": 1.8,
		"hp_shield": 200.0,
		"hp_armor": 350.0,
		"cargo_m3": 800.0,
		"base_price_mlc": 6000,
		"role": "mining",
		"mining_yield": 1.0,
		"description": "Standard mining barge."
	},
	"venture": {
		"class": "Mining",
		"model": "res://assets/models/ships/Mining/venture/venture.glb",
		"max_speed": 14.0,
		"acceleration": 4.5,
		"rotation_speed": 2.5,
		"hp_shield": 150.0,
		"hp_armor": 200.0,
		"cargo_m3": 400.0,
		"base_price_mlc": 3500,
		"role": "mining",
		"mining_yield": 0.7,
		"description": "Nimble mining frigate. Lower yield but can flee."
	},

	# ── BATTLESHIP (Phase 2) ─────────────────────────────────
	"andromeda": {
		"class": "Battleship",
		"model": "res://assets/models/ships/Battleship/andromeda/andromeda.gltf",
		"max_speed": 10.0,
		"acceleration": 2.5,
		"rotation_speed": 1.0,
		"hp_shield": 1200.0,
		"hp_armor": 1000.0,
		"cargo_m3": 500.0,
		"base_price_mlc": 50000,
		"role": "combat",
		"description": "Apex combat platform. Fleet killer."
	},
	"valkyrie": {
		"class": "Battleship",
		"model": "res://assets/models/ships/Battleship/valkyrie/valkyrie.gltf",
		"max_speed": 8.0,
		"acceleration": 2.0,
		"rotation_speed": 0.8,
		"hp_shield": 1500.0,
		"hp_armor": 1200.0,
		"cargo_m3": 400.0,
		"base_price_mlc": 65000,
		"role": "combat",
		"description": "Siege battleship. Slow but devastating."
	},
}

# ============================================================
func get_ship(ship_id: String) -> Dictionary:
	if SHIP_DATA.has(ship_id):
		return SHIP_DATA[ship_id]
	push_error("[ShipRegistry] Ship not found: " + ship_id)
	return {}

func get_ships_by_class(target_class: String) -> Array:
	var result = []
	for id in SHIP_DATA:
		if SHIP_DATA[id].get("class") == target_class:
			result.append({"id": id, "data": SHIP_DATA[id]})
	return result

func get_starter_ship() -> String:
	return "astero"

func get_model_path(ship_id: String) -> String:
	var data = get_ship(ship_id)
	if data.is_empty():
		return ""
	return data["model"]
