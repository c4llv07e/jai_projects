// Simple Text Editor

font_path :: "/usr/share/fonts/TTF/liberation/LiberationMono-Regular.ttf";
SCROLL_MOD :: 24;

Visual_Line :: struct {
	start_byte_offset: s64;
	length: s64;
}

Ctx :: struct {
	window: *SDL_Window;
	renderer: *SDL_Renderer;
	font: *TTF_Font;
	space_texture: *SDL_Texture;
	tab_texture: *SDL_Texture;
	window_width, window_height: s64;
	cursor: s64;
	text_buffer: [..]u8;
	scroll: float32;
	line_number_width: float32;
	visual_lines: [..]Visual_Line;
	should_render: bool;
	is_ctrl_held: bool;
	tab_width: s32 = 8; // Per spaces
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
	digit_width := sdl_char_width(font, #char "9"); // the most wide one. Maybe one day I will calculate max width of all digits.
	for 0..(1024*10) {
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
		adv = measure_char_or_tab(ctx, font, cp);
		left_space -= adv;
		if left_space <= 0 && (before_char.data - line_begin.data > 0) {
			array_add(*visual_lines, .{line_begin.data - text_buffer.data, before_char.data - line_begin.data});
			line_begin = before_char;
			sv = before_char;
			left_space = initial_window_width;
			continue;
		}
	}
	assert(!hard_locked, "Hard locked at generating visual lines");
	array_add(*visual_lines, .{line_begin.data - text_buffer.data, sv.data - line_begin.data});
	line_number_width = (1 + SDL_ceilf(SDL_log10f(xx (visual_lines.count + 1)))) * digit_width;
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
			offset_x, offset_y := draw_text(renderer, font, x, y, color, slice(sv, 0, match));
			advance(*sv, match);
			x += offset_x;
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
				log_error("% is in special_chars, but not in switch case to handle them.");
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

measure_string_with_tab :: (using,except(font,width) ctx: *Ctx, font: *TTF_Font, text: string, max_width: s32 = 0) -> width: s32, length: u64 {
	width: s32 = 0;
	length: u64 = 0;
	if !text then return 0, 0;
	for :utf8_iter text {
		ch_width := measure_char_or_tab(ctx, font, it);
		if max_width != 0 && (width + ch_width > max_width) {
			return width, length;
		}
		width += ch_width;
		length += trailingBytesForUTF8[it] + 1;
	}
	return width, length;
}

draw_on_left :: (using ctx: *Ctx, y: float32, text: string, color: SDL_Color = .{0xe3, 0xe3, 0xe3, 0xff}) {
	ok, width := sdl_measure_string(font, text);
	draw_text(renderer, font, xx (window_width - width), y, color, text);
}

render_frame_count := 0;
render :: (using ctx: *Ctx) {
	drawed: s64 = 0;
	if !should_render {
		SDL_Delay(1);
		return;
	}
	font_height := TTF_GetFontHeight(font);
	sdl_set_color(renderer, .{0x20, 0x20, 0x20, 0xff});
	SDL_RenderClear(renderer);
	draw_on_left(ctx, 0, tprint("%", render_frame_count));
	//draw_on_left(ctx, xx (font_height), tprint("visline count = %", visual_lines.count));
	//draw_on_left(ctx, xx (font_height * 2), tprint("%", text_buffer));
	for visual_lines {
		if (xx ((it_index + 1) * font_height) - scroll) < 0 then continue;
		if (xx (it_index * font_height) - scroll) > xx window_height then break;
		line: string = ---;
		line.data = *text_buffer.data[it.start_byte_offset];
		line.count = it.length;
		draw_text(renderer, font, 0, xx (it_index * font_height) - scroll, .{0x43, 0x83, 0x43, 0xff}, tprint("%", it_index + 1));
		if line.count <= 0 {
			continue;
		}
		line_width := measure_string_with_tab(ctx, font, line);
		draw_rect_lines(renderer, .{line_number_width, - scroll + xx (it_index * font_height), xx line_width, xx font_height}, .{0xff, 0x00, 0x00, 0xff});
		draw_fancy_text(ctx, line_number_width, - scroll + xx (it_index * font_height), line);
		drawed += 1;
	}
	draw_on_left(ctx, xx font_height, tprint("%", drawed));
	if visual_lines { // Cursor
		cursor_visline_index := offset_to_visline_index(ctx, cursor);
		cursor_visline := visual_lines[cursor_visline_index];
		before_cursor_string_length := (cursor - cursor_visline.start_byte_offset);
		width: s32;
		if before_cursor_string_length > 0
			width = measure_string_with_tab(ctx, font, slice(cast(string)text_buffer, cursor_visline.start_byte_offset, before_cursor_string_length));
		else
			width = 0;
		fill_rect(renderer, .{line_number_width + xx width, xx ((cursor_visline_index * font_height) - scroll), 2, xx font_height}, .{0x00, 0xff, 0x00, 0xff});
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

point_to_cursor :: (using ctx: *Ctx, point_x: float32, point_y: float32) -> s64 {
	y := 0.0;
	font_height := TTF_GetFontHeight(font);
	sv := cast(string)text_buffer;
	point_y += scroll;
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

main :: () {
	using ctx := Ctx.{};
	initial_width :: 800;
	initial_height :: 600;
	args := get_command_line_arguments();
	check_sdl(SDL_Init(.VIDEO), "Can't init SDL");
	check_sdl(TTF_Init(), "Can't init font engine");
	check_sdl(SDL_CreateWindowAndRenderer("ste", initial_width, initial_height, .RESIZABLE, *window, *renderer), "Can't create SDL output");
	font = TTF_OpenFont(font_path, 16);
	if args.count > 1 {
		content, ok := read_entire_file(args[1], zero_terminated = true);
		if !ok {
			log_error("Can't open file %", args[1]);
		} else {
			array_add(*text_buffer, ..cast([]u8)content);
		}
	}
	event: SDL_Event;
	create_textures(*ctx);
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
					case .TAB;
					array_insert_at(*text_buffer, #char "\t", cursor);
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

#import "File";
Math :: #import "Math";
#import,file "Unicode.jai";
#import,file "sdl3.jai";
#import "Basic";
#import "String";
#import "Text_File_Handler";