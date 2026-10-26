extends RefCounted
## Shared visual tokens for the landscape illustrated research adventure.
## Reference canvas: 1920 x 1080; 48px body / 144px targets remain readable at 720 x 360.
const INK: Color = Color("252647")
const CREAM: Color = Color("fff2d8")
const PURPLE: Color = Color("f16c65") # Legacy token name; approved primary action is coral.
const GREEN: Color = Color("247b77")
const DISABLED_TEXT: Color = Color("68677a")
const SKY: Color = Color("d9eeeb")
const CORAL: Color = Color("f16c65")
const GOLD: Color = Color("f7d760")
const BORDER: Color = Color("d5c9b7")
const BODY_FONT_SIZE: int = 48
const TARGET_SIZE: int = 144
const RADIUS: int = 24

static func panel_style(kind: String = "surface", radius: int = RADIUS) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.border_color = BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.corner_detail = 12
	style.shadow_color = Color(0.06, 0.19, 0.25, 0.13)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 6)
	match kind:
		"raised":
			style.bg_color = Color("ffffff")
			style.shadow_size = 18
		"accent":
			style.bg_color = Color("e0f4ee")
			style.border_color = Color("8ecbb8")
		"dock":
			style.bg_color = Color("f1f8f8")
			style.border_color = Color("b1d5dc")
		"tooltip":
			style.bg_color = Color("fff3d6")
			style.border_color = GOLD
	return style

static func button_style(state: String, filled: bool = false) -> StyleBoxFlat:
	var style := panel_style("surface", RADIUS)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.bg_color = PURPLE if filled else CREAM
	style.border_color = Color("aa4b59") if filled else BORDER
	style.border_width_bottom = 8 if filled else 5
	style.shadow_color = Color(0.05, 0.16, 0.21, 0.19 if filled else 0.09)
	style.shadow_size = 8 if filled else 4
	style.shadow_offset = Vector2(0, 6)
	match state:
		"hover":
			style.bg_color = Color("ff8076") if filled else Color("fff8e9")
		"pressed":
			style.bg_color = Color("db5c5c") if filled else Color("efe0c9")
			style.border_width_bottom = 2
			style.shadow_size = 0
			style.shadow_offset = Vector2.ZERO
		"disabled":
			style.bg_color = Color("dcd7cf")
			style.border_color = Color("c6beb1")
			style.shadow_size = 0
		"focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = GOLD
			style.set_border_width_all(6)
			style.shadow_size = 0
	return style

static func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font = body_font()
	result.default_font_size = BODY_FONT_SIZE
	result.set_color("font_color", "Label", INK)
	result.set_color("font_color", "Button", INK)
	result.set_color("font_hover_color", "Button", INK)
	result.set_color("font_hover_pressed_color", "Button", INK)
	result.set_color("font_pressed_color", "Button", INK)
	result.set_color("font_disabled_color", "Button", DISABLED_TEXT)
	result.set_color("font_focus_color", "Button", INK)
	for control_type in ["CheckButton","CheckBox"]:
		for state in ["font_color","font_hover_color","font_hover_pressed_color","font_pressed_color","font_focus_color"]:
			result.set_color(state,control_type,INK)
		result.set_color("font_disabled_color",control_type,DISABLED_TEXT)
	result.set_constant("outline_size", "Label", 0)
	result.set_constant("h_separation", "Button", 16)
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		result.set_stylebox(state_name, "Button", button_style(state_name))
	result.set_stylebox("panel", "Panel", panel_style())
	for control in ["HScrollBar", "VScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color("e8ddc9")
		track.set_corner_radius_all(8)
		track.content_margin_top = 7
		track.content_margin_bottom = 7
		track.content_margin_left = 7
		track.content_margin_right = 7
		result.set_stylebox("scroll", control, track)
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var thumb := StyleBoxFlat.new()
			thumb.bg_color = PURPLE if state != "grabber" else Color("40b8b3")
			thumb.set_corner_radius_all(8)
			thumb.content_margin_left = 10
			thumb.content_margin_right = 10
			thumb.content_margin_top = 10
			thumb.content_margin_bottom = 10
			result.set_stylebox(state, control, thumb)
	return result

static func body_font() -> FontVariation:
	var font := FontVariation.new()
	font.base_font = load("res://assets/fonts/Onest-Variable.ttf")
	# Godot uses numeric OpenType axis tags; a raw "wght" string leaves this
	# font at its 200-weight default and produces unreadably thin mobile text.
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): 600.0}
	font.fallbacks = [load("res://assets/fonts/DejaVuSans.ttf")]
	return font

static func heading_font() -> FontVariation:
	var font := FontVariation.new()
	font.base_font = load("res://assets/fonts/Onest-Variable.ttf")
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): 800.0}
	font.fallbacks = [load("res://assets/fonts/DejaVuSans.ttf")]
	return font
