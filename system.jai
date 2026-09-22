#import,file "sdl3.jai";

Color :: SDL_Color;

System_Ctx :: struct {
	window: *SDL_Window;
	renderer: *SDL_Renderer;
	font: *TTF_Font;
}

using system_ctx: System_Ctx;

check_sdl :: (status: bool, msg := "Error on calling sdl function", caller_loc := #caller_location) #expand {
	if (!status) {
		log("%: %: %\n", caller_loc, msg, sdl_get_error(), flags=.ERROR);
		exit(-1);
	}
}

mesaure_text :: (text: string) -> float32 {
	ok, width := sdl_measure_string(font, text, 0);
	if !ok return 0.0;
	return xx width;
}

should_render := true;
system_render :: (renderer: *SDL_Renderer) {
	if on_demand_renderer && !should_render {
		SDL_Delay(1);
		return;
	}
	sdl_set_color(renderer, .{0x20, 0x20, 0x20, 0xff});
	SDL_RenderClear(renderer);
	logic_render();
	SDL_RenderPresent(renderer);
}

draw_text :: (x: float32, y: float32, text: string, color: Color = .{0xe3, 0xe3, 0xe3, 0xff}, scale := 1.0) {
	surface := TTF_RenderText_Blended(font, text.data, xx text.count, color);
	if !surface {
		log("Can't blit surface: %!", sdl_get_error());
		return;
	}
	defer SDL_DestroySurface(surface);
	texture := SDL_CreateTextureFromSurface(renderer, surface);
	if !texture {
		log("Can't upload surface on GPU: %!", sdl_get_error());
		return;
	}
	defer SDL_DestroyTexture(texture);
	dstrect := SDL_FRect.{
		x = x,
		y = y,
		w = texture.w * scale,
		h = texture.h * scale,
	};
	SDL_RenderTexture(renderer, texture, null, *dstrect);
}

draw_rect :: (x: float32, y: float32, w: float32, h: float32, color: Color) {
	rect := SDL_FRect.{x, y, w, h};
	sdl_set_color(renderer, color);
	SDL_RenderRect(renderer, *rect);
}

font_path :: "/usr/share/fonts/TTF/liberation/LiberationMono-Regular.ttf";
font_height :: 24;

main :: () {
	sdl_debug_version_info();
	check_sdl(SDL_Init(.VIDEO), "Can't init sdl");
	check_sdl(SDL_CreateWindowAndRenderer("Sytem", 800, 600, .RESIZABLE, *window, *renderer), "Can't create SDL output");
	check_sdl(TTF_Init(), "Can't init TTF library");
	font = TTF_OpenFont(font_path, font_height);
	if font == null {
		log("Can't open font at %: %", font_path, sdl_get_error());
	}
	logic_init();
	should_close := false;
	event: SDL_Event;
	while main_loop := !should_close {
		while SDL_PollEvent(*event) {
			if event.type == {
				case .QUIT;
				should_close = true;
				break main_loop;
			}
		}
		system_render(renderer);
	}
}

#import "Basic";