#import "Basic";
#import "String";
#import,file "sdl3.jai";
#load "theme.jai";

enable_render_fan :: true;
cool :: true;

Acme_Element :: struct {
	using buffer: Text_Buffer;
	height: float;
};

Acme_Indent :: struct {
        rows: [..]struct {
                width: float;
                columns: [..]Acme_Element;
        };
        selected_row: s64;
        selected_col: s64;
};

Text_Buffer :: struct {
        text: string;
        cursor: s64;
};

Ctx :: struct {
        window: *SDL_Window;
        renderer: *SDL_Renderer;
        font: *TTF_Font;
        using win_size : struct {
                width : u32;
                height : u32;
        };
	is_ctrl_held: bool = false;
        is_running: bool = false;
	should_render: bool = true;
        acme: Acme_Indent;
};

font_path :: "/usr/share/fonts/TTF/liberation/LiberationMono-Regular.ttf";

render_text :: (using ctx: *Ctx, x: float, y: float, color: SDL_Color, text: string) -> (s32, s32) {
        surface: *SDL_Surface = TTF_RenderText_Blended(font, text.data, xx text.count, color);
	if surface == null {
		print("Can't render text on surface: %\n", sdl_get_error());
		return 0, 0;
	}
	defer SDL_DestroySurface(surface);
	texture: *SDL_Texture = SDL_CreateTextureFromSurface(renderer, surface);
	if texture == null {
		print("Can't convert surface to texture: %\n", sdl_get_error());
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
		print("Can't blit texture: %\n", sdl_get_error());
		return 0, 0;
	}
	return texture.w, texture.h;
}

render_text_wrapped :: (using ctx: *Ctx, x: float, y: float, color: SDL_Color, text: string, wrap_width: s32 = 0, caller_loc := #caller_location) -> (s32, s32) {
	font_height := TTF_GetFontSize(font);
	assert(font_height > 0.0, "Can't get font size.");
	while text.count > 0 {
		ok, line_width, line_text_length := sdl_measure_string(font, text, wrap_width);
		if !ok {
			print("Error on rendering wrapped text: %\n", sdl_get_error());
			return 0, 0;
		}
		if line_text_length <= 0 then line_text_length = 1; // At least draw it partially.
		text_w, text_h := render_text(ctx, x, y, color, slice(text, 0, xx line_text_length));
		if text.count == xx line_text_length {
			return line_width, xx y;
		}
		advance(*text, xx line_text_length);
		y += font_height;
	}
	return 0, xx y;
}

postprocessing :: (using ctx: *Ctx) {
        y : float = 0;
        panel_height :: 4.0;
        while xx y < height {
                fill_rect(renderer, .{0, y, xx width, panel_height}, .{0x10, 0x10, 0x10, 0x20});
                y += panel_height * 2;
        }
}

append_text :: (using buffer: *Text_Buffer, str: string, position: s64) {
	// TODO(c4llv07e): This should be done with dynamic array as a string, but I am not sure what's the best way to do it in jai.
	// Maybe I should check modules, maybe there's already implemented such structure.
	before := text;
	before.count = position;
	after := text;
	after.count -= position;
	after.data += position;
	new_text := sprint("%1%2%3", before, str, after);
	free(text);
	text = new_text;
}

delete_char :: (using buffer: *Text_Buffer, position: s64) {
	memcpy(text.data + position, text.data + position + 1, text.count - position - 1);
	text.count -= 1;
}

recalculate_sizes :: (using ctx: *Ctx, new_width: s32, new_height: s32) {
	dw := (cast(float)new_width) / width;
	dh := (cast(float)new_height) / height;
	for *row, row_index: acme.rows {
		for *col, col_index: row.columns {
			col.height *= dh;
		}
		row.width *= dw;
	}
	width = xx new_width;
	height = xx new_height;
}

wrap_text :: (using ctx: *Ctx, text: string, wrap_width: s32) -> (s32, s32) {
	y: s32 = 0;
	font_height := TTF_GetFontSize(font);
	assert(font_height > 0.0, "We can't get font size for some reason.");
	while text.count > 0 {
		ok, line_width, line_text_length := sdl_measure_string(font, text, wrap_width);
		if !ok {
			print("Some error on measuring text: %\n", sdl_get_error());
			return 0, y;
		}
		if line_text_length <= 0 then line_text_length = 1; // To match render_text_wrapped.
		if text.count == xx line_text_length {
			return line_width, y;
		}
		advance(*text, cast(s64)line_text_length);
		y += xx font_height;
	}
	// unreachable.
	return 0, y;
}

#if enable_render_fan {
	render_fan_state : u8 = 0;
}

render_fan :: (using ctx: *Ctx) {
#if enable_render_fan {
		render_fan_cell_size :: 0x10;
		fill_rect(renderer, .{0, 0, render_fan_cell_size * 2, render_fan_cell_size * 2}, .{0x40, 0x40, 0x40, 0xff});
		fill_rect(renderer, .{
				  xx ((render_fan_state / 2) * render_fan_cell_size),
				  xx ((render_fan_state % 2) * render_fan_cell_size),
				  render_fan_cell_size, render_fan_cell_size
			  }, .{0x60, 0x60, 0x60, 0xff});
		render_fan_state = (render_fan_state + 1) % 4;
	}
}

render :: (using ctx: *Ctx) {
	if !should_render return;
	sdl_set_color(renderer, background_color);
	SDL_RenderClear(renderer);
	x: float = 0;
	y: float = 0;
	font_height:= TTF_GetFontSize(font);
	assert(font_height > 0.0, "Can't get font size.");
	for row, row_index: acme.rows {
		for col, col_index: row.columns {
			is_selected := row_index == acme.selected_row && col_index == acme.selected_col;
			border_color : SDL_Color = ifx is_selected {
				SDL_Color.{0x00, 0xff, 0xff, 0xff};
			} else {
				SDL_Color.{0xff, 0x00, 0x00, 0xff};
			}
			color := ifx is_selected {
				text_color;
			} else {
				shadowed_text_color;
			}
			clip_rect := SDL_Rect.{xx SDL_floorf(x), xx SDL_floorf(y), xx SDL_ceilf(row.width), xx SDL_ceilf(col.height)};
			SDL_SetRenderClipRect(renderer, *clip_rect);
			draw_rect_lines(renderer, .{x, y, row.width, col.height}, border_color);
			// print("rect = %\n", SDL_FRect.{x, y, row.width, col.height});
			render_text_wrapped(ctx, x, y, color, col.text, xx row.width);
			line_x, line_y := wrap_text(ctx, slice(col.text, 0, col.cursor), xx row.width);
			fill_rect(renderer, .{x + line_x, y + line_y, 4, xx font_height}, .{0x99, 0x00, 0x00, 0xff});
			y += col.height;
		}
		x += row.width;
		y = 0;
	}
	SDL_SetRenderClipRect(renderer, null);
#if cool {
		postprocessing(ctx);
	}
	render_fan(ctx);
	SDL_RenderPresent(renderer);
	should_render = false;
}

find_acme_on_point :: (using ctx: *Ctx, point: SDL_FPoint) -> (s64, s64, bool) {
	x := 0.0;
	for row, row_index: acme.rows {
		defer x += row.width;
		y := 0.0;
		if (point.x < x) || (point.x >= x + row.width) continue;
		for col, col_index: row.columns {
			defer y += col.height;
			if (point.y >= y) && (point.y <= y + col.height) {
				return row_index, col_index, true;
			}
		}
	}
	return 0, 0, false;
}

main :: () {
        using ctx := Ctx.{
                width = 800,
                height = 600,
        };
        if !SDL_Init(.VIDEO) {
                print("Can't init SDL: %\n", sdl_get_error());
        }
        if !SDL_CreateWindowAndRenderer("editor", ctx.width, ctx.height, .RESIZABLE, *ctx.window, *ctx.renderer) {
                print("Can't create SDL window: %\n", sdl_get_error());
        }
        if !SDL_SetRenderDrawBlendMode(renderer, .BLEND) { 
                print("Can't set blend mode to blending: %\n", sdl_get_error());
        }
	SDL_StartTextInput(window);
        if !TTF_Init() {
                print("Can't init SDL_TTF: %\n", sdl_get_error());
        }
	font = TTF_OpenFont(font_path.data, 16);
        if font == null {
                print("Can't load font at %: %\n", font_path, sdl_get_error());
        }
        array_add(*acme.rows, .{
                          width = xx (width / 3 * 2),
                  });
        array_add(*acme.rows[0].columns, .{
                          text = copy_string("Hello world"),
                          height = xx (height / 2),
                  });
        array_add(*acme.rows[0].columns, .{
                          text = copy_string("Second panel"),
                          height = xx (height / 2),
                  });
	array_add(*acme.rows, .{
			  width = xx (width / 3)
		  });
	array_add(*acme.rows[1].columns, .{
			  text = copy_string("Third panel"),
			  height = xx height,
		  });
	print("Entering main loop...\n");
        is_running = true;
        event: SDL_Event;
        while is_running {
		selected_column :: () -> *Acme_Element #expand {
			return *(acme.rows[acme.selected_row].columns[acme.selected_col]);
		}
		selected_buffer :: () -> *Text_Buffer #expand {
			return *(acme.rows[acme.selected_row].columns[acme.selected_col].buffer);
		}
                while event_handler := SDL_PollEvent(*event) {
                        if event.type == {
                                case .QUIT;
                                is_running = false;
                                break event_handler;
                                case .KEY_DOWN;
                                if event.key.scancode == {
					case .I;
                                        if event.key.mod & .CTRL {
                                                acme.selected_col = cast(s32)((acme.selected_col + 1) % acme.rows[acme.selected_row].columns.count);
						should_render = true;
                                        }
					case .LEFT;
					if selected_buffer().cursor > 0 {
						selected_buffer().cursor -= 1;
						should_render = true;
					}
					case .RIGHT;
					if selected_buffer().cursor < selected_buffer().text.count {
						selected_buffer().cursor += 1;
						should_render = true;
					}
					case .BACKSPACE;
					if selected_buffer().cursor > 0 {
						delete_char(selected_buffer(), xx selected_buffer().cursor - 1);
						selected_buffer().cursor -= 1;
						should_render = true;
					}
					case .LCTRL; #through;
					case .RCTRL;
					is_ctrl_held = event.key.down;
                                }
				case .WINDOW_EXPOSED;
				should_render = true;
				case .WINDOW_PIXEL_SIZE_CHANGED;
				recalculate_sizes(*ctx, event.window.data1, event.window.data2);
				should_render = true;
                                case .KEY_UP;
				if event.key.scancode == {
					case .LCTRL; #through;
					case .RCTRL;
					is_ctrl_held = event.key.down;
				}
				case .TEXT_INPUT;
				text := to_string(event.text.text);
				append_text(selected_buffer(), text, xx selected_buffer().cursor);
				selected_buffer().cursor += text.count;
				should_render = true;
				case .MOUSE_BUTTON_DOWN;
				row, col, ok := find_acme_on_point(*ctx, .{event.mouse.x, event.mouse.y});
				if ok {
					acme.selected_row = row;
					acme.selected_col = col;
					should_render = true;
				}
				case .MOUSE_WHEEL;
				if (is_ctrl_held) {
					font_size := TTF_GetFontSize(font);
					next_size := font_size + event.wheel.integer_y;
					if (next_size >= 1.0) {
						TTF_SetFontSize(font, next_size);
						should_render = true;
					}
				}
                        }
                }
		render(*ctx);
        }
}
