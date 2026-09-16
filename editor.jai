#import "Basic";
#import "String";
#import,file "sdl3.jai";
#import,file "theme.jai";

cool :: true;

Acme_Indent :: struct {
        rows: [..]struct {
                width: float;
                columns: [..]struct {
                        using buffer: Text_Buffer;
                        height: float;
                };
        };
        selected_row: s32;
        selected_col: s32;
};

Text_Buffer :: struct {
        text: string;
        cursor: s64;
};

Ctx :: struct {
        window: *void;
        renderer: *void;
        font: *TTF_Font;
	font_height: u32;
        using win_size : struct {
                width : u32;
                height : u32;
        };
        is_running: bool;
        acme: Acme_Indent;
};

font_path :: "/usr/share/fonts/TTF/liberation/LiberationMono-Regular.ttf";

substring :: (s: string, n: s64) -> string {
	res : string = s;
	res.count = n;
	return res;
}

render_text :: (using ctx: *Ctx, x: float, y: float, color: SDL_Color, text: string, wrap_width: s32 = 0) -> (s32, s32) {
        surface: *SDL_Surface;
	if wrap_width > 0 {
		surface = TTF_RenderText_Blended_Wrapped(font, text.data, xx text.count, color, wrap_width);
	} else {
		surface = TTF_RenderText_Blended(font, text.data, xx text.count, color);
	}
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

rect_line :: (using ctx: *Ctx, rect: SDL_FRect, color: SDL_Color) {
        SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
        SDL_RenderRect(renderer, *rect);
}

fill_rect :: (using ctx: *Ctx, rect :SDL_FRect, color: SDL_Color) {
        SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
        SDL_RenderFillRect(renderer, *rect);
}

postprocessing :: (using ctx: *Ctx) {
        y : float = 0;
        panel_height :: 2.0;
        while xx y < height {
                fill_rect(ctx, .{0, y, xx width, panel_height}, .{0x10, 0x10, 0x10, 0x50});
                y += panel_height * 2;
        }
}

append_text :: (using buffer: *Text_Buffer, str: string, position: s32) {
	before := text;
	before.count = position;
	after := text;
	after.count -= position;
	after.data += position;
	text = sprint("%1%2%3", before, str, after);
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

sdl_measure_string :: (font: *TTF_Font, text: string, max_width: s32) -> (bool, s32, u64) {
	measured_width: s32;
	measured_length: u64;
	res := TTF_MeasureString(font, text.data, cast(u64)text.count, max_width, *measured_width, *measured_length);
	return res, measured_width, measured_length;
}

wrap_text :: (using ctx: *Ctx, text: string, wrap_width: s32) -> (s32, s32) {
	y: s32 = 0;
	while true {
		if text.count <= 0 return 0, y;
		ok, line_width, line_text_length := sdl_measure_string(font, text, wrap_width);
		if !ok {
			print("Some error on measuring text: %\n", sdl_get_error());
			return 0, y;
		}
		if text.count == xx line_text_length {
			return line_width, y;
		}
		advance(*text, cast(s64)line_text_length);
		y += xx font_height;
	}
	// unreachable.
	return 0, 0;
}

main :: () {
        using ctx := Ctx.{
                width = 800,
                height = 600,
		font_height = 24,
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
        font = TTF_OpenFont(font_path.data, xx font_height);
        if font == null {
                print("Can't load font at %: %\n", font_path, sdl_get_error());
        }
        array_add(*acme.rows, .{
                          width = xx width,
                  });
        array_add(*acme.rows[0].columns, .{
                          text = "Hello world",
                          height = xx (height / 2),
                  });
        array_add(*acme.rows[0].columns, .{
                          text = "Second panel",
                          height = xx (height / 2),
                  });
        print("Entering main loop...\n");
        is_running = true;
        event: SDL_Event;
	text_width : s32 = 15;
        while is_running {
		selected_buffer :: () -> *Text_Buffer #expand {
			return *(acme.rows[acme.selected_row].columns[acme.selected_col].buffer);
		}
                while event_handler := SDL_PollEvent(*event) {
                        if event.type == {
                                case .QUIT;
                                is_running = false;
                                break event_handler;
                                case .KEY_DOWN;
                                if event.key.scancode == .I {
                                        if event.key.mod & .CTRL {
                                                acme.selected_col = cast(s32)((acme.selected_col + 1) % acme.rows[acme.selected_row].columns.count);
                                        }
                                }
				case .WINDOW_PIXEL_SIZE_CHANGED;
				recalculate_sizes(*ctx, event.window.data1, event.window.data2);
                                case .KEY_UP;
				case .TEXT_INPUT;
				text := to_string(event.text.text);
				append_text(selected_buffer(), text, 0);
				case .MOUSE_WHEEL;
				text_width += event.wheel.integer_y;
                        }
                }
                sdl_set_color(renderer, background_color);
                SDL_RenderClear(renderer);
                x: float = 0;
                y: float = 0;
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
				rect_line(*ctx, .{x, y, row.width, col.height}, border_color);
                                render_text(*ctx, x, y, color, col.text, xx row.width);
				line_x, line_y := wrap_text(*ctx, col.text, xx row.width);
				fill_rect(*ctx, .{x + line_x, y + line_y, 4, xx font_height}, .{0x99, 0x00, 0x00, 0xff});
                                y += col.height;
                        }
                        x += row.width;
                        y = 0;
                }
#if cool {
                        postprocessing(*ctx);
                }
		SDL_RenderPresent(renderer);
        }
}
