// Simple Text Editor

font_path :: "/usr/share/fonts/TTF/liberation/LiberationMono-Regular.ttf";
SCROLL_MOD :: 8;

Visual_Line :: struct {
	start_byte_offset: s64;
	length: s64;
}

Ctx :: struct {
	window: *SDL_Window;
	renderer: *SDL_Renderer;
	font: *TTF_Font;
	window_width, window_height: s64;
	cursor: s64;
	text_buffer: [..]u8;
	scroll: float32;
	line_number_width: float32;
	visual_lines: [..]Visual_Line;
	should_render: bool;
	is_ctrl_held: bool;
}

calculate_vislines :: (using ctx: *Ctx) {
	array_reset(*visual_lines);
	sv := cast(string)text_buffer;
	if !sv return;
	adv: s32;
	initial_window_width := window_width - line_number_width;
	left_space := initial_window_width;
	line_begin := sv;
	hard_locked := true;
	before_char: string;
	for 0..1024 {
		before_char = sv;
		cp, ok := utf8_next_character(*sv);
		if ok == .SOURCE_EXHAUSTED {
			hard_locked = false;
			break;
		}
		assert(ok != .SOURCE_ILLEGAL, "Can't iterate over text buffer, error on '%': %", slice(sv, 0, 5), ok);
		if cp == #char "\n" {
			array_add(*visual_lines, .{line_begin.data - text_buffer.data, sv.data - line_begin.data - 1});
			line_begin = sv;
			left_space = initial_window_width;
			continue;
		}
		assert(TTF_GetGlyphMetrics(font, cp, null, null, null, null, *adv), "Can't get glyph % info", cp);
		left_space -= adv;
		if left_space <= 0 {
			array_add(*visual_lines, .{line_begin.data - text_buffer.data, before_char.data - line_begin.data});
			line_begin = before_char;
			sv = before_char;
			left_space = initial_window_width;
			continue;
		}
	}
	assert(!hard_locked, "Hard locked at generating visual lines");
	if sv.data != line_begin.data {
		array_add(*visual_lines, .{line_begin.data - text_buffer.data, sv.data - line_begin.data});
	}
}

draw_text :: (renderer: *SDL_Renderer, font: *TTF_Font, x: float, y: float, color: SDL_Color, text: string) -> (s32, s32) {
        surface: *SDL_Surface = TTF_RenderText_Blended(font, text.data, xx text.count, color);
	if surface == null {
		log_error("Can't render text on surface: %", sdl_get_error());
		return 0, 0;
	}
	defer SDL_DestroySurface(surface);
	texture: *SDL_Texture = SDL_CreateTextureFromSurface(renderer, surface);
	if texture == null {
		log_error("Can't convert surface to texture: %", sdl_get_error());
		return 0, 0;
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
		return 0, 0;
	}
	return texture.w, texture.h;
}

draw_text_wrapped :: (renderer: *SDL_Renderer, font: *TTF_Font, x: float, y: float, color: SDL_Color, text: string, wrap_width: s32 = 0, caller_loc := #caller_location) -> (x: s32, y: s32) {
	font_height := TTF_GetFontSize(font);
	assert(font_height > 0.0, "Can't get font size.");
	while text.count > 0 {
		ok, line_width, line_text_length := sdl_measure_string(font, text, wrap_width);
		if !ok {
			log_error("Error on rendering wrapped text: %", sdl_get_error());
			return 0, 0;
		}
		if line_text_length <= 0 then line_text_length = 1; // At least draw it partially.
		text_w, text_h := draw_text(renderer, font, x, y, color, slice(text, 0, xx line_text_length));
		if text.count == xx line_text_length {
			return xx x + line_width, xx y;
		}
		advance(*text, xx line_text_length);
		y += font_height;
	}
	return xx x, xx y;
}

offset_to_visline_index :: (using ctx: *Ctx, offset: s64) -> s64 {
	for visual_lines {
		if it.start_byte_offset > offset then return it_index - 1;
	}
	return visual_lines.count - 1;
}

render_frame_count := 0;
render :: (using ctx: *Ctx) {
	if !should_render {
		SDL_Delay(1);
		return;
	}
	font_height := TTF_GetFontHeight(font);
	sdl_set_color(renderer, .{0x20, 0x20, 0x20, 0xff});
	SDL_RenderClear(renderer);
	render_frame_string := tprint("%", render_frame_count);
	ok, render_frame_width := sdl_measure_string(font, render_frame_string);
	scroll_value_string := tprint("%", scroll);
	scroll_value_width: s32;
	ok, scroll_value_width = sdl_measure_string(font, scroll_value_string);
	buffer_string := tprint("%", text_buffer);
	buffer_width: s32;
	ok, buffer_width = sdl_measure_string(font, buffer_string);
	draw_text(renderer, font, xx (window_width - render_frame_width), 0, .{0xe3, 0xe3, 0xe3, 0xff}, render_frame_string);
	draw_text(renderer, font, xx (window_width - scroll_value_width), xx font_height, .{0xe3, 0xe3, 0xe3, 0xff}, scroll_value_string);
	draw_text(renderer, font, xx (window_width - buffer_width), xx (font_height * 2), .{0xe3, 0xe3, 0xe3, 0xff}, buffer_string);
	for visual_lines {
		line: string = ---;
		line.data = *text_buffer.data[it.start_byte_offset];
		line.count = it.length;
		if line.count <= 0 {
			continue;
		}
		draw_rect_lines(renderer, .{line_number_width, - scroll + xx (it_index * font_height), xx (line.count * 10), xx font_height}, .{0xff, 0x00, 0x00, 0xff});
		draw_text(renderer, font, line_number_width, - scroll + xx (it_index * font_height), .{0xe3, 0xe3, 0xe3, 0xff}, line);
	}
	if visual_lines { // Cursor
		cursor_visline_index := offset_to_visline_index(ctx, cursor);
		cursor_visline := visual_lines[cursor_visline_index];
		before_cursor_string_length := (cursor - cursor_visline.start_byte_offset);
		ok: bool;
		width: s32;
		length: u64;
		if before_cursor_string_length > 0
			ok, width, length = sdl_measure_string(font, slice(cast(string)text_buffer, cursor_visline.start_byte_offset, before_cursor_string_length));
		else
			width = 0;
		fill_rect(renderer, .{xx width, xx ((cursor_visline_index * font_height) - scroll), 2, xx font_height}, .{0x00, 0xff, 0x00, 0xff});
	}
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

find_newline :: (using ctx: *Ctx, sv: string, buffer_width: float32) -> s64 {
	ok, width, chopped_count := sdl_measure_string(font, sv, xx buffer_width);
	assert(ok, "Can't measure line %", sv);
	visline := slice(sv, 0, xx chopped_count);
	newline_index := find_index_from_left(visline, #char "\n");
	if newline_index != -1 then return newline_index; // If in visual line \n was found, it means line is smaller than visline.
	return xx chopped_count;
}

point_to_cursor :: (using ctx: *Ctx, point_x: float32, point_y: float32) -> s64 {
	y := 0.0;
	font_height := TTF_GetFontHeight(font);
	sv := cast(string)text_buffer;
	point_y += scroll;
	if point_y < 0 return 0;
	for visual_lines {
		if y <= point_y && y + font_height >= point_y {
			ok, width, length := sdl_measure_string(font, slice(sv, it.start_byte_offset, it.length), xx point_x);
			return it.start_byte_offset + xx length;
		}
		y += font_height;
	}
	return sv.count;
}

cursor_position :: (using ctx: *Ctx) -> (x: float32, y: float32) {
	y := scroll;
	hard_lock := true;
	font_height := TTF_GetFontHeight(font);
	sv := cast(string)text_buffer;
	sv = slice(sv, 0, cursor);
	for 0..255 {
		ok, width, chopped_line := sdl_measure_string(font, sv, xx (window_width - line_number_width));
		assert(ok, "Can't measure %", sv);
		if sv.count < xx chopped_line {
			return 0, y;
		}
		advance(*sv, xx chopped_line);
		y += font_height;
	}
	if hard_lock {
		log_error("Can't find cursor over iterating, maybe a hard lock!");
		exit(-1);
	}
	return 0, y;
}

main :: () {
	using ctx := Ctx.{};
	initial_width :: 800;
	initial_height :: 600;
	check_sdl(SDL_Init(.VIDEO), "Can't init SDL");
	check_sdl(TTF_Init(), "Can't init font engine");
	check_sdl(SDL_CreateWindowAndRenderer("ste", initial_width, initial_height, .RESIZABLE, *window, *renderer), "Can't create SDL output");
	font = TTF_OpenFont(font_path, 16);
	event: SDL_Event;
	should_render = true;
	SDL_StartTextInput(window);
	while main_loop := true {
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
				if event.key.scancode == {
					case .LEFT;
					if cursor > 0 {
						cursor -= 1;
						should_render = true;
					}
					case .RIGHT;
					if cursor < text_buffer.count {
						cursor += 1;
						should_render = true;
					}
					case .RETURN;
					array_insert_at(*text_buffer, #char "\n", cursor);
					cursor += 1;
					should_render = true;
					case .BACKSPACE;
					while cursor > 0 && ((text_buffer.data[cursor - 1] & 0xc0) == 0x80) {
						cursor -= 1;
						array_ordered_remove_by_index(*text_buffer, cursor);
					}
					if cursor > 0 {
						array_ordered_remove_by_index(*text_buffer, cursor - 1);
						cursor -= 1;
					}
					should_render = true;
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
						TTF_SetFontSize(font, next_size);
						should_render = true;
					}
				} else {
					scroll -= event.wheel.integer_y * SCROLL_MOD;
					should_render = true;
				}
				case .TEXT_INPUT;
				text := to_string(event.text.text);
				for byte: text {
					array_insert_at(*text_buffer, byte, xx cursor);
					cursor += 1;
				}
				should_render = true;
				case .MOUSE_BUTTON_DOWN;
				cursor = clamp(point_to_cursor(*ctx, event.mouse.x, event.mouse.y), 0, text_buffer.count);
				should_render = true;
			};
		}
		if should_render {
			calculate_vislines(*ctx);
			render(*ctx);
		}
		reset_temporary_storage();
	}
}

#import "Unicode";
#import,file "sdl3.jai";
#import "Basic";
#import "String";
#import "Text_File_Handler";