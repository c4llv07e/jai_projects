Render_State :: struct {
	render_text :: inline (render_data: render_data_type, x: float32, y: float32, text: string, color: Color = .{0xe3, 0xe3, 0xe3, 0xff}, font_size: float32 = 0.0, font: font_type) {
		assert(font != null);
		draw_text(render_data.renderer, font, x, y, text, cast,force(SDL_Color)color, font_size);
	};
	measure_string :: inline (render_data: render_data_type, font: font_type, text: string) -> float32 {
		ok, width := sdl_measure_string(render_data.font, text);
		return xx width;
	};
	render_rect :: inline (using render_data: render_data_type, rect: Rect, color: Color) {
		sdl_set_color(renderer, cast,force(SDL_Color)color);
		sdl_rect := SDL_FRect.{rect.x, rect.y, rect.w, rect.h};
		SDL_RenderRect(renderer, *sdl_rect);
	};
	render_fill_rect :: inline (using render_data: render_data_type, rect: Rect, color: Color) {
		sdl_set_color(renderer, cast,force(SDL_Color)color);
		sdl_rect := SDL_FRect.{rect.x, rect.y, rect.w, rect.h};
		SDL_RenderFillRect(renderer, *sdl_rect);
	};
	font_type :: *TTF_Font;
	render_data_type :: *Ctx;
}

#import,file "imgui.jai" (Render = Render_State);

Entities :: struct {
	should_delete: bool = false;
	time: u64;
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
	entities: [..]Entities;
	gui_state: Gui_State;
}

check_sdl :: (status: bool, msg := "Error on calling sdl function", caller_loc := #caller_location) #expand {
	if (!status) {
		log_error("%: %: %\n", caller_loc, msg, sdl_get_error(), flags=.ERROR);
		exit(-1);
	}
}

draw_text :: (renderer: *SDL_Renderer, font: *TTF_Font, x: float32, y: float32, text: string, color: SDL_Color = .{0xe3, 0xe3, 0xe3, 0xff}, font_size := 0.0) {
	surface := TTF_RenderText_Blended(font, text.data, xx text.count, color);
	if !surface {
		log_error("Can't blit surface: %!", sdl_get_error());
		return;
	}
	defer SDL_DestroySurface(surface);
	texture := SDL_CreateTextureFromSurface(renderer, surface);
	if !texture {
		log("Can't upload surface on GPU: %!", sdl_get_error());
		return;
	}
	defer SDL_DestroyTexture(texture);
	scale := 1.0;
	if font_size != 0.0 {
		scale = font_size / TTF_GetFontSize(font);
	}
	dstrect := SDL_FRect.{
		x = x,
		y = y,
		w = texture.w * scale,
		h = texture.h * scale,
	};
	SDL_RenderTexture(renderer, texture, null, *dstrect);
}

prune_entities :: (using ctx: *Ctx) {
	iter := 0;
	while iter < entities.count {
		if entities[iter].should_delete {
			if iter < entities.count - 1 {
				memcpy(*entities[iter], *entities[iter + 1], size_of(type_of(entities[iter])) * (entities.count - 1 - iter));
			}
			entities.count -= 1;
		} else {
			iter += 1;
		}
	}
}

render :: (using ctx: *Ctx) {
	sdl_set_color(renderer, .{0x20, 0x20, 0x20, 0xff});
	SDL_RenderClear(renderer);
	gui_render(*gui_state, ctx);
	// debug_widget(*gui_state, ctx, font, gui_state.widget_root, y = 40.0);
	SDL_RenderPresent(renderer);
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
	event: SDL_Event;
	window_state: Window_State;
	SDL_GetWindowSizeInPixels(window, *window_state.width, *window_state.height);
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
				case .MOUSE_BUTTON_DOWN;
				buttons: Mouse_Buttons_State;
				if event.mouse.button == .LEFT then buttons |= .LEFT;
				handle_click(*gui_state, .{event.mouse.x, event.mouse.y}, buttons);
				case .WINDOW_RESIZED;
				window_state.width = event.window.data1;
				window_state.height = event.window.data2;
			}
		}
		gui_begin(*gui_state, window_state);
		{
			// TODO(c4llv07e): gui_state.stacks.<stack_name> is too long, we need helper functions like set_next_pref_width or something;
			stack_push(*gui_state.stacks.font, font);
			stack_set_next(*gui_state.stacks.pref_width, .{property = .Percent, value = 1.0});
			stack_set_next(*gui_state.stacks.background_color, .{0x80, 0x00, 0x00, 0xff});
			gui_panel_begin(*gui_state, "buttons");
			{
				gui_label(*gui_state, "test % % %", 1, 2, 3);
				gui_label(*gui_state, "test2");
				if gui_button(*gui_state, "add entity").clicked & .LEFT {
					array_add(*entities, .{time = current_frame_time});
				}
			}
			gui_panel_end(*gui_state);
			stack_set_next(*gui_state.stacks.layout_dir, .Y);
			stack_set_next(*gui_state.stacks.background_color, .{0x00, 0x00, 0xff, 0xff});
			stack_set_next(*gui_state.stacks.pref_height, .{property = .Shrink});
			stack_set_next(*gui_state.stacks.pref_width, .{property = .Shrink});
			gui_panel_begin(*gui_state, "entities");
			{
				stack_push(*gui_state.stacks.text_color, .{0xff, 0x00, 0x00, 0xff});
				stack_push(*gui_state.stacks.pref_width, .{property = .Content, value = 12});
				stack_push(*gui_state.stacks.pref_height, .{property = .Content, value = 0});
				stack_push(*gui_state.stacks.border_color, .{0xff, 0xff, 0x00, 0xff});
				for * entity: entities {
					if gui_button(*gui_state, tprint("entity-%", entity.time)).clicked & .LEFT {
						entity.should_delete = true;
					}
				}
				stack_pop(*gui_state.stacks.border_color);
				stack_pop(*gui_state.stacks.pref_height);
				stack_pop(*gui_state.stacks.pref_width);
				stack_pop(*gui_state.stacks.text_color);
			}
			gui_panel_end(*gui_state);
			stack_set_next(*gui_state.stacks.floating_x, 100);
			stack_set_next(*gui_state.stacks.floating_y, 100);
			stack_set_next(*gui_state.stacks.layout_dir, .Y);
			gui_panel_begin(*gui_state, "floating");
			{
				stack_set_next(*gui_state.stacks.font_size, 48.0);
				gui_label(*gui_state, "we are floating...");
				gui_label(*gui_state, "after big text");
			}
			gui_panel_end(*gui_state);
			gui_label(*gui_state, "end");
			prune_entities(*ctx);
			stack_pop(*gui_state.stacks.font);
		}
		gui_end(*gui_state);
		render(*ctx);
		reset_temporary_storage();
	}
}

#import "Basic";
#import,file "sdl3.jai";