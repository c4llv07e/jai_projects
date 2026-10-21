#if false {
	font_path :: "/usr/share/fonts/TTF/liberation/LiberationMono-Regular.ttf";
} else {
	font_path :: "/usr/share/fonts/TTF/liberation/LiberationSans-Regular.ttf";
}

Node_Data :: struct {
	rect: SDL_FRect;
	text: string;
	min_size: float;
}

Ctx :: struct {
	window: *SDL_Window;
	window_height, window_width: s64;
	renderer: *SDL_Renderer;
	font: *TTF_Font;
	font_height: s64;
	should_render: bool;
	report: *Iprof.Report;
	iprof_config: Iprof.Config;
	mouse_x, mouse_y: s64;
	graph_portion: float32;
	in_graph: bool;
	graph: Node(Node_Data);
	camera: SDL_FPoint;
	camera_scale: float32;
	keybinds_root: Keybind_Root;
}
using ctx: Ctx;

Zones :: enum s64 {
	global :: 0;
	main_loop;
	render;
	events;
	float_to_u8;
	draw_line;
	draw_rectangle;
	draw_text;
	text_width;
	draw_node;
}

Node :: struct(Data_Type: Type) {
	children: [..]*#this;
	using data: Data_Type;
}

check_sdl :: (status: bool, msg := "Error on calling sdl function", caller_loc := #caller_location) #expand {
	if (!status) {
		log_error("%: %: %\n", caller_loc, msg, sdl_get_error(), flags=.ERROR);
		exit(-1);
	}
}

norm_float_to_u8 :: inline (x: float) -> u8 {
	Iprof.zone_begin(cast(s64)Zones.float_to_u8);
	defer Iprof.zone_end();
	return cast,force,no_check(u8)clamp(x * 255, 0, 255);
}

to_sdl_color :: (c: Vector4) -> SDL_Color {
	return .{norm_float_to_u8(c.x), norm_float_to_u8(c.y), norm_float_to_u8(c.z), norm_float_to_u8(c.w)};
}

draw_iprof_in_rect :: (x: float, y: float, width: float, height: float, graph_portion: float32 = 0.5, iprof_config: *Iprof.Config) {
	Iprof.draw(x, window_height - y - height + (graph_portion) * height, width, height * (1.0 - graph_portion), iprof_config);
	{
		old_draw_text := iprof_config.draw_text;
		defer iprof_config.draw_text = old_draw_text;
		iprof_config.draw_text = #bake_arguments draw_text(grow_up = true);
		Iprof.draw_graph(x, xx window_height - y - height * (1.0 - graph_portion) - iprof_config.font_character_height, width, height * graph_portion - iprof_config.font_character_height, iprof_config);
	}
}

project_to_camera :: (using rect: SDL_FRect) -> SDL_FRect {
	return .{
		(x - camera.x) * camera_scale + window_width / 2,
		(y - camera.y) * camera_scale + window_height / 2,
		w * camera_scale,
		h * camera_scale,
	};
}

project_to_camera :: (using point: SDL_FPoint) -> SDL_FPoint {
	return .{
		(x - camera.x) * camera_scale + window_width / 2,
		(y - camera.y) * camera_scale + window_height / 2,
	};
}

project_to_camera :: (x: float32, y: float32) -> float32, float32 {
	return (x - camera.x) * camera_scale + window_width / 2, (y - camera.y) * camera_scale + window_height / 2;
}

project_from_camera :: (x: float32, y: float32) -> float32, float32 {
	return (x - window_width / 2) / camera_scale + camera.x, (y - window_height / 2) / camera_scale + camera.y;
}

draw_node :: (using node: Node(Node_Data)) {
	Iprof.zone_begin(cast(s64)Zones.draw_node);
	defer Iprof.zone_end();
	screen_rect := project_to_camera(node.rect);
	for child: node.children {
		child_srect := project_to_camera(child.rect);
		draw_node(child);
		sdl_render_line(renderer, project_to_camera(SDL_FPoint.{rect.x + rect.w / 2, rect.y + rect.h}), project_to_camera(SDL_FPoint.{child.rect.x + child.rect.w / 2, child.rect.y}), .{0xff, 0x00, 0x00, 0xff});
	}
	draw_rect_lines(renderer, screen_rect, .{0xff, 0x00, 0x00, 0xff});
	if node.text.count > 0
		sdl_render_text(renderer, font, SDL_floorf(screen_rect.x), SDL_floorf(screen_rect.y), node.text);
	sdl_render_text(renderer, font, SDL_floorf(screen_rect.x), SDL_floorf(screen_rect.y + font_height), tprint("%", node.min_size));
	// draw_rect_lines(renderer, project_to_camera(SDL_FRect.{node.rect.x + node.rect.w / 2 - node.min_size / 2, node.rect.y, node.min_size, node.rect.h}), .{0x00, 0x00, 0xff, 0xff});
}

render :: () {
	Iprof.zone_begin(cast(s64)Zones.render);
	defer Iprof.zone_end();
	if !should_render {
		SDL_Delay(1);
		return;
	}
	sdl_set_color(renderer, .{0x20, 0x20, 0x20, 0xff});
	SDL_RenderClear(renderer);
	rect := SDL_FRect.{10, 10, 400, 500};
	// draw_iprof_in_rect(rect.x, rect.y, rect.w, rect.h, graph_portion, *iprof_config);
	// draw_rect_lines(renderer, rect, .{0xff, 0x00, 0x00, 0xff});
	// draw_text(0, 0, tprint("%", Iprof.displayed_quantity), Vector4.{1, 1, 1, 1});
	draw_node(graph);
	sdl_render_line(renderer, project_to_camera(.{0, 0}), project_to_camera(.{100, 0}), .{0xff, 0x00, 0x00, 0xff});
	sdl_render_line(renderer, project_to_camera(.{0, 0}), project_to_camera(.{0, 100}), .{0x00, 0xff, 0x00, 0xff});
	SDL_RenderPresent(renderer);
	// should_render = false;
}

draw_text :: (x: float, y: float, str: string, color: Vector4, $grow_up := false) {
	Iprof.zone_begin(cast(s64)Zones.draw_text);
	Iprof.zone_end();
	if !str return;
	y = window_height - y;
#if grow_up y -= iprof_config.font_character_height;
	sdl_color := to_sdl_color(color);
	surface: *SDL_Surface = TTF_RenderText_Blended(font, str.data, xx str.count, sdl_color);
	if surface == null {
		log_error("Can't render text '%' on surface: %", str, sdl_get_error());
		return;
	}
	defer SDL_DestroySurface(surface);
	texture: *SDL_Texture = SDL_CreateTextureFromSurface(renderer, surface);
	if texture == null {
		log_error("Can't convert surface to texture: %", sdl_get_error());
		return;
	}
	defer SDL_DestroyTexture(texture);
	text_bounds := SDL_FRect.{
		x = SDL_floorf(x),
		y = SDL_floorf(y),
		w = xx texture.w,
		h = xx texture.h,
	};
	if !SDL_RenderTexture(renderer, texture, null, *text_bounds) {
		log_error("Can't blit texture: %", sdl_get_error());
	}
}

text_width :: (s: string) -> float {
	Iprof.zone_begin(cast(s64)Zones.text_width);
	Iprof.zone_end();
	ok, width := sdl_measure_string(font, s);
	return xx width;
}

draw_rectangle :: (x0: float, y0: float, x1: float, y1: float, color: Vector4) {
	Iprof.zone_begin(cast(s64)Zones.draw_rectangle);
	Iprof.zone_end();
	y0 = window_height - y0; y1 = window_height - y1;
	height := abs(y1 - y0);
	fill_rect(renderer, .{min(x0, x1), min(y0, y1), abs(x1 - x0), height}, to_sdl_color(color));
}

draw_line :: (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color: Vector4) {
	Iprof.zone_begin(cast(s64)Zones.draw_line);
	defer Iprof.zone_end();
	sdl_render_lines(renderer, .[.{p0.x, window_height - p0.y}, .{p1.x, window_height - p1.y}, .{p2.x, window_height - p2.y}, .{p3.x, window_height - p3.y}, .{p0.x, window_height - p0.y}], to_sdl_color(color));
}

graph_begin :: (x: float, y: float, width: float, height: float) {}
graph_end :: (x: float, y: float, width: float, height: float) {}

init_zones :: () {
#insert -> string {
		sb: String_Builder;
		ti :: type_info(Zones);
		for member_name, member_index: ti.names {
			if member_index == 0 continue;
			print(*sb, "Iprof.zones[%1].name = \"%2\";", ti.values[member_index], member_name);
		}
		return builder_to_string(*sb);
	}
}

add_new_node :: inline (parent: *Node($T), child: Node(T)) -> *Node(T) {
	allocated := New(Node(T));
	allocated.* = child;
	array_add(*parent.children, allocated);
	return allocated;
}

update_required_size :: (using root: *Node(Node_Data), padding: float = 0.0) {
	min_size = 0.0;
	for child: children {
		update_required_size(child, padding);
		min_size += child.min_size + padding;
	}
	min_size -= padding;
	ok, text_width := sdl_measure_string(font, text);
	rect.w = max(40.0, xx text_width);
	rect.h = xx (font_height * 2);
	min_size = max(min_size, rect.w);
}

reform_graph :: (using root: *Node(Node_Data), padding: float = 0.0, padding_down: float = 0.0) {
	update_required_size(root, padding);
	left: float = rect.x + rect.w / 2 - (root.min_size / 2);
	for child, child_index: children {
		child.rect.x = left + child.min_size / 2 - child.rect.w / 2;
		child.rect.y = rect.y + rect.h + padding_down;
		left += child.min_size + padding;
		reform_graph(child, padding, padding_down);
	}
}

keybind_tree_to_graph :: (kb: Keybind) -> Node(Node_Data) {
	res := Node(Node_Data).{text = sprint("(%)-(%)", kb.mod, kb.key)};
	for kb.commands {
		com_node := New(Node(Node_Data));
		com_node.text = copy_string(it);
		array_add(*res.children, com_node);
	}
	for kb.next {
		child := New(Node(Node_Data));
		child.* = keybind_tree_to_graph(it);
		array_add(*res.children, child);
	}
	return res;
}

keybinds_root_to_graph :: (root: Keybind_Root) -> Node(Node_Data) {
	res := Node(Node_Data).{text = "root"};
	for mode_name: root.modes {
		mode_node := New(Node(Node_Data));
		mode_node.text = copy_string(mode_name);
		array_add(*res.children, mode_node);
	}
	root_node := New(Node(Node_Data));
	root_node.* = keybind_tree_to_graph(root.root);
	array_add(*res.children, root_node);
	return res;
}

main :: () {
	ctx = .{
		window_width = 800,
		window_height = 600,
		graph_portion = 0.5,
		camera_scale = 1.0,
	};
	keybinds_root = generate_keybinds("./keybinds.conf");
	graph = keybinds_root_to_graph(keybinds_root);
	check_sdl(SDL_Init(.VIDEO));
	check_sdl(SDL_CreateWindowAndRenderer("garph", window_width, window_height, .RESIZABLE, *window, *renderer));
	check_sdl(TTF_Init());
	SDL_SetRenderVSync(renderer, 1);
	Iprof.init_runtime();
	font = TTF_OpenFont(font_path, 15);
	assert(font != null, "Can't open font at %", font_path);
	font_height = TTF_GetFontHeight(font);
	reform_graph(*graph, 5.0, 20.0);
	iprof_config = .{
		line_spacing = cast(s32)(xx font_height * 1.2),
		font_character_height = cast(s32)font_height,
		draw_text = #bake_arguments draw_text(grow_up = false),
		text_width = text_width,
		draw_rectangle = draw_rectangle,
		draw_line = draw_line,
		graph_begin = graph_begin,
		graph_end = graph_end,
	};
	init_zones();
	event: SDL_Event;
	should_render = true;
	while main_loop := true {
		Iprof.update(true);
		Iprof.zone_begin(cast(s64)Zones.main_loop);
		while SDL_PollEvent(*event) {
			Iprof.zone_begin(cast(s64)Zones.events);
			defer Iprof.zone_end();
			if event.type == {
				case .QUIT;
				break main_loop;
				case .WINDOW_EXPOSED;
				should_render = true;
				case .WINDOW_PIXEL_SIZE_CHANGED;
				window_width = event.window.data1;
				window_height = event.window.data2;
				should_render = true;
				case .WINDOW_RESIZED;
				window_width = event.window.data1;
				window_height = event.window.data2;
				should_render = true;
				case .MOUSE_MOTION;
				Iprof.set_cursor_screen_coordinates(xx event.motion.x, xx (window_height - event.motion.y));
				mouse_x = xx event.motion.x;
				mouse_y = xx event.motion.y;
				if event.motion.state & .MIDDLE {
					camera.x -= event.motion.xrel / camera_scale;
					camera.y -= event.motion.yrel / camera_scale;
				}
				should_render = true;
				case .MOUSE_BUTTON_DOWN;
				if event.mouse.button == .LEFT
					Iprof.graph_select_sample();
				should_render = true;
				case .KEY_DOWN;
				if event.key.scancode == {
					case .TAB;
					Iprof.displayed_quantity = (Iprof.displayed_quantity + 1) % 4;
					case .UP;
					Iprof.move_cursor(1);
					case .DOWN;
					Iprof.move_cursor(-1);
					case .RETURN;
					if event.key.mod & (.SHIFT | .CTRL | .ALT) {
						Iprof.select_parent();
					} else {
						Iprof.select();
					}
				}
				case .MOUSE_WHEEL;
				modstate := SDL_GetModState();
				if modstate & .SHIFT {
					graph_portion += SDL_copysignf(0.1, event.wheel.y);
					graph_portion = clamp(graph_portion, 0.0, 1.0);
				} else {
#if false {
						new_font_size := TTF_GetFontSize(font) + SDL_copysignf(1, event.wheel.y);
						if new_font_size > 1.0 {
							TTF_SetFontSize(font, new_font_size);
							font_height = TTF_GetFontHeight(font);
							camera_scale += event.wheel.y / 10.0;
							camera_scale = max(camera_scale, 0.01);
						}
					} else {
						camera_scale += event.wheel.y / 10.0;
						camera_scale = max(camera_scale, 0.01);
						TTF_SetFontSize(font, camera_scale * 15.0);
						font_height = TTF_GetFontHeight(font);
					}
				}
				should_render = true;
			}
		}
		render();
		Iprof.zone_end();
		reset_temporary_storage();
		report = Iprof.create_report();
	}
	Iprof.update(true);
	Iprof.log_text_report(report);
}

#import,file "keybinds.jai" (SDL_Keycode, sdl_keycode_from_string);
Iprof :: #import "Iprof" (.CLIENT, true);
#import "Math";
#import,file "sdl3.jai";
#import "Basic";