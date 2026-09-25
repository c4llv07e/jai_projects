
Element_Type :: enum s32 {
	NONE :: 0;
	BUTTON;
	LABEL;
}

Element :: union {
	type: Element_Type = .NONE;
	label: Label_Element;
	button: Button_Element;
}

Button_Element :: struct {
	type: Element_Type  = .BUTTON;
	rect: SDL_FRect;
	inner_color: SDL_Color;
	border_color: SDL_Color;
}

Label_Element :: struct {
	type: Element_Type = .LABEL;
	text: string;
	using position: SDL_FPoint;
	color: SDL_Color;
}

Ctx :: struct {
	window: *SDL_Window;
	renderer: *SDL_Renderer;
	font: *TTF_Font;
	deltatime: float32;
	mouse_x, mouse_y: float32;
	previous_frame_time: u64;
	current_frame_time: u64;
	keymod_state: SDL_Keymod;
	immediate_cursor: SDL_FPoint;
	label_height: float32 = 24;
	elements: [..]Element;
}

check_sdl :: (status: bool, msg := "Error on calling sdl function", caller_loc := #caller_location) #expand {
	if (!status) {
		log("%: %: %\n", caller_loc, msg, sdl_get_error(), flags=.ERROR);
		exit(-1);
	}
}

draw_text :: (renderer: *SDL_Renderer, font: *TTF_Font, x: float32, y: float32, text: string, color: SDL_Color = .{0xe3, 0xe3, 0xe3, 0xff}, scale := 1.0) {
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

render_ui :: (using ctx: *Ctx) {
	for element, element_index: elements {
		if element.type == {
			case .LABEL;
			label := element.label;
			draw_text(renderer, font, label.x, label.y, label.text, label.color);
			case;
			log("Unknown element type %", element.type);
			exit(-1);
		}
	}
}

render :: (using ctx: *Ctx) {
	sdl_set_color(renderer, .{0x20, 0x20, 0x20, 0xff});
	SDL_RenderClear(renderer);
	render_ui(ctx);
	SDL_RenderPresent(renderer);
}

label :: (using ctx: *Ctx, text: string, color := SDL_Color.{0xe3, 0xe3, 0xe3, 0xff}) {
	array_add(*elements, Element.{label = .{
				  text = text,
				  position = immediate_cursor,
				  color = color,
			  }});
	immediate_cursor.y += label_height;
}

end_ui_frame :: (using ctx: *Ctx) {
	immediate_cursor = .{0, 0};
	array_reset(*elements);
}

main :: () {
	using ctx := Ctx.{
	};
	initial_width :: 800;
	initial_height :: 600;
	check_sdl(SDL_Init(.VIDEO), "Can't init SDL");
	check_sdl(TTF_Init(), "Can't init TTF engine");
	check_sdl(SDL_CreateWindowAndRenderer("ui", initial_width, initial_height, .RESIZABLE, *window, *renderer), "Can't create SDL output");
	font = TTF_OpenFont("/usr/share/fonts/TTF/liberation/LiberationMono-Regular.ttf", 24);
	assert(font != null, "Can't load font");
	SDL_SetRenderVSync(renderer, 1);
	elements.allocator = temp;
	event: SDL_Event;
	previous_frame_time = SDL_GetTicks();
	while main_loop := true {
		current_frame_time := SDL_GetTicks();
		deltatime = (current_frame_time - previous_frame_time) / 1000.0;
		previous_frame_time = current_frame_time;
		keymod_state = SDL_GetModState();
		while SDL_PollEvent(*event) {
			if event.type == {
				case .QUIT;
				break main_loop;
			}
		}
		label(*ctx, "test");
		label(*ctx, "second");
		render(*ctx);
		end_ui_frame(*ctx);
		reset_temporary_storage();
	}
}

#import "Basic";
#import,file "sdl3.jai";