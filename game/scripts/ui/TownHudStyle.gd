extends RefCounted
## Shared presentation tokens. No simulation state or asset dependencies.
const INK := Color(0.055, 0.09, 0.10, 0.94)
const RAISED := Color(0.10, 0.16, 0.17, 0.97)
const LINE := Color(0.36, 0.50, 0.47, 0.80)
const ACCENT := Color(0.65, 0.82, 0.73)
const LINEN := Color(0.94, 0.94, 0.87)
const MUTED := Color(0.72, 0.79, 0.76)

static func panel(raised: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = RAISED if raised else INK
	style.border_color = LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.01,0.025,0.025,0.22)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0,2)
	style.anti_aliasing = true
	return style

static func button(control: Button, font: Font, size: int = 14) -> void:
	control.add_theme_font_override("font",font)
	control.add_theme_font_size_override("font_size",size)
	control.add_theme_color_override("font_color",LINEN)
	control.add_theme_color_override("font_hover_color",Color.WHITE)
	control.add_theme_color_override("font_pressed_color",Color.WHITE)
	control.add_theme_color_override("font_disabled_color",MUTED.darkened(0.25))
	control.add_theme_stylebox_override("normal",panel())
	control.add_theme_stylebox_override("hover",panel(true))
	control.add_theme_stylebox_override("pressed",panel(true))
	var focus := panel(true)
	focus.border_color = ACCENT
	focus.set_border_width_all(2)
	control.add_theme_stylebox_override("focus",focus)
	control.focus_mode = Control.FOCUS_NONE

static func label(control: Label, font: Font, size: int = 14) -> void:
	control.add_theme_font_override("font",font)
	control.add_theme_font_size_override("font_size",size)
	control.add_theme_color_override("font_color",LINEN)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
