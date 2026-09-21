#import,file "sdl3.jai";
#import,file "theme.jai";
using Basic :: #import "Basic" () (MEMORY_DEBUGGER = false);
#import "File";
#import "File_Utilities";
#import "String";

DEBUG :: true;
SCROLL_MOD :: 32.0;
font_path :: "/usr/share/fonts/TTF/liberation/LiberationMono-Regular.ttf";
padding :: 1.1;
pathbar_height :: 24.0;

Dir_Entry :: struct {
	name: string;
	filesize: s64;
	filetype: enum {
		FILE;
		DIRECTORY;
	};
};

Panel :: struct {
	rect: SDL_FRect;
	path: Path;
	icon_size: s32 = 32;
	dirents: [..]Dir_Entry;
	scroll: float32 = 0.0;
};

DebugText :: struct {
	text: string; // Should be allocated in arena allocator, but whatever.
	rect: SDL_FRect;
	color: SDL_Color;
}

Ctx :: struct {
	window: *SDL_Window;
	renderer: *SDL_Renderer;
	font: *TTF_Font;
	should_render: bool = true;
	is_running: bool = true;
	is_ctrl_held: bool = false;
	panels: [..]Panel;
#if DEBUG {
		debug_text: [..]DebugText; // Must set allocator to arena
	}
}

print_debug :: (using ctx: *Ctx, text: string, rect: SDL_FRect, color: SDL_Color) {
#if DEBUG {
		array_add(*debug_text, .{text, rect, color},, allocator=temp);
	}
}

substring :: (s: string, n: s64) -> string {
	assert(s.count >= n);
	res : string = s;
	res.count = n;
	return res;
}

check_sdl :: (status: bool, msg := "Error on calling sdl function", caller_loc := #caller_location) #expand {
	if (!status) {
		log("%: %: %\n", caller_loc, msg, sdl_get_error(), flags=.ERROR);
		exit(-1);
	}
}

render :: (using ctx: *Ctx) {
	if !should_render {
		SDL_Delay(1);
		return;
	}
	sdl_set_color(renderer, .{0x20, 0x20, 0x20, 0xff});
	SDL_RenderClear(renderer);
	for panel: panels {
		panel_render(ctx, *panel);
	}
#if DEBUG {
		for debug_text {
			render_text(ctx, it.rect.x, it.rect.y, it.color, it.text);
		}
		array_free(debug_text);
	}
	SDL_RenderPresent(renderer);
	should_render = false;
}

render_text :: (using ctx: *Ctx, x: float, y: float, color: SDL_Color, text: string) -> (s32, s32) {
	if text.count <= 0 return 0, 0;
        surface: *SDL_Surface = TTF_RenderText_Blended(font, text.data, xx text.count, color);
	if surface == null {
		log("Can't render text on surface: %\n", sdl_get_error(), flags=.WARNING);
		return 0, 0;
	}
	defer SDL_DestroySurface(surface);
	texture: *SDL_Texture = SDL_CreateTextureFromSurface(renderer, surface);
	if texture == null {
		log("Can't convert surface to texture: %\n", sdl_get_error(), flags=.WARNING);
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
		log("Can't blit texture: %\n", sdl_get_error(), flags=.WARNING);
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
			log("Error on rendering wrapped text: %\n", sdl_get_error(), flags=.WARNING);
			return 0, 0;
		}
		if line_text_length <= 0 then line_text_length = 1; // At least draw it partially.
		text_w, text_h := render_text(ctx, x, y, color, substring(text, xx line_text_length));
		if text.count == xx line_text_length {
			return line_width, xx y;
		}
		advance(*text, xx line_text_length);
		y += font_height;
	}
	return 0, xx y;
}

get_panel_entry_position :: (using ctx: *Ctx, using panel: *Panel, entry_index: s64 = 0) -> SDL_FRect {
	width, height: s32;
	SDL_GetWindowSizeInPixels(window, *width, *height);
	return .{
		xx (rect.x + icon_size / 5),
		xx ((icon_size * padding / 10.0) + rect.y + (entry_index * (icon_size * padding))) + panel.scroll + pathbar_height,
		xx (width - (icon_size / 2.5)),
		xx icon_size
	};
}

get_panel_pathbar_rect :: (using ctx: *Ctx, using panel: *Panel) -> SDL_FRect {
	font_size := TTF_GetFontSize(font);
	return .{
		xx panel.rect.x, xx panel.rect.y,
		xx panel.rect.w, font_size,
	};
}

get_pathbar_text_rect :: (using ctx: *Ctx, using panel: *Panel) -> SDL_FRect {
	pathbar_rect := get_panel_pathbar_rect(ctx, panel);
	return pathbar_rect + .{24, 0, -24, 0};
}

get_pathbar_up_button_rect :: (using ctx: *Ctx, using panel: *Panel) -> SDL_FRect {
	pathbar_rect := get_panel_pathbar_rect(ctx, panel);
	font_size := TTF_GetFontSize(font);
	return .{pathbar_rect.x, pathbar_rect.y, font_size, font_size};
}

get_dirents_rect :: (using ctx: *Ctx, using panel: *Panel) -> SDL_FRect {
	pathbar_rect := get_panel_pathbar_rect(ctx, panel);
	return SDL_FRect.{
		x = panel.rect.x,
		y = panel.rect.y + pathbar_rect.h,
		w = panel.rect.w,
		h = panel.rect.h
	};
}

panel_render :: (using ctx: *Ctx, using panel: *Panel) {
	draw_rect_lines(renderer, panel.rect, .{0xff, 0x00, 0x00, 0xff});
	x := icon_size * padding - icon_size;
	y := icon_size * padding - icon_size;
	font_size := TTF_GetFontSize(font);
	pathbar_rect := get_panel_pathbar_rect(ctx, panel);
	pathbar_text_rect := get_pathbar_text_rect(ctx, panel);
	pathbar_up_icon_rect := get_pathbar_up_button_rect(ctx, panel);
	path_str := path_to_string(path,, allocator=temp);
	SDL_SetRenderClipRectFloat(renderer, *pathbar_rect);
	fill_rect(renderer, pathbar_rect, pathbar_background_color);
	render_text(ctx, pathbar_text_rect.x, pathbar_text_rect.y, pathbar_color, path_str);
	draw_rect_lines(renderer, pathbar_up_icon_rect + .{2, 2, -4, -4}, .{0xff, 0x00, 0x00, 0xff});
	free(path_str,, allocator=temp);
	dirents_rect := get_dirents_rect(ctx, panel);
	SDL_SetRenderClipRectFloat(renderer, *dirents_rect);
	for dirent, dirent_index: dirents {
		name_color :: SDL_Color.{0xe3, 0xe3, 0xe3, 0xff};
		color : SDL_Color = ifx dirent.filetype == .FILE
			then SDL_Color.{0xff, 0x00, 0x00, 0xff}
		else SDL_Color.{0x00, 0x00, 0xff, 0xff};
		render_rect := get_panel_entry_position(ctx, panel, dirent_index);
		draw_rect_lines(renderer, render_rect, color);
		surface := TTF_RenderText_Blended(font, dirent.name.data, xx dirent.name.count, name_color);
		assert(surface != null, "Can't blend file name!");
		defer SDL_DestroySurface(surface);
		texture := SDL_CreateTextureFromSurface(renderer, surface);
		assert(texture != null, "Can't convert text surface to texture!");
		defer SDL_DestroyTexture(texture);
		proportions : float32 = render_rect.h / texture.h;
		dstrect := SDL_FRect.{
			render_rect.x, render_rect.y,
			xx texture.w * proportions, render_rect.h,
		};
		SDL_RenderTexture(renderer, texture, null, *dstrect);
		x += icon_size * padding;
		if x + icon_size >= rect.w {
			x = icon_size * padding - icon_size;
			y += icon_size * padding;
		}
	}
	SDL_SetRenderClipRectFloat(renderer, null);
}

Ctx_with_panel :: struct {
	ctx: *Ctx;
	panel: *Panel;
};

update_panel_file :: (info: *File_Visit_Info, using user_data: *Ctx_with_panel) {
	using ctx;
	using panel;
	array_add(*dirents, .{name=copy_string(info.short_name), filesize=0, filetype=(ifx info.is_directory then .DIRECTORY else .FILE)});
}

panel_update :: (using ctx: *Ctx, using panel: *Panel) {
	user_info := Ctx_with_panel.{ctx, panel};
	new_path := copy_to_permanent(reduce_path(path));
	free_permanent(path);
	path = new_path;
	for panel.dirents {
		free(it.name);
	}
	panel.scroll = 0;
	panel.dirents.count = 0;
	path_str: string;
	path_str = path_to_string(path,, allocator=temp);
	ok := visit_files(path_str, false, *user_info, update_panel_file, visit_files = true, visit_directories = true);
	if !ok {
		log("Can't list files in dir \"%\"\n", path_str, flags=.WARNING);
	}
	should_render = true;
}

is_at_cwd_path :: (path: Path) -> bool {
	return path.words.count == 1 && equal(path.words[0], ".");
}

go_up_dir :: (using ctx: *Ctx, using panel: *Panel) {
#if DEBUG {
		assert(is_absolute_path(path_to_string(path,, allocator=temp)), "Somehow we get relative path in panel path. It should not happen.");
	}
	if path.words.count > 0 {
		free(path.words[path.words.count - 1]);
		path.words.count -= 1;
		panel_update(ctx, panel);
		should_render = true;
	}
}

try_select_dirent_on_point :: (using ctx: *Ctx, panel: *Panel, point: SDL_FPoint) -> bool {
	using,only(icon_size,dirents,rect) panel;
	dirents_rect := get_dirents_rect(ctx, panel);
	for dirent, dirent_index: dirents {
		dirent_rect := get_panel_entry_position(ctx, panel, dirent_index);
		visible_rect: SDL_FRect;
		is_visible := SDL_GetRectIntersectionFloat(*dirents_rect, *dirent_rect, *visible_rect);
		if !is_visible continue;
		if point.x >= visible_rect.x && point.x <= visible_rect.x + visible_rect.w && point.y >= visible_rect.y && point.y <= visible_rect.y + visible_rect.h {
			if #complete dirent.filetype == {
				case .FILE;
				log("todo: open file %\n", dirent.name);
				case .DIRECTORY;
				array_add(*panel.path.words, copy_string(dirent.name));
				panel_update(ctx, panel);
				should_render = true;
				case;
				log("Unknown filetype clicked: %\n", dirent.filetype, flags=.WARNING);
			}
			return true;
		}
	}
	return false;
}

check_buttons_hit :: (using ctx: *Ctx, using panel: *Panel, point: SDL_FPoint) -> bool {
	up_button_rect := get_pathbar_up_button_rect(ctx, panel);
	if is_intersecting(up_button_rect, point) {
		go_up_dir(ctx, panel);
	}
	return false;
}

main :: () {
	init_width :: 800;
	init_height :: 600;
	using ctx := Ctx.{
	};
#if DEBUG {
		debug_text.allocator = temp;
	}
	path := copy_to_permanent(parse_path(get_absolute_path(".")));
	array_add(*ctx.panels, .{rect=.{x=0, y=0, w=init_width, h=init_height}, path=path});
	sdl_debug_version_info();
	check_sdl(SDL_Init(.VIDEO), "Can't init SDL");
	check_sdl(SDL_CreateWindowAndRenderer("file explorer", 800, 600, .RESIZABLE, *window, *renderer), "Can't create window");
	check_sdl(TTF_Init());
	font = TTF_OpenFont(font_path, 24);
	if !font {
		log("Can't load font: %\n", sdl_get_error(), flags=.ERROR);
		exit(-1);
	}
	panel_update(*ctx, *ctx.panels[0]);
	event: SDL_Event;
	while main_loop := is_running {
		render(*ctx);
		// SDL guys break wayland resizing once again (3.5.0 ver), do only partial retained renderer.
		// TODO(c4llv07e): Write a bug report for SDL guys.
		event_poller_function :: #ifx false SDL_WaitEvent else SDL_PollEvent;
		while event_poller_function(*event) {
			if event.type == {
				case .QUIT;
				is_running = false;
				break main_loop;
				case .WINDOW_EXPOSED; #through;
				case .WINDOW_RESIZED; #through;
				case .WINDOW_MOVED; #through;
				case .WINDOW_SHOWN; #through;
				case .WINDOW_PIXEL_SIZE_CHANGED;
				should_render = true;
				case .MOUSE_BUTTON_DOWN;
				if event.mouse.button == {
					case .LEFT;
					if try_select_dirent_on_point(*ctx, *ctx.panels[0], .{event.mouse.x, event.mouse.y}) continue;
					if check_buttons_hit(*ctx, *ctx.panels[0], .{event.mouse.x, event.mouse.y}) continue;
					case .X1;
					go_up_dir(*ctx, *ctx.panels[0]);
				}
				case .MOUSE_WHEEL;
				if is_ctrl_held {
					if ctx.panels[0].icon_size > 1 {
						ctx.panels[0].icon_size += event.wheel.integer_y;
						should_render = true;
					}
				} else {
					ctx.panels[0].scroll += event.wheel.integer_y * SCROLL_MOD;
					should_render = true;
				}
                                case .KEY_DOWN;
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
			}
		}
	}
#if Basic.MEMORY_DEBUGGER {
		array_free(path.words);
		for ctx.panels {
			array_free(it.path.words);
		}
		array_free(ctx.panels);
		report := make_leak_report();
		for report.sorted_summaries {
			log("** Summary %: **\n%\n", it_index, <<it);
		}
		log_leak_report(report);
	}
}