extends Node

# ============================================================
# CargoSystem.gd — Cleaned & Godot 4 Signal Standard
# ============================================================

@export var max_capacity: float = 50.0

var cargo: Dictionary    = {}
var used_capacity: float = 0.0

signal cargo_changed(cargo: Dictionary, used: float, max_cap: float)
signal cargo_full()

# ============================================================
func _ready() -> void:
	cargo = { "silicate": 0.0, "ice": 0.0, "rare": 0.0 }

# ============================================================
func add_ore(ore_type: String, amount: float) -> float:
	var space = max_capacity - used_capacity
	if space <= 0.0:
		cargo_full.emit()
		return 0.0

	var actual = min(amount, space)
	cargo[ore_type] = cargo.get(ore_type, 0.0) + actual
	used_capacity  += actual

	cargo_changed.emit(cargo, used_capacity, max_capacity)
	if used_capacity >= max_capacity:
		cargo_full.emit()

	return actual

# ============================================================
func clear() -> void:
	cargo         = { "silicate": 0.0, "ice": 0.0, "rare": 0.0 }
	used_capacity = 0.0
	cargo_changed.emit(cargo, used_capacity, max_capacity)

# ============================================================
func get_used() -> float:     return used_capacity
func get_free() -> float:     return max_capacity - used_capacity
func is_full() -> bool:       return used_capacity >= max_capacity

func get_summary() -> String:
	var parts = []
	for ore in cargo:
		if cargo[ore] > 0.0:
			parts.append("%s:%.1f" % [ore, cargo[ore]])
	return " | ".join(parts) if parts.size() > 0 else "empty"

func dump() -> Dictionary:
	return {
		"cargo":    cargo.duplicate(),
		"used":     used_capacity,
		"capacity": max_capacity,
	}
