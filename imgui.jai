// Was inspired by Ryan Fleury's UI concepts.

Widget_Flags :: enum_flags u32 {
	Clickable;
	Draw_Background;
	Draw_Border;
	Draw_Text;
	Hot_Effect;
}

Mouse_Buttons_State :: enum_flags u8 {
	LEFT;
	RIGHT;
	MIDDLE;
	M4;
	M5;
}

Widget_Signal :: struct {
	clicked: Mouse_Buttons_State;
	hovered: bool;
}

Widget :: struct {
	font: *TTF_Font; // TODO(c4llv07e): Maybe it should point on persistent storage and not directly on font.
	flags: Widget_Flags;
	key: u64;
	text: string;
	using rect: SDL_FRect;
	border_color: SDL_Color;
	background_color: SDL_Color;
	text_color: SDL_Color;
	font_size: float32;
	frame_signal: Widget_Signal;
	last_frame_index: s64;
}
null_widget: Widget;

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
	widgets: [..]*Widget;
	widget_stack: [..]*Widget;
	seed_stack: [..]u64;
	frame_index: s64;
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

get_top_seed :: (using ctx: *Ctx) -> u64 {
	if seed_stack.count > 0 {
		return pop(*seed_stack);
	}
	return 0;
}

key_from_string :: (seed: u64, str: string) -> u64 {
	// TODO(c4llv07e): I am just learning, but this seed could be problematic in the future.
	return seed + djb2_hash(str);
}

top_text_color :: () -> SDL_Color {
	return .{0xe3, 0xe3, 0xe3, 0xff};
}

is_null_widget :: (widget: *Widget) -> bool {
	return (widget == *null_widget) || (widget.key == 0);
}

get_widget_by_key :: (using ctx: *Ctx, key: u64) -> *Widget {
	for widget: widgets {
		if widget.key == key {
			return widget;
		}
	}
	return *null_widget;
}

add_and_peek :: (array: *[..] $T, item: T) -> *T {
	array_add(array, item);
	return peek_pointer(array.*);
}

init_widget_by_key :: (using ctx: *Ctx, key: u64, flags: Widget_Flags) -> *Widget {
	widget := get_widget_by_key(ctx, key);
	if is_null_widget(widget) {
		widget = alloc(size_of(Widget));
		widget.key = key;
		array_add(*widgets, widget);
	}
	widget.last_frame_index = frame_index;
	widget.font = font;
	widget.font_size = 24;
	widget.text_color = top_text_color();
	widget.flags = flags;
	array_add(*ctx.widget_stack, widget);
	return widget;
}

init_widget_by_string :: (using ctx: *Ctx, str: string, flags: Widget_Flags) -> *Widget {
	seed := get_top_seed(ctx);
	key := key_from_string(seed, str);
	widget := init_widget_by_key(ctx, key, flags);
	if flags & .Draw_Text {
		widget.text = str;
	}
	return widget;
}

gui_label :: (using ctx: *Ctx, fmt: string, args: ..Any) -> Widget_Signal {
	text: string = fmt;
	if args.count > 0 {
		text = tprint(fmt, ..args);
	}
	font_height := TTF_GetFontHeight(font);
	ok, text_width := sdl_measure_string(font, text, 0);
	widget := init_widget_by_string(ctx, text, .Draw_Text);
	widget.rect = .{0, 0, xx text_width, xx font_height};
	return widget.frame_signal;
} @PrintLike;

gui_button :: (using ctx: *Ctx, text: string) -> Widget_Signal {
	font_height := TTF_GetFontHeight(font);
	ok, text_width := sdl_measure_string(font, text, 0);
	widget := init_widget_by_string(ctx, text, .Clickable | .Draw_Border | .Draw_Background | .Draw_Text);
	widget.rect = .{0, 0, xx text_width, xx font_height};
	return widget.frame_signal;
}

render :: (using ctx: *Ctx) {
	sdl_set_color(renderer, .{0x20, 0x20, 0x20, 0xff});
	SDL_RenderClear(renderer);
	for widget: widget_stack {
		if widget.flags & .Draw_Background {
			sdl_set_color(renderer, widget.background_color);
			SDL_RenderFillRect(renderer, *widget.rect);
		}
		if widget.flags & .Draw_Border {
			sdl_set_color(renderer, widget.border_color);
			SDL_RenderRect(renderer, *widget.rect);
		}
		if widget.flags & .Draw_Text {
			draw_text(renderer, widget.font, widget.x, widget.y, widget.text, widget.text_color);
		}
	}
	draw_text(renderer, font, 300, 0, tprint("number of widgets in stack = %", widget_stack.count));
	draw_text(renderer, font, 300, 24, tprint("allocated widgets in stack = %", widget_stack.allocated));
	draw_text(renderer, font, 300, 48, tprint("number of widgets in heap = %", widgets.count));
	draw_text(renderer, font, 300, 72, tprint("allocated widgets in heap = %", widgets.allocated)); 
	SDL_RenderPresent(renderer);
}

handle_click :: (using ctx: *Ctx, point: SDL_FPoint, buttons: Mouse_Buttons_State) {
	for widget: widgets {
		if is_intersecting(widget.rect, point) && widget.flags & .Clickable {
			widget.frame_signal.clicked |= .LEFT;
		}
	}
}

widget_reset_frame_signal :: (using ctx: *Ctx) {
	for widget: widgets {
		memset(*widget.frame_signal, 0, size_of(Widget_Signal));
	}
}

prune_old_widgets :: (using ctx: *Ctx) {
	for widget: widgets {
		if widget.last_frame_index < frame_index {
			remove;
		}
	}
	frame_index += 1;
}

calculate_layout :: (using ctx: *Ctx) {
	for widget, widget_index: widget_stack {
		widget.y = xx (widget_index * 26);
	}
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
	previous_frame_time = SDL_GetTicks();
	while main_loop := true {
		current_frame_time := SDL_GetTicks();
		deltatime = (current_frame_time - previous_frame_time) / 1000.0;
		previous_frame_time = current_frame_time;
		keymod_state = SDL_GetModState();
		widget_reset_frame_signal(*ctx);
		prune_old_widgets(*ctx);
		while SDL_PollEvent(*event) {
			if event.type == {
				case .QUIT;
				break main_loop;
				case .MOUSE_BUTTON_DOWN;
				buttons: Mouse_Buttons_State;
				if event.mouse.button == .LEFT then buttons |= .LEFT;
				handle_click(*ctx, .{event.mouse.x, event.mouse.y}, buttons);
			}
		}
		gui_label(*ctx, "test % % %", 1, 2, 3);
		gui_label(*ctx, "test2");
		if gui_button(*ctx, "add entity").clicked & .LEFT {
			log("Added entity at %", current_frame_time);
			array_add(*entities, .{time = current_frame_time});
		}
		for * entity: entities {
			if gui_button(*ctx, tprint("entity-%", entity.time)).clicked & .LEFT {
				entity.should_delete = true;
			}
		}
		prune_entities(*ctx);
		calculate_layout(*ctx);
		render(*ctx);
		widget_stack.count = 0;
		reset_temporary_storage();
	}
}

#import "Hash";
#import "Basic" () (MEMORY_DEBUGGER=true);
#import,file "sdl3.jai";