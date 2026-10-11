// Simple Text Editor

// TODO(c4llv07e): Somewhere in the future add different encoding and line ending settings.
// TODO(c4llv07e): More keybinds for text movement.
// TODO(c4llv07e): ring buffer Undo-redo.
// TODO(c4llv07e): Profile everything.
// TODO(c4llv07e): Selection mark animations.
// TODO(c4llv07e): Store buffer modification in undo ring
// TODO(c4llv07e): Store font_height as a variable and don't query it each time.

// NOTE(c4llv07e): Maybe there should be a primary selection like in most X11 text editors?

#if false {
	font_path :: "/usr/share/fonts/TTF/liberation/LiberationMono-Regular.ttf";
} else {
	font_path :: "/usr/share/fonts/TTF/liberation/LiberationSans-Regular.ttf";
}
SCROLL_MOD :: 30;
HARD_LOCK_CHECK :: false;

Visual_Line :: struct {
	real_line_number: s64;
	start_byte_offset: s64;
	length: s64;
}

Buffer_Type :: enum u32 {
	Text;
	File_Dialog; // _Open
	File_Dialog_Save;
}

Undo_Type :: enum u32 {
	Insert;
	Delete;
}

Undo_Group :: enum u32 {
	Keyboard;
	Clipboard;
}

Undo_Operation :: struct {
	type: Undo_Type;
	group: Undo_Group;
	pos: s64;
	data: [..]u8;
}

Text_Buffer :: struct {
#as buffer: [..]u8;
	filepath: string;
	content_type: Buffer_Type;
	immutable_prefix_size: s64;
	modified: bool;
	undos: [..]Undo_Operation;
	undos_cursor: s64;
}

Ctx :: struct {
	keybind_root: Keybind_Root;
	modes: [..]s64;
	current_keybind: *Keybind;
	window: *SDL_Window;
	renderer: *SDL_Renderer;
	font: *TTF_Font;
	space_texture: *SDL_Texture;
	tab_texture: *SDL_Texture;
	window_width, window_height: s64;
	required_cursor_width: s64;
	selection_mark: s64; // I think it shouldn't have an animation.
	cursor: s64;
	cursor_interp: SDL_FPoint;
	real_cursor_position: SDL_FPoint;
	text_buffer: Text_Buffer;
	text_buffers: [..]Text_Buffer; // Because I am too lazy to do proper abstraction over text editing code.
	scroll: float32;
	scroll_interp: float32;
	line_number_width: float32;
	visual_lines: [..]Visual_Line;
	should_render: bool;
	is_ctrl_held: bool;
	tab_width: s32 = 8; // Per spaces
	deltatime: float32;
	previous_frame_time: u64;
	current_frame_time: u64;
}

insert_text_no_undo :: (using ctx: *Ctx, tb: *Text_Buffer, content: string, position: s64) {
	assert(position >= 0, "Can't insert text into negative position");
	assert(tb.buffer.count >= position, "Tried to insert text out of bounds");
	if tb.immutable_prefix_size > position {
		return;
	}
	array_resize(*tb.buffer, tb.buffer.count + content.count);
	// ------p-----------------e
	// ------p=====c-----------------e
	memcpy(*tb.buffer.data[position + content.count], *tb.buffer.data[position], tb.buffer.count - position);
	memcpy(*tb.buffer.data[position], *content.data[0], content.count);
	if cursor >= position then cursor += content.count;
	if selection_mark >= position then selection_mark += content.count;
	should_render = true;
	required_cursor_width = -1;
}

update_cursor_scroll :: (using ctx: *Ctx) {
	cursor_visline := offset_to_visline_index(ctx, cursor);
	if cursor_visline == -1 {
		// Strange, but ok.
		return;
	}
	font_height := TTF_GetFontHeight(font);
	cursor_height := (cursor_visline * font_height);
	if cursor_height < xx scroll || cursor_height > xx scroll + window_height {
		scroll = xx (cursor_height - (window_height / 2));
	}
}

insert_text :: (using ctx: *Ctx, tb: *Text_Buffer, content: string, position: s64, undo_group: Undo_Group) {
	insert_text_no_undo(ctx, tb, content, position);
	copy_string(content);
	arr: [..]u8;
	array_copy(*arr, cast([]u8)content);
	undo_push_op(ctx, tb, .{type = .Insert, group = undo_group, pos = position, data = arr});
	calculate_vislines(ctx);
	update_cursor_scroll(ctx);
}

delete_text_no_undo :: (using ctx: *Ctx, tb: *Text_Buffer, position: s64, length: s64) {
	assert(position >= 0, "Can't remove text from negative index");
	assert(tb.buffer.count >= position + length, "Can't remove text outside of the text buffer");
	if tb.buffer.count > position + length {
		memcpy(*tb.buffer[position], *tb.buffer[position + length], tb.buffer.count - position - length);
	}
	array_resize(*tb.buffer, tb.buffer.count - length);
	if cursor >= (position + length) then cursor -= length;
	else if cursor >= position then cursor = position;
	if selection_mark >= (position + length) then selection_mark -= length;
	else if selection_mark >= position then selection_mark = position;
	should_render = true;
}

delete_text :: (using ctx: *Ctx, tb: *Text_Buffer, position: s64, length: s64, undo_group: Undo_Group) {
	arr: [..]u8;
	array_copy(*arr, cast([]u8)slice(cast(string)tb.buffer, position, length));
	delete_text_no_undo(ctx, tb, position, length);
	undo_push_op(ctx, tb, .{type = .Delete, group = undo_group, pos = position, data = arr});
}

calculate_vislines :: (using ctx: *Ctx) {
	array_reset(*visual_lines);
	sv := cast(string)text_buffer.buffer;
	if !sv return;
	adv: s32;
	initial_window_width := window_width - line_number_width;
	left_space := initial_window_width;
	line_begin := sv;
	hard_locked := HARD_LOCK_CHECK;
	before_char: string;
	digit_width := sdl_char_width(font, #char "9"); // the most wide one. Maybe one day I will calculate max width of all digits.
	iter := 0;
	newlines_count := 0;
	while true {
#if HARD_LOCK_CHECK {
			if iter > 1024*10 {
				break;
			}
		}
		before_char = sv;
		cp, ok := utf8_next_character(*sv);
		if ok == .SOURCE_EXHAUSTED {
			hard_locked = false;
			break;
		}
		assert(ok != .SOURCE_ILLEGAL, "Can't iterate over text buffer, error on '%': %", slice(sv, 0, 5), ok);
		if cp == #char "\n" {
			array_add(*visual_lines, .{newlines_count, line_begin.data - text_buffer.buffer.data, sv.data - line_begin.data - 1});
			newlines_count += 1;
			line_begin = sv;
			left_space = initial_window_width;
			continue;
		}
		adv = measure_char_or_tab(ctx, font, cp);
		left_space -= adv;
		if left_space <= 0 && (before_char.data - line_begin.data > 0) {
			array_add(*visual_lines, .{newlines_count, line_begin.data - text_buffer.buffer.data, before_char.data - line_begin.data});
			line_begin = before_char;
			sv = before_char;
			left_space = initial_window_width;
			continue;
		}
	}
	assert(!hard_locked, "Hard locked at generating visual lines");
	array_add(*visual_lines, .{newlines_count, line_begin.data - text_buffer.buffer.data, sv.data - line_begin.data});
	line_number_width = (1 + SDL_ceilf(SDL_log10f(xx (newlines_count + 2)))) * digit_width;
}

undo_free_after_cursor :: (using ctx: *Ctx, tb: *Text_Buffer) {
	while tb.undos_cursor < tb.undos.count {
		array_free(pop(*tb.undos).data);
	}
}

undo_push_op :: (using ctx: *Ctx, tb: *Text_Buffer, op: Undo_Operation) {
	if tb.undos {
		prev_op := peek_pointer(tb.undos);
		if prev_op.type == {
			case .Insert;
			if op.type == prev_op.type && op.pos == (prev_op.pos + prev_op.data.count) {
				if (op.data[0] == #char "\n") == (prev_op.data[prev_op.data.count - 1] == #char "\n") {
					undo_free_after_cursor(ctx, tb);
					array_add(*prev_op.data, ..op.data);
					array_free(op.data);
					return;
				}
			}
			case .Delete;
			if op.type == prev_op.type && (op.pos + op.data.count) == prev_op.pos {
				undo_free_after_cursor(ctx, tb);
				array_add(*op.data, ..prev_op.data);
				array_free(prev_op.data);
				prev_op.* = op;
				return;
			}
			case;
			log_error("Unknown undo operation type %", prev_op.type);
		}
	}
	if tb.undos_cursor >= tb.undos.count {
		array_add(*tb.undos, op);
	} else {
		tb.undos[tb.undos_cursor] = op;
	}
	tb.undos_cursor += 1;
	undo_free_after_cursor(ctx, tb);
}

draw_text :: (renderer: *SDL_Renderer, font: *TTF_Font, x: float, y: float, color: SDL_Color, text: string) {
        surface: *SDL_Surface = TTF_RenderText_Blended(font, text.data, xx text.count, color);
	if surface == null {
		log_error("Can't render text on surface: %", sdl_get_error());
		return;
	}
	defer SDL_DestroySurface(surface);
	texture: *SDL_Texture = SDL_CreateTextureFromSurface(renderer, surface);
	if texture == null {
		log_error("Can't convert surface to texture: %", sdl_get_error());
		return;
	}
	defer SDL_DestroyTexture(texture);
	text_bounds := SDL_FRect.{
		x = SDL_floorf(x),
		y = SDL_floorf(y),
		w = xx texture.w,
		h = xx texture.h,
	};
	if !SDL_RenderTexture(renderer, texture, null, *text_bounds) {
		log_error("Can't blit texture: %", sdl_get_error());
	}
}

draw_fancy_text :: (using ctx: *Ctx, x: float, y: float, text: string, color: SDL_Color = .{0xe3, 0xe3, 0xe3, 0xff}) {
	special_chars :: " \t";
	sv := text;
	space_width := sdl_char_width(font, #char " ");
	font_height := TTF_GetFontHeight(font);
	while true {
		match := find_index_of_any_from_left(sv, special_chars);
		if match == -1 {
			draw_text(renderer, font, x, y, color, sv);
			break;
		}
		if match != 0 {
			draw_text(renderer, font, x, y, color, slice(sv, 0, match));
			x += measure_string_with_tab(ctx, font, slice(sv, 0, match));
			advance(*sv, match);
		}
		while sv.count > 0 && is_any(sv.data[0], special_chars) {
			if sv.data[0] == {
				case #char " ";
				rect := SDL_FRect.{SDL_floorf(x), SDL_floorf(y), xx space_width, xx font_height};
				SDL_RenderTexture(renderer, space_texture, null, *rect);
				x += space_width;
				case #char "\t";
				rect := SDL_FRect.{SDL_floorf(x), SDL_floorf(y), xx (space_width * tab_width), xx font_height};
				SDL_RenderTexture(renderer, tab_texture, null, *rect);
				x += space_width * tab_width;
				case;
				log_error("% is in special_chars, but not in switch case to handle them.", sv.data[0]);
			}
			advance(*sv, 1);
		}
		if sv.count <= 0 break;
	}
}

offset_to_visline_index :: (using ctx: *Ctx, offset: s64) -> s64 {
	for visual_lines {
		if it.start_byte_offset > offset then return it_index - 1;
	}
	return visual_lines.count - 1;
}

measure_char_or_tab :: (using,except(font) ctx: *Ctx, font: *TTF_Font, ch: u32) -> width: s32 {
	if ch == #char "\t" then return sdl_char_width(font, #char " ") * tab_width;
	else return sdl_char_width(font, ch);
}

measure_string_with_tab :: (using,except(font,width) ctx: *Ctx, font: *TTF_Font, text: string, max_width: s64 = -1) -> width: s32, length: u64 {
	width: s32 = 0;
	length: u64 = 0;
	if !text then return 0, 0;
	for :utf8_iter text {
		ch_width := measure_char_or_tab(ctx, font, it);
		if max_width != -1 && (width + ch_width > max_width) {
			return width, length;
		}
		width += ch_width;
		length += trailingBytesForUTF8[it&0xff] + 1;
	}
	return width, length;
}

draw_on_left :: (using ctx: *Ctx, y: float32, text: string, color: SDL_Color = .{0xe3, 0xe3, 0xe3, 0xff}) {
	ok, width := sdl_measure_string(font, text);
	draw_text(renderer, font, xx (window_width - width), y, color, text);
}

update_real_cursor_position :: (using ctx: *Ctx) {
	if visual_lines {
		font_height := TTF_GetFontHeight(font);
		cursor_visline_index := offset_to_visline_index(ctx, cursor);
		if cursor_visline_index == -1 {
			real_cursor_position = .{line_number_width, 0};
			return;
		}
		cursor_visline := visual_lines[cursor_visline_index];
		before_cursor_string_length := (cursor - cursor_visline.start_byte_offset);
		width: s32;
		if before_cursor_string_length > 0
			width = measure_string_with_tab(ctx, font, slice(cast(string)text_buffer.buffer, cursor_visline.start_byte_offset, before_cursor_string_length));
		else
			width = 0;
		real_cursor_position = .{line_number_width + xx width, xx ((cursor_visline_index * font_height) - scroll_interp)};
	} else {
		real_cursor_position = .{line_number_width, - scroll_interp};
	}
}

copy_to_clipboard :: (text: string) {
	SDL_SetClipboardText(to_c_string(text,, temp));
}

render_frame_count := 0;
render :: (using ctx: *Ctx) {
	drawed: s64 = 0;
	if !should_render {
		SDL_Delay(1);
		return;
	}
	update_real_cursor_position(ctx);
	font_height := TTF_GetFontHeight(font);
	sdl_set_color(renderer, .{0x20, 0x20, 0x20, 0xff});
	SDL_RenderClear(renderer);
	max_real_line_number := 0;
	fill_rect(renderer, .{0, 0, xx line_number_width, xx window_height}, .{0x10, 0x20, 0x10, 0xff});
	draw_rect_lines(renderer, .{0, 0, xx line_number_width, xx window_height}, .{0x20, 0x30, 0x20, 0xff});
	for visual_lines {
		if (xx ((it_index + 1) * font_height) - scroll_interp) < 0 then continue;
		if (xx (it_index * font_height) - scroll_interp) > xx window_height then break;
		line: string = ---;
		line.data = *text_buffer.buffer.data[it.start_byte_offset];
		line.count = it.length;
		if max_real_line_number < it.real_line_number + 1 {
			draw_text(renderer, font, 0, xx (it_index * font_height) - scroll_interp, .{0x43, 0x83, 0x43, 0xff}, tprint("%", it.real_line_number + 1));
			max_real_line_number = it.real_line_number + 1;
		}
		if line.count <= 0 {
			continue;
		}
		// line_width := measure_string_with_tab(ctx, font, line);
		// draw_rect_lines(renderer, .{line_number_width, - scroll_interp + xx (it_index * font_height), xx line_width, xx font_height}, .{0xff, 0x00, 0x00, 0xff});
		draw_fancy_text(ctx, line_number_width, - scroll_interp + xx (it_index * font_height), line);
		drawed += 1;
	}
	vislines_end_y := xx (visual_lines.count * font_height) - scroll_interp;
	fill_rect(renderer, .{line_number_width, vislines_end_y, window_width - line_number_width, window_height - vislines_end_y}, .{0x18, 0x18, 0x18, 0xff});
	if scroll_interp < 0 then fill_rect(renderer, .{line_number_width, 0, window_width - line_number_width, -scroll_interp}, .{0x18, 0x18, 0x18, 0xff});
	{ // Debug
		draw_on_left(ctx, xx (font_height * 0), tprint("%", render_frame_count));
		draw_on_left(ctx, xx (font_height * 1), tprint("%", drawed));
		draw_on_left(ctx, xx (font_height * 2), tprint("%", cursor));
		draw_on_left(ctx, xx (font_height * 3), tprint("%", required_cursor_width));
		draw_on_left(ctx, xx (font_height * 4), tprint("%", font_height));
		draw_on_left(ctx, xx (font_height * 5), tprint("%", ctx.modes));
#if true {
			sb: String_Builder;
			print(*sb, "[");
			for ctx.text_buffers {
				print(*sb, "%, ", it.content_type);
			}
			print(*sb, "]");
			draw_on_left(ctx, xx (font_height * 6), builder_to_string(*sb));
		}
		draw_on_left(ctx, xx (font_height * 7), tprint("% - %", text_buffer.undos.count, text_buffer.undos_cursor));
	}
	static_cursor_width := max(1.0, font_height / 8.0);
	cursor_width := max(static_cursor_width, SDL_logf(length_squared(real_cursor_position - cursor_interp)));
	cursor_interp_rect := SDL_FRect.{cursor_interp.x - cursor_width / 2, cursor_interp.y, cursor_width, xx font_height};
	{ // Selection mark
		selection_visline_index := offset_to_visline_index(ctx, selection_mark);
		selection_mark_pos := SDL_FRect.{line_number_width, 0.0, static_cursor_width, xx font_height};
		if selection_visline_index != -1 {
			selection_mark_pos.y = (selection_visline_index * font_height) - scroll_interp;
			width: s32 = 0;
			selection_visline := visual_lines[selection_visline_index];
			before_selection_length := (selection_mark - selection_visline.start_byte_offset);
			if before_selection_length > 0 {
				width = measure_string_with_tab(ctx, font, slice(cast(string)text_buffer.buffer,
										 selection_visline.start_byte_offset,
										 before_selection_length));
			}
			selection_mark_pos.x = line_number_width + xx width;
		}
		selection_mark_pos.x -= selection_mark_pos.w / 2;
		fill_rect(renderer, selection_mark_pos, .{0xff, 0xff, 0x00, 0xff});
		selection_mark_dot_size := font_height / 7;
		if cursor <= selection_mark {
			fill_rect(renderer,
				  .{selection_mark_pos.x - selection_mark_dot_size,
					  selection_mark_pos.y + font_height - selection_mark_dot_size,
					  xx selection_mark_dot_size,
					  xx selection_mark_dot_size},
				  .{0xff, 0xff, 0x00, 0Xff});
		} else {
			fill_rect(renderer,
				  .{selection_mark_pos.x + selection_mark_pos.w,
					  selection_mark_pos.y,
					  xx selection_mark_dot_size,
					  xx selection_mark_dot_size},
				  .{0xff, 0xff, 0x00, 0Xff});
		}
	}
	fill_rect(renderer, cursor_interp_rect, .{0x00, 0xff, 0x00, 0xff});
	cursor_selection_dir_line_width := font_height / 3;
	cursor_selection_dir_line_height := font_height / 7;
	if cursor <= selection_mark {
		fill_rect(renderer,
			  .{cursor_interp_rect.x + cursor_interp_rect.w,
				  cursor_interp_rect.y,
				  xx cursor_selection_dir_line_width,
				  xx cursor_selection_dir_line_height},
			  .{0x00, 0xff, 0x00, 0xff});
	} else {
		fill_rect(renderer,
			  .{cursor_interp_rect.x - cursor_selection_dir_line_width,
				  cursor_interp_rect.y + font_height - cursor_selection_dir_line_height,
				  xx cursor_selection_dir_line_width,
				  xx cursor_selection_dir_line_height},
			  .{0x00, 0xff, 0x00, 0xff});
	}
	linecol_padding :: 2;
	linecol_panel_rect := SDL_FRect.{line_number_width, xx (window_height - font_height - linecol_padding * 2), xx (window_width - line_number_width), xx (font_height + linecol_padding * 2)};
	fill_rect(renderer, linecol_panel_rect, .{0x20, 0x30, 0x20, 0xff});
	draw_rect_lines(renderer, linecol_panel_rect, .{0x30, 0x40, 0x30, 0xff});
	vislinenum := offset_to_visline_index(ctx, cursor);
	col: s64 = 0;
	linenum: s64 = 0;
	if vislinenum != -1 { 
		visline := visual_lines[vislinenum];
		col = utf8_count_codepoints(slice(cast(string)text_buffer.buffer, visline.start_byte_offset, cursor - visline.start_byte_offset));
		linenum = visline.real_line_number;
	}
	linecol_text := tprint("Ln: %, Col: %, Buff: %3%4", linenum + 1, col + 1, text_buffer.filepath, (ifx text_buffer.modified then "*" else ""));
	draw_text(renderer, font, linecol_panel_rect.x + linecol_padding, linecol_panel_rect.y + linecol_padding, .{0xe3, 0xe3, 0xe3, 0xff}, linecol_text);
	SDL_RenderPresent(renderer);
	render_frame_count += 1;
	should_render = false;
}

check_sdl :: (status: bool, msg := "Error on calling sdl function", caller_loc := #caller_location) #expand {
	if (!status) {
		log_error("%: %: %\n", caller_loc, msg, sdl_get_error(), flags=.ERROR);
		exit(-1);
	}
}

point_to_cursor :: (using ctx: *Ctx, point_x: float32, point_y: float32) -> s64 {
	y := 0.0;
	font_height := TTF_GetFontHeight(font);
	sv := cast(string)text_buffer.buffer;
	point_y += scroll_interp;
	point_x -= line_number_width;
	if point_y < 0 return 0;
	for visual_lines {
		if y <= point_y && y + font_height >= point_y {
			width, length := measure_string_with_tab(ctx, font, slice(sv, it.start_byte_offset, it.length), xx point_x);
			return it.start_byte_offset + xx length;
		}
		y += font_height;
	}
	return sv.count;
}

create_textures :: (using ctx: *Ctx) {
	{ // space
		space_surface := TTF_RenderGlyph_Blended(font, #char ".", color_dim_by(.{0xe3, 0xe3, 0xe3, 0xff}, 2));
		assert(space_surface != null, "Can't generate space surface!");
		defer SDL_DestroySurface(space_surface);
		space_texture = SDL_CreateTextureFromSurface(renderer, space_surface);
		assert(space_texture != null, "Can't generate space texture!");
	}
	{ // tab
		tab_text :: ">>      ";
		assert(tab_text.count == tab_width, "Tab texture size isn't aligned with tab_width");
		tab_surface := TTF_RenderText_Blended(font, tab_text.data, tab_text.count, color_dim_by(.{0xe3, 0xe3, 0xe3, 0xff}, 2));
		assert(tab_surface != null, "Can't generate tab surface!");
		defer SDL_DestroySurface(tab_surface);
		tab_texture = SDL_CreateTextureFromSurface(renderer, tab_surface);
		assert(tab_texture != null, "Can't generate tab texture!");
	}
}

go_up_line :: (using ctx: *Ctx) {
	sv := cast(string)text_buffer.buffer;
	first_nl := find_index_from_right(slice(sv, 0, cursor), #char "\n");
	should_render = true;
	if first_nl <= text_buffer.immutable_prefix_size {
		cursor = text_buffer.immutable_prefix_size;
		return;
	}
	if required_cursor_width == -1 {
		update_required_cursor_width(ctx);
	}
	second_nl := find_index_from_right(slice(sv, 0, first_nl), #char "\n");
	if required_cursor_width == 0 {
		cursor = second_nl + 1;
		return;
	}
	second_width, length := measure_string_with_tab(ctx, font, slice(sv, second_nl + 1, first_nl - second_nl - 1), xx required_cursor_width);
	cursor = second_nl + 1 + xx length;
	update_cursor_scroll(ctx);
}

go_down_line :: (using ctx: *Ctx) {
	sv := cast(string)text_buffer.buffer;
	first_nl := find_index_from_left(slice(sv, cursor, sv.count), #char "\n");
	should_render = true;
	if first_nl < 0 {
		cursor = sv.count;
		return;
	}
	first_nl += cursor;
	if required_cursor_width == -1 {
		update_required_cursor_width(ctx);
	}
	second_nl := find_index_from_left(slice(sv, first_nl + 1, sv.count), #char "\n");
	if second_nl == -1 {
		second_nl = sv.count;
	} else {
		second_nl += first_nl + 1;
	}
	second_width, length := measure_string_with_tab(ctx, font, slice(sv, first_nl + 1, second_nl - first_nl - 1), xx required_cursor_width);
	cursor = first_nl + 1 + xx length;
	update_cursor_scroll(ctx);
}

update_required_cursor_width :: inline (using ctx: *Ctx) {
	sv := cast(string)text_buffer.buffer;
	line_start := find_index_from_right(slice(sv, 0, cursor), #char "\n");
	required_cursor_width = measure_string_with_tab(ctx, font, slice(sv, line_start + 1, cursor - line_start - 1));
}

insert_char_u8 :: (using ctx: *Ctx, $char: u8, $undo_group: Undo_Group = .Keyboard) {
	ch := char;
	sv: string = ---;
	sv.data = *ch;
	sv.count = 1;
	insert_text(ctx, *text_buffer, sv, cursor, undo_group);
}

go_left :: (using ctx: *Ctx) {
	if cursor > text_buffer.immutable_prefix_size {
		cursor -= 1;
		while cursor > text_buffer.immutable_prefix_size && ((text_buffer.buffer.data[cursor] & 0xc0) == 0x80) {
			cursor -= 1;
		}
		required_cursor_width = -1;
		should_render = true;
	}
}

go_right :: (using ctx: *Ctx) {
	if cursor < text_buffer.buffer.count {
		cursor += 1;
		while cursor < text_buffer.buffer.count && ((text_buffer.buffer.data[cursor] & 0xc0) == 0x80) {
			cursor += 1;
		}
		required_cursor_width = -1;
		should_render = true;
	}
}

#if false {
	go_left_word :: (using ctx: *Ctx) {
		if cursor > text_buffer.immutable_prefix_size {
			cp, ok := utf8_step_back(cast(string)text_buffer.buffer, *cursor);
			should_render = true;
			while cursor > 0 && is_alpha(cp) && is_digit(text_buffer.buffer[cursor]) {
				cursor -= 1;
			}
		}
	}
}

remove_previous_char :: (using ctx: *Ctx) {
	from := cursor;
	while from > text_buffer.immutable_prefix_size && ((text_buffer.buffer.data[from - 1] & 0xc0) == 0x80) {
		from -= 1;
	}
	if from > text_buffer.immutable_prefix_size {
		from -= 1;
	}
	delete_text(ctx, *text_buffer, from, cursor - from, .Keyboard);
}

set_mark :: (using ctx: *Ctx) {
	selection_mark = cursor;
	should_render = true;
}

copy_selection :: (using ctx: *Ctx) {
	if cursor == selection_mark return;
	from := min(cursor, selection_mark);
	to := max(cursor, selection_mark);
	copy_to_clipboard(slice(cast(string)text_buffer.buffer, from, to - from));
}

cut_selection :: (using ctx: *Ctx) {
	if cursor == selection_mark return;
	from := min(cursor, selection_mark);
	to := max(cursor, selection_mark);
	sv := slice(cast(string)text_buffer.buffer, from, to - from);
	copy_to_clipboard(sv);
	delete_text(ctx, *text_buffer, from, sv.count, .Clipboard);
}

paste_text :: (using ctx: *Ctx) {
	if !SDL_HasClipboardText() return;
	cstr := SDL_GetClipboardText();
	if cstr == null return;
	defer SDL_free(cstr);
	sv := to_string(cstr);
	insert_text(ctx, *text_buffer, sv, cursor, .Clipboard);
}

go_line_beginning :: (using ctx: *Ctx) {
	if cursor <= text_buffer.immutable_prefix_size return;
	cursor -= 1;
	should_render = true;
	required_cursor_width = -1;
	while cursor > text_buffer.immutable_prefix_size && text_buffer.buffer[cursor] != #char "\n" cursor -= 1;
	if text_buffer.buffer[cursor] == #char "\n" cursor += 1;
}

go_line_end :: (using ctx: *Ctx) {
	if cursor >= text_buffer.buffer.count return;
	should_render = true;
	required_cursor_width = -1;
	while cursor < text_buffer.buffer.count && text_buffer.buffer[cursor] != #char "\n" cursor += 1;
}

// Current model is too simple to introduce some form of multi buffer memory management.
// So for now currently opened buffer is in text_buffer and text_buffers stack is used only
// for shadowed buffers (like for a file content while the new one is a file dialog).
stash_file_buffer :: (using ctx: *Ctx) {
	array_add(*text_buffers, text_buffer); // Save current one.
	text_buffer = .{}; // reset without cleaning space.
}

try_enable_mode :: (using ctx: *Ctx, name: string) {
	mode_index := find_mode_index(ctx.keybind_root, name);
	if mode_index != -1 {
		if !is_mode_enabled(ctx.modes, mode_index) {
			array_add(*ctx.modes, mode_index);
		}
	}
}

open_file_dialog :: (using ctx: *Ctx) {
	// Theoretically you could open file dialog inside another file dialog. Don't know if
	// we should prevent this.
	prefix_path: string = "./";
	if text_buffer.filepath {
		prefix_path = get_absolute_path(text_buffer.filepath);
		prefix_path = path_strip_filename(prefix_path);
	}
	stash_file_buffer(ctx);
	text_buffer.content_type = .File_Dialog;
	prefix :: "Enter file path to open: ";
	text_buffer.immutable_prefix_size = prefix.count;
	array_add(*text_buffer.buffer, ..cast([]u8)prefix);
	array_add(*text_buffer.buffer, ..cast([]u8)prefix_path);
	try_enable_mode(ctx, "file_dialog");
	cursor = text_buffer.buffer.count;
	selection_mark = text_buffer.immutable_prefix_size;
	should_render = true;
}

// Creates now buffer on the text_buffer stack and returns pointer to it.
open_buffer_from_file :: (using ctx: *Ctx, filepath: string) -> Text_Buffer {
	content, exists := read_entire_file(filepath);
	if !exists {
		log_error("Can't open file '%'", filepath);
		content = copy_string("");
	}
	new_buffer: Text_Buffer;
	array_add(*new_buffer.buffer, ..cast([]u8)content);
	new_buffer.filepath = copy_string(filepath);
	return new_buffer;
}

try_disable_mode :: (using ctx: *Ctx, mode: string) {
	file_dialog_index := find_mode_index(ctx.keybind_root, mode);
	if file_dialog_index != -1 {
		array_ordered_remove_by_value(*ctx.modes, file_dialog_index);
	}
}

file_dialog_enter :: (using ctx: *Ctx) {
	entered_path := cast(string)text_buffer.buffer;
	filepath := copy_temporary_string(trim(slice(entered_path, text_buffer.immutable_prefix_size, text_buffer.buffer.count)));
	if text_buffer.content_type != .File_Dialog {
		if text_buffer.content_type != .File_Dialog_Save {
			log_error("Got file dialog button inside non file dialog buffer");
		} else {
			try_disable_mode(ctx, "file_dialog");
			if text_buffers.count <= 0 {
				log_error("Something very bad happened with your text editor, tried to save non-existent buffer.");
				// What should I even do at this point?
				return;
			}
			text_buffer = pop(*text_buffers);
			if text_buffer.filepath then free(text_buffer.filepath);
			text_buffer.filepath = copy_string(filepath);
			write_entire_file(filepath, cast(string)text_buffer.buffer);
			text_buffer.modified = false;
			should_render = true;
			return;
		}
	} else {
		array_reset(*text_buffer.buffer);
		for text_buffers {
			if text_buffer.buffer.data == it.buffer.data remove;
		}
	}
	text_buffer = open_buffer_from_file(ctx, filepath);
	try_disable_mode(ctx, "file_dialog");
	for * text_buffers {
		free_text_buffer(it);
	}
	array_reset_keeping_memory(*text_buffers);
	cursor = text_buffer.immutable_prefix_size;
	selection_mark = cursor;
	should_render = true;
}

free_text_buffer :: (tb: *Text_Buffer) {
	array_free(tb.buffer);
	if tb.filepath then free(tb.filepath);
	for tb.undos {
		array_free(it.data);
	}
	array_free(tb.undos);
	free(tb);
}

swap_mark_with_cursor :: (using ctx: *Ctx) {
	Swap(*cursor, *selection_mark);
	should_render = true;
}

abort_file_dialog :: (using ctx: *Ctx) {
	should_render = true;
	if text_buffers.count <= 0 {
		log_error("File dialog is the only buffer, creating new buffer.");
		text_buffer = .{};
		cursor = text_buffer.immutable_prefix_size;
		selection_mark = cursor;
		return;
	}
	text_buffer = pop(*text_buffers);
	try_disable_mode(ctx, "file_dialog");
	cursor = text_buffer.immutable_prefix_size;
	selection_mark = cursor;
}

prompt_and_save :: (using ctx: *Ctx) {
	prefix_path: string = "./";
	if text_buffer.filepath {
		prefix_path = get_absolute_path(text_buffer.filepath,, temp);
		prefix_path = path_strip_filename(prefix_path);
	}
	stash_file_buffer(ctx);
	text_buffer.content_type = .File_Dialog_Save;
	prefix :: "Enter save path: ";
	text_buffer.immutable_prefix_size = prefix.count;
	array_add(*text_buffer.buffer, ..cast([]u8)prefix);
	array_add(*text_buffer.buffer, ..cast([]u8)prefix_path);
	try_enable_mode(ctx, "file_dialog");
	cursor = text_buffer.buffer.count;
	selection_mark = text_buffer.immutable_prefix_size;
	should_render = true;
}

save_path_or_prompt :: (using ctx: *Ctx) {
	if text_buffer.filepath {
		write_entire_file(text_buffer.filepath, cast(string)text_buffer.buffer);
		text_buffer.modified = false;
		should_render = true;
		return;
	}
	prompt_and_save(ctx);
}

undo :: (using ctx: *Ctx, tb: *Text_Buffer = null) {
	if tb == null then tb = *text_buffer;
	if tb.undos_cursor <= 0 return;
	op := tb.undos[tb.undos_cursor - 1];
	if op.type == {
		case .Insert;
		// -----f----t--------l
		// -----t--------l
		memcpy(*tb.buffer.data[op.pos], *tb.buffer.data[op.pos + op.data.count], tb.buffer.count - (op.pos + op.data.count));
		tb.buffer.count -= op.data.count;
		tb.undos_cursor -= 1;
		if cursor >= (op.pos + op.data.count) then cursor -= op.data.count;
		else if cursor >= op.pos then cursor = op.pos;
		if selection_mark >= (op.pos + op.data.count) then selection_mark -= op.data.count;
		else if selection_mark >= op.pos then selection_mark = op.pos;
		case .Delete;
		insert_text_no_undo(ctx, tb, cast(string)op.data, op.pos);
		tb.undos_cursor -= 1;
		case;
		log_error("Unknown undo operation type %", op.type);
	}
	should_render = true;
}

redo :: (using ctx: *Ctx, tb: *Text_Buffer = null) {
	if tb == null then tb = *text_buffer;
	if tb.undos_cursor >= tb.undos.count return;
	op := tb.undos[tb.undos_cursor];
	if op.type == {
		case .Delete;
		memcpy(*tb.buffer.data[op.pos], *tb.buffer.data[op.pos + op.data.count], tb.buffer.count - (op.pos + op.data.count));
		tb.buffer.count -= op.data.count;
		tb.undos_cursor += 1;
		if cursor >= (op.pos + op.data.count) then cursor -= op.data.count;
		else if cursor >= op.pos then cursor = op.pos;
		if selection_mark >= (op.pos + op.data.count) then selection_mark -= op.data.count;
		else if selection_mark >= op.pos then selection_mark = op.pos;
		case .Insert;
		insert_text_no_undo(ctx, tb, cast(string)op.data, op.pos);
		tb.undos_cursor += 1;
		case;
		log_error("Unknown undo operation type %", op.type);
	}
	should_render = true;
}

handle_command :: (using ctx: *Ctx, command: string) -> ok: bool {
	// I know what you think, but I'm doing it so I can do more than just
	// calling existing functions there.
	if command == {
		case "go_up_line";
		go_up_line(ctx);
		case "go_down_line";
		go_down_line(ctx);
		case "insert_tab";
		insert_char_u8(ctx, #char "\t");
		case "insert_newline";
		insert_char_u8(ctx, #char "\n");
		case "go_left";
		go_left(ctx);
		case "go_right";
		go_right(ctx);
		case "remove_previous_char";
		remove_previous_char(ctx);
		case "set_mark";
		set_mark(ctx);
		case "swap_mark_with_cursor";
		swap_mark_with_cursor(ctx);
		case "cut_selection";
		cut_selection(ctx);
		case "copy_selection";
		copy_selection(ctx);
		case "paste_text";
		paste_text(ctx);
		case "go_line_beginning";
		go_line_beginning(ctx);
		case "go_line_end";
		go_line_end(ctx);
		case "open_file_dialog";
		open_file_dialog(ctx);
		case "enter_path";
		file_dialog_enter(ctx);
		case "abort_file_dialog";
		abort_file_dialog(ctx);
		case "save_path_or_prompt";
		save_path_or_prompt(ctx);
		case "prompt_and_save";
		prompt_and_save(ctx);
		case "undo";
		undo(ctx);
		case "redo";
		redo(ctx);
		case;
		log_error("unknown command %", command);
		return false;
	}
	return true;
}

keybind_mods_from_mod :: (mod: SDL_Keymod) -> Modifier {
	res: Modifier;
	if mod & .CTRL then res |= .CTRL;
	if mod & .ALT then res |= .ALT;
	if mod & .SHIFT then res |= .SHIFT;
	return res;
}

main :: () {
	using ctx := Ctx.{};
	initial_width :: 800;
	initial_height :: 600;
	args := get_command_line_arguments();
	check_sdl(SDL_Init(.VIDEO), "Can't init SDL");
	check_sdl(TTF_Init(), "Can't init font engine");
	check_sdl(SDL_CreateWindowAndRenderer("ste", initial_width, initial_height, .RESIZABLE, *window, *renderer), "Can't create SDL output");
	SDL_SetRenderVSync(renderer, 1);
	program_path: string = "./";
	if args.count > 0 {
		program_path = path_strip_filename(args[0]);
	}
	ctx.keybind_root = generate_keybinds(tprint("%1%2", program_path, "keybinds.conf"));
	array_add(*ctx.modes, 0);
	ctx.current_keybind = *ctx.keybind_root.root;
	font = TTF_OpenFont(font_path, 16);
	if args.count > 1 {
		text_buffer = open_buffer_from_file(*ctx, args[1]);
	}
	event: SDL_Event;
	create_textures(*ctx);
	should_render = true;
	previous_frame_time = SDL_GetTicks();
	SDL_StartTextInput(window);
	while main_loop := true {
		current_frame_time := SDL_GetTicks();
		deltatime = (current_frame_time - previous_frame_time) / 1000.0;
		previous_frame_time = current_frame_time;
		while SDL_PollEvent(*event) {
			if event.type == {
				case .QUIT;
				break main_loop;
				case .WINDOW_EXPOSED;
				should_render = true;
				case .WINDOW_PIXEL_SIZE_CHANGED;
				window_width = event.window.data1;
				window_height = event.window.data2;
				should_render = true;
				case .WINDOW_RESIZED;
				window_width = event.window.data1;
				window_height = event.window.data2;
				should_render = true;
				case .KEY_DOWN;
				keybind_mods := keybind_mods_from_mod(event.key.mod);
				next_keybind := walk_key(current_keybind, event.key.key, keybind_mods, ctx.modes);
				if next_keybind == null {
					if current_keybind != *keybind_root.root {
						log_error("unknown keybind (%)-(%)", keybind_mods, event.key.key);
					}
					current_keybind = *keybind_root.root;
				} else {
					command, exists := check_keybind_leaf(next_keybind, ctx.modes);
					if exists {
						handle_command(*ctx, command);
						current_keybind = *keybind_root.root;
					} else {
						current_keybind = next_keybind;
					}
				}
				if event.key.scancode == {
					case .LCTRL; #through;
					case .RCTRL;
					is_ctrl_held = event.key.down;
				}
				case .KEY_UP;
				if event.key.scancode == {
					case .LCTRL; #through;
					case .RCTRL;
					is_ctrl_held = event.key.down;
				}
				case .MOUSE_WHEEL;
				if (is_ctrl_held) {
					font_size := TTF_GetFontSize(font);
					next_size := font_size + event.wheel.integer_y;
					if (next_size >= 1.0) {
						// TODO(c4llv07e): Fix resizing breaking because of visual line jumping.
#if false { // I hate visual and non-visual lines...
							font_height := TTF_GetFontHeight(font);
							line_index := SDL_floorf(scroll / font_height);
							line_offset := SDL_fmodf(scroll, xx font_height) / font_height;
							TTF_SetFontSize(font, next_size);
							font_height = TTF_GetFontHeight(font);
							scroll = (line_index + line_offset) * font_height;
						} else {
							TTF_SetFontSize(font, next_size);
							scroll *= (next_size / font_size);
						}
						scroll_interp = scroll;
						should_render = true;
					}
				} else {
					scroll -= event.wheel.integer_y * SCROLL_MOD;
					should_render = true;
				}
				case .TEXT_INPUT;
				text := to_string(event.text.text);
				text_buffer.modified = true;
				insert_text(*ctx, *text_buffer, text, cursor, .Keyboard);
				case .MOUSE_MOTION;
				if event.motion.state & .LEFT {
					new_cursor := clamp(point_to_cursor(*ctx, event.mouse.x, event.mouse.y), text_buffer.immutable_prefix_size, text_buffer.buffer.count);
					if new_cursor != cursor
						should_render = true;
					cursor = new_cursor;
				}
				case .MOUSE_BUTTON_DOWN;
				cursor = clamp(point_to_cursor(*ctx, event.mouse.x, event.mouse.y), text_buffer.immutable_prefix_size, text_buffer.buffer.count);
				selection_mark = cursor;
				required_cursor_width = -1;
				should_render = true;
			};
		}
		if SDL_fabsf(scroll - scroll_interp) >= 0.01 {
			scroll_interp = Math.lerp(scroll_interp, scroll, 15 * deltatime);
			should_render = true;
		} else {
			if scroll_interp != scroll_interp then should_render = true;
			scroll_interp = scroll;
		}
		if length_squared(real_cursor_position - cursor_interp) >= 0.00001 {
			cursor_interp = lerp(cursor_interp, real_cursor_position, 64 * deltatime);
			should_render = true;
		} else {
			if cursor_interp != real_cursor_position then should_render = true;
			cursor_interp = real_cursor_position;
		}
		if should_render {
			calculate_vislines(*ctx);
			render(*ctx);
		} else {
			SDL_Delay(1);
		}
		reset_temporary_storage();
	}
}

#import,file "keybinds.jai" (SDL_Keycode, sdl_keycode_from_string);
#import "File";
Math :: #import "Math";
#import,file "Unicode.jai";
#import,file "sdl3.jai";
#import "Basic";
#import "String";
#import "Text_File_Handler";