extends Node

# ============================================================
# CombatSystem.gd
# Attach sebagai child node bernama "CombatSystem" di tiap kapal
# (PlayerShip, BotMiner, PirateBot)
#
# Mechanic:
#   - Damage masuk ke shield dulu, limpahan ke armor
#   - Shield regen otomatis setelah tidak kena damage X detik
#   - Armor TIDAK regen (harus repair di station)
#   - HP 0 → emit signal "destroyed"
# ============================================================

@export var max_shield: float = 150.0
@export var max_armor: float  = 100.0
@export var shield_regen_rate: float  = 8.0    # per detik
@export var shield_regen_delay: float = 5.0    # detik tanpa damage sebelum regen

var hp_shield: float = 0.0
var hp_armor:  float = 0.0
var is_alive:  bool  = true

var _regen_timer: float = 0.0   # countdown sebelum regen aktif

signal hp_changed(hp_shield: float, hp_armor: float, max_shield: float, max_armor: float)
signal shield_broken()
signal destroyed(killer_node: Node)

# ============================================================
func _ready() -> void:
	hp_shield = max_shield
	hp_armor  = max_armor

# ============================================================
func _process(delta: float) -> void:
	if not is_alive:
		return
	_handle_shield_regen(delta)

# ============================================================
func take_damage(amount: float, attacker: Node = null) -> void:
	if not is_alive:
		return

	_regen_timer = shield_regen_delay   # reset timer regen

	# Damage ke shield dulu
	var shield_absorbed = min(amount, hp_shield)
	hp_shield -= shield_absorbed
	var overflow      = amount - shield_absorbed

	if hp_shield <= 0.0 and shield_absorbed > 0.0:
		emit_signal("shield_broken")

	# Sisa damage ke armor
	if overflow > 0.0:
		hp_armor -= overflow
		hp_armor  = max(hp_armor, 0.0)

	emit_signal("hp_changed", hp_shield, hp_armor, max_shield, max_armor)

	if hp_armor <= 0.0:
		_die(attacker)

# ============================================================
func _handle_shield_regen(delta: float) -> void:
	if hp_shield >= max_shield:
		return
	if _regen_timer > 0.0:
		_regen_timer -= delta
		return
	hp_shield = min(hp_shield + shield_regen_rate * delta, max_shield)
	emit_signal("hp_changed", hp_shield, hp_armor, max_shield, max_armor)

# ============================================================
func _die(killer: Node) -> void:
	is_alive  = false
	hp_shield = 0.0
	hp_armor  = 0.0
	emit_signal("hp_changed", 0.0, 0.0, max_shield, max_armor)
	emit_signal("destroyed", killer)
	print("[CombatSystem] %s destroyed by %s" % [
		get_parent().name,
		killer.name if killer else "unknown"
	])

# ============================================================
func repair_armor(amount: float) -> void:
	hp_armor = min(hp_armor + amount, max_armor)
	emit_signal("hp_changed", hp_shield, hp_armor, max_shield, max_armor)

func get_hp_ratio_shield() -> float:
	return hp_shield / max_shield if max_shield > 0 else 0.0

func get_hp_ratio_armor() -> float:
	return hp_armor / max_armor if max_armor > 0 else 0.0

func get_summary() -> String:
	return "SH:%.0f/%.0f AR:%.0f/%.0f" % [hp_shield, max_shield, hp_armor, max_armor]
