package menu

import clay "../third_party/clay"

WHITE :: clay.Color{242, 246, 248, 255}
MUTED :: clay.Color{155, 170, 182, 255}
ACCENT :: clay.Color{155, 230, 80, 255}
PANEL :: clay.Color{16, 22, 29, 240}
SURFACE :: clay.Color{28, 37, 46, 255}
SELECTED :: clay.Color{46, 64, 40, 255}

text :: proc(label: string, size, scale: f32, color: clay.Color = WHITE) {
	clay.Text(label, {fontSize = u16(size * scale), lineHeight = u16(size * scale * 1.3), textColor = color})
}

button :: proc(state: ^State, label, id_label: string, action: Action, selected: bool = false, primary: bool = false, enabled: bool = true) {
	id := clay.ID(id_label, u32(action.index))
	register(state, {id = id, action = action, enabled = enabled})
	color := selected ? SELECTED : SURFACE
	if clay.PointerOver(id) && enabled { color = {45, 57, 68, 255} }
	if state.pressed == id.id { color = {59, 72, 83, 255} }
	if primary { color = enabled ? ACCENT : SURFACE }
	label_color := !enabled ? MUTED : primary ? clay.Color{16, 25, 18, 255} : selected ? ACCENT : WHITE
	if clay.UI(id)({
		layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(48 * state.scale)}, padding = clay.PaddingAll(u16(14 * state.scale)), childAlignment = {y = .Center}},
		backgroundColor = color,
		cornerRadius = clay.CornerRadiusAll(5 * state.scale),
		border = {color = state.focus == id.id ? ACCENT : clay.Color{}, width = clay.BorderOutside(state.focus == id.id ? 1 : 0)},
	}) {
		text(label, 17, state.scale, label_color)
	}
}

spacer :: proc() {
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}}}) {}
}

rule :: proc(scale: f32) {
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(1)}}, backgroundColor = {65, 79, 90, 150}}) {}
}

stat :: proc(label, value: string, scale: f32) {
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childAlignment = {y = .Center}}}) {
		text(label, 13, scale, MUTED)
		spacer()
		text(value, 16, scale)
	}
}
