
Element_Flags :: enum_flags u32 {
	Clickable;
	Hoverable;
	Scrollable;
	Text;
	Border;
	Background;
	Clip;
	Slider; // Ryan, I curse you! You've said something about "OOP virus" and now what? You're using `custom_draw` function pointer for different rendering! It's literally the most OOP-ish polymorphism!
}

Mouse_Buttons_State :: enum_flags u8 {
	LEFT;
	RIGHT;
	MIDDLE;
	BACK;
	FORWARD;
}

Element_Frame_Data :: struct {
	clicked: Mouse_Buttons_State;
	hovered: bool;
}

Element :: struct {
	flags: Element_Flags;
	using rect: SDL_FRect;
	text: string;
	frame_data: Element_Frame_Data;
	background_color: SDL_Color;
	border_color: SDL_Color;
	children: [..]Element;
	id: s64;
	padding: float32;
	union {
		slider_value: *float32;
	}
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
	root: Element;
	last_hovered_element: *Element = null;
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

render_element :: (using ctx: *Ctx, element: Element, offset: SDL_FPoint = .{0.0, 0.0}) {
	off_rect := element.rect + offset;
	if element.flags & .Background {
		sdl_set_color(renderer, element.background_color);
		SDL_RenderFillRect(renderer, *off_rect);
	}
	if element.flags & .Border {
		sdl_set_color(renderer, element.border_color);
		SDL_RenderRect(renderer, *off_rect);
	}
	if element.flags & .Text {
		draw_text(renderer, font, off_rect.x + element.padding, off_rect.y, element.text);
	}
	if element.flags & .Slider {
		sdl_set_color(renderer, .{0x00, 0xff, 0x00, 0xff});
		rect := SDL_FRect.{off_rect.x + (element.slider_value.*) * off_rect.w, off_rect.y, off_rect.h, off_rect.h};
		SDL_RenderFillRect(renderer, *rect);
	}
	for child, child_index: element.children {
		render_element(ctx, child, rect_origin(off_rect));
	}
}

render :: (using ctx: *Ctx) {
	sdl_set_color(renderer, .{0x20, 0x20, 0x20, 0xff});
	SDL_RenderClear(renderer);
	render_element(ctx, root);
	SDL_RenderPresent(renderer);
}

// Doesn't own or copy anything, manage memory yourself.
label :: (font: *TTF_Font, text: string, background_color := SDL_Color.{0, 0, 0, 0}, border_color := SDL_Color.{0, 0, 0, 0}) -> Element {
	background_bit: Element_Flags = ifx background_color.a != 0 then Element_Flags.Background else 0;
	border_bit: Element_Flags = ifx border_color.a != 0 then Element_Flags.Border else 0;
	font_height := TTF_GetFontHeight(font);
	ok, text_width := sdl_measure_string(font, text);
	return .{
		flags = .Text | background_bit | border_bit,
		text = text,
		rect = .{0, 0, xx text_width, xx font_height},
		border_color = border_color,
		background_color = background_color,
	};
}

slider :: (val: *float32, width: float32 = 100.0, background_color := SDL_Color.{0x10, 0x30, 0x10, 0xff}, border_color := SDL_Color.{0, 0, 0, 0}) -> Element {
	border_bit: Element_Flags = ifx border_color.a != 0 then Element_Flags.Border else 0;
	return .{
		flags = .Background | border_bit | .Slider,
		rect = .{
			0, 0, width, 24,
		},
		slider_value = val,
		border_color = border_color,
		background_color = background_color,
	};
}

button :: (text: string = "", font: *TTF_Font = null, id: s64 = 0, background_color := SDL_Color.{0x20, 0x20, 0x20, 0x20}, border_color := SDL_Color.{0x20, 0x60, 0x20, 0xff}, padding: float32 = 6.0) -> Element {
	if text.count > 0 && font == null {
		log("Warning, button get text but not font, can't determine height and width of the button due to it!");
	}
	font_height: s32 = 0;
	text_width: s32 = 0;
	if font != null {
		ok: bool;
		font_height = TTF_GetFontHeight(font);
		ok, text_width = sdl_measure_string(font, text);
	}
	return .{
		flags = .Text | .Background | .Border | .Clickable,
		text = text,
		rect = .{0, 0, (xx text_width) + padding * 2, xx font_height},
		border_color = border_color,
		background_color = background_color,
		id = id,
		padding = padding,
	};
}

recalculate_layout :: (tree: *Element, margin: float32 = 0.0) {
	accum_height: float32 = 0.0;
	for * child: tree.children {
		child.y = accum_height;
		recalculate_layout(child, margin);
		accum_height += child.h + margin;
	}
	if accum_height > tree.h {
		tree.h = accum_height;
	}
}

// Id 0 considered unclickable. .Clicable with zero id is forbidden.
hit_test :: (tree: *Element, point: SDL_FPoint, flags: Element_Flags = .Clickable) -> *Element {
	if tree.flags & .Clickable {
		if is_intersecting(tree.rect, point) {
			return tree;
		}
	}
	for * child: tree.children {
		res := hit_test(child, point - .{tree.x, tree.y});
		if res != null {
			return res;
		}
	}
	return null;
}

hover_logic :: (element: *Element, hovered := true) {
	if element == null return;
	if element.id == {
		case press_me_id;
		background_color := SDL_Color.{0x00, 0x00, 0x00, 0xff};
		if hovered then background_color = SDL_Color.{0xff, 0x00, 0xff, 0xff};
		element.background_color = background_color;
	}
}

press_me_id :: 1;

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
	val: float32;
	array_add(*ctx.root.children, label(font, "test"));
	array_add(*ctx.root.children, label(font, "second"));
	array_add(*ctx.root.children, slider(*val));
	array_add(*ctx.root.children, button("press me", font, press_me_id));
	recalculate_layout(*ctx.root, 5.0);
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
				case .MOUSE_MOTION;
				hovered_element := hit_test(*ctx.root, .{event.motion.x, event.motion.y}, .Hoverable);
				hover_logic(last_hovered_element, hovered_element == last_hovered_element);
				last_hovered_element = hovered_element;
				hover_logic(hovered_element);
				case .MOUSE_BUTTON_DOWN;
				if event.mouse.button == .LEFT {
					clicked_element := hit_test(*ctx.root, .{event.mouse.x, event.mouse.y});
					if clicked_element == null continue;
					if clicked_element.id == {
						case press_me_id;
						log("pressed \"press me\" button");
					}
				} else if event.mouse.button == .RIGHT {
					ctx.root.x = event.mouse.x;
					ctx.root.y = event.mouse.y;
				}
			}
		}
		render(*ctx);
		reset_temporary_storage();
	}
}

#import "Basic";
#import,file "sdl3.jai";