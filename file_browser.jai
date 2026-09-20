#import,file "sdl3.jai";
using Basic :: #import "Basic" () (MEMORY_DEBUGGER = false);
#import "File";
#import "File_Utilities";
#import "String";

DEBUG :: true;
SCROLL_MOD :: 32.0;
font_path :: "/usr/share/fonts/TTF/liberation/LiberationMono-Regular.ttf";
padding :: 1.1;

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
	icon_size: s32 = 48;
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
		print("%: %: %\n", caller_loc, msg, sdl_get_error());
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
		xx ((icon_size * padding / 10.0) + rect.y + (entry_index * (icon_size * padding))) + panel.scroll,
		xx (width - (icon_size / 2.5)),
		xx icon_size
	};
}

panel_render :: (using ctx: *Ctx, using panel: *Panel) {
	rect_line(renderer, panel.rect, .{0xff, 0x00, 0x00, 0xff});
	x := icon_size * padding - icon_size;
	y := icon_size * padding - icon_size;
	font_size := TTF_GetFontSize(font);
	for dirent, dirent_index: dirents {
		name_color :: SDL_Color.{0xe3, 0xe3, 0xe3, 0xff};
		color : SDL_Color = ifx dirent.filetype == .FILE
			then SDL_Color.{0xff, 0x00, 0x00, 0xff}
		else SDL_Color.{0x00, 0x00, 0xff, 0xff};
		render_rect := get_panel_entry_position(ctx, panel, dirent_index);
		rect_line(renderer, render_rect, color);
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
	for panel.dirents {
		free(it.name);
	}
	panel.scroll = 0;
	panel.dirents.count = 0;
	path_str: string;
	if path.words.count == 0
		path_str = ".";
	else {
		path_str = path_to_string(path,, allocator=temp);
	}
	ok := visit_files(path_str, false, *user_info, update_panel_file, visit_files = true, visit_directories = true);
	if !ok {
		print("Can't list files in dir \"%\"\n", path_str);
	}
	should_render = true;
}

select_dirent_on_point :: (using ctx: *Ctx, panel: *Panel, point: SDL_FPoint) {
	using,only(icon_size,dirents,rect) panel;
	for dirent, dirent_index: dirents {
		render_rect := get_panel_entry_position(ctx, panel, dirent_index);
		if point.x >= render_rect.x && point.x <= render_rect.x + render_rect.w && point.y >= render_rect.y && point.y <= render_rect.y + render_rect.h {
			if #complete dirent.filetype == {
				case .FILE;
				print("todo: open file %\n", dirent.name);
				case .DIRECTORY;
				array_add(*panel.path.words, copy_string(dirent.name));
				panel_update(ctx, panel);
				should_render = true;
				case;
				print("Unknown filetype clicked: %\n", dirent.filetype);
			}
			break;
		}
	}
}

is_at_cwd_path :: (path: Path) -> bool {
	return path.words.count == 1 && equal(path.words[0], ".");
}

go_up_dir :: (using ctx: *Ctx, using panel: *Panel) {
	array_add(*path.words, "..");
	reduce_path(path);
	panel_update(ctx, panel);
	should_render = true;
}

main :: () {
	init_width :: 800;
	init_height :: 600;
	using ctx := Ctx.{
	};
#if DEBUG {
		debug_text.allocator = temp;
	}
	path := parse_path(copy_string("."), reduce=false);
	array_add(*ctx.panels, .{rect=.{x=0, y=0, w=init_width, h=init_height}, path=path});
	sdl_debug_version_info();
	check_sdl(SDL_Init(.VIDEO), "Can't init SDL");
	check_sdl(SDL_CreateWindowAndRenderer("file explorer", 800, 600, .RESIZABLE, *window, *renderer), "Can't create window");
	check_sdl(TTF_Init());
	font = TTF_OpenFont(font_path, 24);
	if !font {
		print("Can't load font: %\n", sdl_get_error());
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
					select_dirent_on_point(*ctx, *ctx.panels[0], .{event.mouse.x, event.mouse.y});
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
			print("** Summary %: **\n%\n", it_index, <<it);
		}
		print("Found leaks:\n");
		log_leak_report(report);
	}
}