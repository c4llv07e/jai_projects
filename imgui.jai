// Was inspired by Ryan Fleury's UI concepts.

Widget_Flags :: enum_flags u32 {
	Clickable;
	Draw_Background;
	Draw_Border;
	Draw_Text;
	Hot_Effect;
}

Widget_Size_Property :: enum u8 {
	None :: 0;
	Pixels;
	Content;
	Percent;
	Shrink; // to sum of children
}

Widget_Size :: struct {
	property: Widget_Size_Property;
	value: float32;
}

Axies :: enum u8 {
	X;
	Y;
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
	pref_size: [#run enum_values_as_s64(Axies).count]Widget_Size;
	child_dir: Axies;
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
	next, prev, first, last, parent: *Widget;
	layout_dir: Axies = .Y;
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
	widget_root: *Widget;
	widgets: [..]*Widget;
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

get_top_pref_width :: (using ctx: *Ctx) -> Widget_Size {
	return .{property = .Pixels, value = 250.0};
}

get_top_pref_height :: (using ctx: *Ctx) -> Widget_Size {
	return .{property = .Pixels, value = 50.0};
}

get_top_parent :: (using ctx: *Ctx) -> *Widget {
	return ctx.widget_root;
}

key_from_string :: (seed: u64, str: string) -> u64 {
	// TODO(c4llv07e): I am just learning, but this seed could be problematic in the future.
	return seed + djb2_hash(str);
}

top_text_color :: () -> SDL_Color {
	return .{0xe3, 0xe3, 0xe3, 0xff};
}

is_null_widget :: (widget: *Widget) -> bool {
	return (widget == *null_widget) || (widget == null);
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

iterate_children :: (root: *Widget, widget: *Widget) -> next: *Widget {
	if !is_null_widget(widget.first) {
		return widget.first;
	}
	while !is_null_widget(widget) && widget != root {
		if !is_null_widget(widget.next) {
			return widget.next;
		}
		widget = widget.parent;
	}
	return *null_widget;
}

append_to_parent :: (parent: *Widget, widget: *Widget) {
	widget.parent = parent;
	if is_null_widget(parent.last) {
		assert(is_null_widget(parent.first), "Parent doesn't have last child but have first.");
		parent.first = widget;
		parent.last = widget;
		widget.next = *null_widget;
		widget.prev = *null_widget;
	} else {
		parent.last.next = widget;
		widget.prev = parent.last;
		widget.next = *null_widget;
		parent.last = widget;
	}
}

init_widget_by_key :: (using ctx: *Ctx, key: u64, flags: Widget_Flags) -> *Widget {
	parent := get_top_parent(ctx);
	widget := get_widget_by_key(ctx, key);
	if is_null_widget(widget) {
		widget = alloc(size_of(Widget));
		array_add(*widgets, widget);
	}
	widget.key = key;
	widget.last_frame_index = frame_index;
	widget.font = font;
	widget.font_size = 24;
	widget.text_color = top_text_color();
	widget.flags = flags;
	widget.pref_size[Axies.X] = get_top_pref_width(ctx);
	widget.pref_size[Axies.Y] = get_top_pref_height(ctx);
	widget.first = *null_widget;
	widget.last = *null_widget;
	append_to_parent(parent, widget);
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

draw_widget :: (using ctx: *Ctx, widget: *Widget) {
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

render :: (using ctx: *Ctx) {
	sdl_set_color(renderer, .{0x20, 0x20, 0x20, 0xff});
	SDL_RenderClear(renderer);
	widget := ctx.widget_root;
	while !is_null_widget(widget) {
		draw_widget(ctx, widget);
		widget = iterate_children(ctx.widget_root, widget);
	}
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

get_dir_properties :: (rect: *SDL_FRect, dir: Axies) -> pos: *float32, size: *float32 #expand {
	assert(dir == .X || dir == .Y);
	if dir == .X {
		return *rect.x, *rect.w;
	}
	return *rect.y, *rect.h;
}

set_dir_pos :: inline (rect: *SDL_FRect, dir: Axies, val: float32) #expand {
	assert(dir == .X || dir == .Y);
	if dir == .X {
		rect.x = val;
	} else {
		rect.y = val;
	}
}

set_dir_size :: inline (rect: *SDL_FRect, dir: Axies, val: float32) #expand {
	assert(dir == .X || dir == .Y);
	if dir == .X {
		rect.w = val;
	} else {
		rect.h = val;
	}
}

get_dir_size :: inline (rect: *SDL_FRect, dir: Axies) -> float32 #expand {
	assert(dir == .X || dir == .Y);
	if dir == .X {
		return rect.w;
	}
	return rect.h;
}

calculate_layout_standalone :: (using ctx: *Ctx, root: *Widget, dir: Axies) {
	widget := root;
	while !is_null_widget(widget) {
		if widget.pref_size[dir].property == {
			case .Pixels;
			set_dir_size(*widget.rect, dir, widget.pref_size[dir].value);
			case .Content;
			log("Content layout size not implemented yet!");
			exit(-1);
		}
		widget = iterate_children(root, widget);
	}
}

calculate_layout_position :: (using ctx: *Ctx, root: *Widget, dir: Axies) {
	position: float32 = 0.0;
	widget := root;
	while !is_null_widget(widget) {
		child := widget.first;
		while !is_null_widget(child) {
			if widget.layout_dir == dir {
				set_dir_pos(*child.rect, dir, position);
				position += get_dir_size(*child.rect, dir);
			}
			child = child.next;
		}
		widget = iterate_children(root, widget);
	}
}

calculate_layout :: (using ctx: *Ctx, root: *Widget, dir: Axies) {
	calculate_layout_standalone(ctx, root, dir);
	calculate_layout_position(ctx, root, dir);
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
	_root: Widget;
	ctx.widget_root = *_root;
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
			array_add(*entities, .{time = current_frame_time});
		}
		for * entity: entities {
			if gui_button(*ctx, tprint("entity-%", entity.time)).clicked & .LEFT {
				entity.should_delete = true;
			}
		}
		prune_entities(*ctx);
		for dir: enum_values_as_s64(Axies) {
			calculate_layout(*ctx, ctx.widget_root, cast(Axies)dir);
		}
		render(*ctx);
		reset_temporary_storage();
	}
}

#import "Hash";
#import "Basic" () (MEMORY_DEBUGGER=true);
#import,file "sdl3.jai";