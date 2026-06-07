extends CanvasLayer

# ============================================================
# HUD.gd — REBOOTED: Cyber-Diagnostic Minimalist Style
# Stellarium: Echoes of Monolith
# ============================================================

var player_ship: Node3D = null
var cargo_sys: Node     = null

# Refs ke node UI (yang akan dibuat otomatis)
var _shield_bar: ProgressBar = null
var _armor_bar:  ProgressBar = null
var _cargo_bar:  ProgressBar = null

var _ore_silicate: Label = null
var _ore_ice:      Label = null
var _ore_rare:     Label = null

var _state_label: Label = null
var _coord_label: Label = null
var _cargo_title: Label = null # Menampilkan "X / Y m3"

# --- PALET WARNA MINIMALIS SCI-FI ---
const COLOR_TECH_CYAN  = Color(0.15, 0.85, 1.00) # Shield / Active State
const COLOR_TECH_AMBER = Color(1.00, 0.70, 0.20) # Armor / Moving
const COLOR_SILICATE   = Color(0.70, 0.70, 0.70) # Abu-abu Ore
const COLOR_ICE        = Color(0.60, 0.80, 1.00) # Biru Es
const COLOR_RARE       = Color(0.60, 1.00, 0.60) # Hijau Rare
const COLOR_TEXT_MAIN  = Color(0.90, 0.95, 1.00) # Putih bersih
const COLOR_TEXT_DIM   = Color(0.40, 0.50, 0.60) # Abu-abu redup (garis/label)
const COLOR_BG_ULTRA_DIM = Color(0.02, 0.03, 0.05, 0.50) # Sangat transparan

# ============================================================
func _ready() -> void:
	# Penting: Saat testing di editor, kadang HUD muncul di atas scene lain.
	# Kita set layer agar selalu di depan.
	layer = 10 
	_build_ui_responsive()

# ============================================================
func _process(_delta: float) -> void:
	if not player_ship or not is_instance_valid(player_ship):
		# Jika kapal meledak/hilang, sembunyikan UI
		visible = false
		return
	visible = true
	_update_combat()
	_update_cargo()
	_update_info()

# ============================================================
func setup(ship: Node3D) -> void:
	player_ship = ship
	cargo_sys   = ship.get_node_or_null("CargoSystem")

# ============================================================
func _update_combat() -> void:
	if not player_ship: return
	var cs = player_ship.get_node_or_null("CombatSystem")
	if cs:
		_shield_bar.value = cs.get_hp_ratio_shield() * 100.0
		_armor_bar.value  = cs.get_hp_ratio_armor()  * 100.0

func _update_cargo() -> void:
	if not cargo_sys:
		return
	var data     = cargo_sys.dump()
	var used     = data["used"]
	var capacity = data["capacity"]
	var cargo    = data["cargo"]

	var ratio = used / capacity if capacity > 0 else 0.0
	_cargo_bar.value = ratio * 100.0
	
	# Update label kargo utama
	_cargo_title.text = "STORAGE: %.1f / %.0f m³" % [used, capacity]

	# Update breakdown ore (gunakan karakter monospace biar rapi)
	_ore_silicate.text = "Si [ %.1f ]" % cargo.get("silicate", 0.0)
	_ore_ice.text      = "Ic [ %.1f ]" % cargo.get("ice", 0.0)
	_ore_rare.text     = "Ra [ %.1f ]" % cargo.get("rare", 0.0)

	# Warnai kargo bar menyesuaikan tingkat kepenuhan
	_cargo_bar.modulate = COLOR_TECH_CYAN.lerp(COLOR_TECH_AMBER, ratio)

func _update_info() -> void:
	var pos = player_ship.global_position
	# Gunakan bracket biar kelihatan diagnostik
	_coord_label.text = "LOC: [ %.0f , %.0f ]" % [pos.x, pos.z]

	var state_text = ">> STANDBY"
	var state_color = COLOR_TEXT_DIM
	
	if player_ship.has_method("get") :
		var s = player_ship.get("current_state")
		if s != null:
			match s:
				0: 
					state_text = ">> STANDBY"
					state_color = COLOR_TEXT_DIM
				1: 
					state_text = ">> MOVING"
					state_color = COLOR_TECH_AMBER
				2: 
					state_text = "⛏ MINING ACTIVE"
					state_color = COLOR_TECH_CYAN
	
			
	_state_label.text = state_text
	_state_label.modulate = state_color

func _on_hp_changed(_sh, _ar, _msh, _mar) -> void: pass
func _on_shield_broken() -> void: print("[HUD] SHIELD BROKEN!")	

# ============================================================
# --- RESPONSIF UI BUILDER (MENGGUNAKAN KONTAINER OTOMATIS) ---
# Berhenti menggunakan posisi absolut agar tidak tabrakan!
# ============================================================
func _build_ui_responsive() -> void:
	# Tambahkan VBox utama di kiri atas untuk info kapal
	_build_top_left_diagnostics()
	
	# Tambahkan VBox di kiri bawah untuk defense
	_build_bottom_left_defense()
	
	# Tambahkan VBox di kanan bawah untuk kargo (rata kanan)
	_build_bottom_right_cargo()

# ---- TOP LEFT — Ship Status Diagnostics (Floating) -------
func _build_top_left_diagnostics() -> void:
	# Gunakan MarginContainer untuk jarak aman dari pinggir layar
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	add_child(margin)

	# VBox untuk menumpuk teks secara vertikal otomatis tanpa tabrakan
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	# Label untuk Ship Name (Dimmed header)
	var header = _make_label("AM-FRT-01 // SIG: MONOLITH ECHOES", 10, COLOR_TEXT_DIM, false)
	vbox.add_child(header)
	
	# Garis pemisah tipis
	var separator = _make_tech_line(180, 1)
	vbox.add_child(separator)

	# Label State (Besar, Bold, Berwarna saat aktif)
	_state_label = _make_label(">> STANDBY", 14, COLOR_TEXT_DIM, true)
	vbox.add_child(_state_label)

	# Label Koordinat (Muted, di bawah state)
	_coord_label = _make_label("LOC: [ 0 , 0 ]", 11, COLOR_TEXT_DIM, false)
	vbox.add_child(_coord_label)

# ---- BOTTOM LEFT — Vital Defense Systems -----------------
func _build_bottom_left_defense() -> void:
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	
	# INI KUNCINYA: Paksa UI tumbuh ke ATAS (masuk ke layar), bukan ke bawah
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN 
	
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)
	
	var header = _make_label("HULL INTEGRITY", 10, COLOR_TEXT_DIM, false)
	vbox.add_child(header)

	# --- Baris Shield ---
	var shi_vbox = VBoxContainer.new()
	shi_vbox.add_theme_constant_override("separation", 1)
	vbox.add_child(shi_vbox)
	
	var sh_lbl = _make_label("SHIELD FIELD", 11, COLOR_TECH_CYAN, false)
	shi_vbox.add_child(sh_lbl)
	_shield_bar = _make_ultra_thin_bar(150, 3, COLOR_TECH_CYAN)
	shi_vbox.add_child(_shield_bar)

	# --- Baris Armor ---
	var arm_vbox = VBoxContainer.new()
	arm_vbox.add_theme_constant_override("separation", 1)
	vbox.add_child(arm_vbox)
	
	var ar_lbl = _make_label("ARMOR PLATING", 11, COLOR_TECH_AMBER, false)
	arm_vbox.add_child(ar_lbl)
	_armor_bar = _make_ultra_thin_bar(150, 3, COLOR_TECH_AMBER)
	arm_vbox.add_child(_armor_bar)

# ---- BOTTOM RIGHT — Cargo & Storage (Aligned Right) -----
func _build_bottom_right_cargo() -> void:
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	
	# INI KUNCINYA: Paksa UI tumbuh ke ATAS dan KIRI (masuk ke layar)
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# --- Bagian Bar Kargo ---
	var bar_vbox = VBoxContainer.new()
	bar_vbox.add_theme_constant_override("separation", 2)
	bar_vbox.size_flags_horizontal = Control.SIZE_SHRINK_END 
	vbox.add_child(bar_vbox)

	_cargo_title = _make_label("STORAGE: 0 / 0 m³", 12, COLOR_TEXT_MAIN, false)
	_cargo_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar_vbox.add_child(_cargo_title)

	_cargo_bar = _make_ultra_thin_bar(200, 3, COLOR_TECH_CYAN)
	var style_bg = _cargo_bar.get_theme_stylebox("background")
	style_bg.set_content_margin_all(0) 
	bar_vbox.add_child(_cargo_bar)

	# --- Bagian Breakdown Ore ---
	var ore_margin = MarginContainer.new()
	ore_margin.size_flags_horizontal = Control.SIZE_SHRINK_END 
	vbox.add_child(ore_margin)

	var ore_grid = GridContainer.new()
	ore_grid.columns = 1 
	ore_grid.add_theme_constant_override("v_separation", 2)
	ore_margin.add_child(ore_grid)

	_ore_silicate = _make_label("Si [ 0.0 ]", 11, COLOR_SILICATE, false)
	_ore_silicate.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ore_ice      = _make_label("Ic [ 0.0 ]", 11, COLOR_ICE, false)
	_ore_ice.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ore_rare     = _make_label("Ra [ 0.0 ]", 11, COLOR_RARE, false)
	_ore_rare.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	ore_grid.add_child(_ore_rare) 
	ore_grid.add_child(_ore_ice)
	ore_grid.add_child(_ore_silicate)
# ============================================================
# --- Estetik UI Helpers (Bebas Spasi Siluman) ---
# ============================================================

# Membuat label tipis sci-fi tanpa background box kaku
func _make_label(txt: String, sz: int, color: Color, is_bold: bool) -> Label:
	var lbl = Label.new()
	lbl.text = txt
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", sz)
	
	if is_bold:
		# Godot default font bold
		lbl.add_theme_font_override("font", SystemFont.new())
		
	# Trik Estetik: Beri sedikit bayangan redup agar teks terbaca di bg gelap
	lbl.add_theme_color_override("font_shadow_color", Color(0,0,0,0.5))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	
	return lbl

# Membuat bar diagnostik ultra tipis (tinggi 3px)
func _make_ultra_thin_bar(width: int, height: int, fill_color: Color) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, height) # Pakai minimum size agar kontainer otomatis menghormatinya
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	
	# Background bar (Abu-abu sangat gelap, transparan)
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0.05, 0.06, 0.08, 0.6)
	style_bg.set_corner_radius_all(1) # Sudut tajam/hampir kotak
	bar.add_theme_stylebox_override("background", style_bg)

	# Fill bar (Warna murni, Additive blend biar glowing)
	var style_fill = StyleBoxFlat.new()
	style_fill.bg_color = fill_color
	# KUNCI ESTETIK: Nyalakan antialiasing agar bar tipis tidak terlihat pecah
	style_fill.anti_aliasing = true 
	style_fill.set_corner_radius_all(1)
	bar.add_theme_stylebox_override("fill", style_fill)
	
	bar.modulate = fill_color.lightened(0.2)

	return bar

# Membuat garis pemisah tipis dekoratif ala diagnostik
func _make_tech_line(width: int, height: int) -> ColorRect:
	var cr = ColorRect.new()
	cr.custom_minimum_size = Vector2(width, height)
	cr.color = COLOR_TEXT_DIM
	cr.color.a = 0.3 # Sangat transparan
	return cr
