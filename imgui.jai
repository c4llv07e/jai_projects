// Was inspired by Ryan Fleury's UI concepts.

#module_parameters (Render : $I/interface Render_Interface = Render_Interface(void, s32)) () {
	Render_Interface :: struct(render_data_type: Type, font_type: Type) {
		render_text :: inline (render_data: render_data_type, x: float32, y: float32, text: string, color: Color = .{0xe3, 0xe3, 0xe3, 0xff}, font_size: float32 = 24.0, font: font_type) {};
		measure_string :: inline (render_data: render_data_type, font: font_type, text: string) {};
		render_rect :: inline (render_data: render_data_type, rect: Rect, color: Color) {};
		render_fill_rect :: inline (render_data: render_data_type, rect: Rect, color: Color) {};
	}
};

Color :: struct {
	r, g, b, a: u8;
}

Rect :: struct {
	x, y: float32;
	w, h: float32;
#place x;
	xy: Vector2 = ---;
#place x;
	pos: [2] float32 = ---;
#place w;
	wh: Vector2 = ---;
#place w;
	size: [2] float32 = ---;
#place x;
	v: [4] float32 = ---;
}

Window_State :: struct {
	width: s32;
	height: s32;
}

Widget_Flags :: enum_flags u32 {
	Clickable;
	Draw_Background;
	Draw_Border;
	Draw_Text;
	Hot_Effect;
	Floating_X;
	Floating_Y;
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
	X :: 0;
	Y :: 1;
}

Mouse_Buttons_State :: enum_flags u8 {
	LEFT;
	RIGHT;
	MIDDLE;
	M4;
	M5;
}

Widget_Frame_Signal :: struct {
	clicked: Mouse_Buttons_State;
}

Widget_Continious_Signal :: struct {
	holding: bool;
}

Widget_Signal :: struct {
	using frame: Widget_Frame_Signal;
	using continious: Widget_Continious_Signal;
}

Stack :: struct(element_type: Type, default: element_type) {
	array: [..]element_type;
	pop_next: bool;
}

stack_push :: (stack: *Stack, value: stack.element_type) {
	array_add(*stack.array, value);
}

stack_pop :: (stack: *Stack) -> stack.element_type {
	stack.pop_next = false;
	return pop(*stack.array);
}

stack_peek :: (stack: Stack) -> stack.element_type {
	return peek(stack.array);
}

stack_set_next :: (stack: *Stack, value: stack.element_type) {
	assert(!stack.pop_next, "Trying to put multiple values for next element!");
	stack_push(stack, value);
	stack.pop_next = true;
}

Widget_Stacks :: struct {
	parents: Stack(*Widget, *null_widget);
	seed: Stack(u64, 123);
	pref_width: Stack(Widget_Size, .{property = .Pixels, value = 250.0});
	pref_height: Stack(Widget_Size, .{property = .Pixels, value = 50.0});
	text_color: Stack(Color, .{0xe3, 0xe3, 0xe3, 0xff});
	background_color: Stack(Color, .{0x00, 0x00, 0x00, 0x00});
	border_color: Stack(Color, .{0x00, 0x00, 0x00, 0x00});
	layout_dir: Stack(Axies, .X);
	font: Stack(Render.font_type, #run -> Render.font_type {x: Render.font_type; return x;}); // TODO(c4llv07e): This is sooo bad...
	font_size: Stack(float32, 24.0);
	flags: Stack(Widget_Flags, 0);
	floating_x: Stack(float32, 0);
	floating_y: Stack(float32, 0);
}

pop_unused :: (stacks: *Widget_Stacks) {
#insert -> string {
		sb: String_Builder;
		ti :: type_info(Widget_Stacks);
		for stack_ti: ti.members {
			if stack_ti.type.type != .STRUCT continue;
			stack_struct_ti := cast(*Type_Info_Struct)stack_ti.type;
			print_to_builder(*sb, "if stacks.%1.pop_next then stack_pop(*stacks.%1);\n", stack_ti.name);
		}
		return builder_to_string(*sb);
	}
}

init_stacks :: (stacks: *Widget_Stacks) {
#insert -> string {
		sb: String_Builder;
		ti :: type_info(Widget_Stacks);
		for stack_ti: ti.members {
			if stack_ti.type.type != .STRUCT continue;
			stack_struct_ti := cast(*Type_Info_Struct)stack_ti.type;
			print_to_builder(*sb, "array_reset(*stacks.%1.array);\n", stack_ti.name);
			print_to_builder(*sb, "stack_push(*stacks.%1, stacks.%1.default);\n", stack_ti.name);
		}
		return builder_to_string(*sb);
	}
}

Widget_Theme :: struct {
	background_color: Color;
	border_color: Color;
	font_size: float32;
}

Gui_State :: struct {
	widget_root: *Widget;
	widgets: [..]*Widget;
	stacks: Widget_Stacks;
	theme: Widget_Theme;
	mouse_pos: Vector2;
	frame_index: s64;
}

Widget :: struct {
	pref_size: [#run enum_values_as_s64(Axies).count]Widget_Size;
	child_dir: Axies;
	font: *Render.font_type;
	flags: Widget_Flags;
	key: u64;
	text: string;
	using rect: Rect;
	border_color: Color;
	background_color: Color;
	text_color: Color;
	font_size: float32;
	signal: Widget_Signal;
	continious_signal: Widget_Continious_Signal; // TODO(c4llv07e): Rename it.
	last_frame_index: s64;
	next, prev, first, last, parent: *Widget;
	layout_dir: Axies;
}
null_widget: Widget;

is_intersecting :: (rect: Rect, point: Vector2) -> bool {
	return point.x >= rect.x && point.x <= rect.x + rect.w && point.y >= rect.y && point.y <= rect.y + rect.h;
}

key_from_string :: (seed: u64, str: string) -> u64 {
	// TODO(c4llv07e): I am just learning, but this seed could be problematic in the future.
	// Update: Works fine, because we don't use hash table. Fix when hash table arrives.
	return seed + djb2_hash(str);
}

is_null_widget :: (widget: *Widget) -> bool {
	return (widget == *null_widget) || (widget == null);
}

get_widget_by_key :: (using gui_state: *Gui_State, key: u64) -> *Widget {
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

init_widget_by_key :: (using gui_state: *Gui_State, key: u64, flags: Widget_Flags) -> *Widget {
	parent := stack_peek(stacks.parents);
	widget := get_widget_by_key(gui_state, key);
	if is_null_widget(widget) {
		widget = alloc(size_of(Widget));
		array_add(*widgets, widget);
	}
	widget.key = key;
	widget.last_frame_index = frame_index;
	widget.font = stack_peek(stacks.font);
	if stacks.font_size.array.count > 1 {
		widget.font_size = stack_peek(stacks.font_size);
	} else {
		widget.font_size = gui_state.theme.font_size;
	}
	widget.text_color = stack_peek(stacks.text_color);
	if stacks.background_color.array.count > 1 {
		widget.background_color = stack_peek(stacks.background_color);
	} else {
		widget.background_color = gui_state.theme.background_color;
	}
	if stacks.border_color.array.count > 1 {
		widget.border_color = stack_peek(stacks.border_color);
	} else {
		widget.border_color = gui_state.theme.border_color;
	}
	additional_flags := stack_peek(stacks.flags);
	widget.flags = flags | additional_flags;
	widget.pref_size[Axies.X] = stack_peek(stacks.pref_width);
	widget.pref_size[Axies.Y] = stack_peek(stacks.pref_height);
	widget.first = *null_widget;
	widget.last = *null_widget;
	widget.layout_dir = stack_peek(stacks.layout_dir);
	if stacks.floating_y.array.count > 1 {
		widget.flags |= .Floating_Y;
		widget.rect.y = stack_peek(stacks.floating_y);
	}
	if stacks.floating_x.array.count > 1 {
		widget.flags |= .Floating_X;
		widget.rect.x = stack_peek(stacks.floating_x);
	}
	pop_unused(*stacks);
	append_to_parent(parent, widget);
	return widget;
}

init_widget_by_string :: (using gui_state: *Gui_State, str: string, flags: Widget_Flags) -> *Widget {
	seed := stack_peek(stacks.seed);
	key := key_from_string(seed, str);
	widget := init_widget_by_key(gui_state, key, flags);
	if flags & .Draw_Text {
		widget.text = str;
	}
	return widget;
}

gui_label :: (using gui_state: *Gui_State, fmt: string, args: ..Any) -> Widget_Signal {
	text: string = fmt;
	if args.count > 0 {
		text = tprint(fmt, ..args);
	}
	widget := init_widget_by_string(gui_state, text, .Draw_Text);
	return widget.signal;
} @PrintLike;

gui_button :: (using gui_state: *Gui_State, text: string) -> Widget_Signal {
	widget := init_widget_by_string(gui_state, text, .Clickable | .Draw_Border | .Draw_Background | .Draw_Text);
	return widget.signal;
}

gui_slider :: (using gui_state: *Gui_State, value: *float32, from := 0.0, to := 1.0) -> Widget_Signal {
	seed := stack_peek(stacks.seed);
	key :u64= seed * cast(u64)value;
	stack_set_next(*gui_state.stacks.layout_dir, .X);
	frame := init_widget_by_key(gui_state, key, .Draw_Border | .Clickable);
	if frame.signal.holding {
		value.* = lerp(from, to, (gui_state.mouse_pos.x - frame.rect.x) / frame.rect.w);
	}
	stack_set_next(*gui_state.stacks.parents, frame);
	percent := clamp(((value.* - from) / (to - from)), 0.0, 1.0);
	stack_set_next(*gui_state.stacks.pref_width, .{property = .Percent, value = percent});
	space := init_widget_by_key(gui_state, key + 2, 0);
	stack_set_next(*gui_state.stacks.parents, frame);
	stack_set_next(*gui_state.stacks.pref_height, .{property = .Percent, value = 1.0});
	stack_set_next(*gui_state.stacks.pref_width, .{property = .Pixels, value = 10.0});
	stack_set_next(*gui_state.stacks.background_color, .{0xff, 0x00, 0x00, 0xff});
	slider := init_widget_by_key(gui_state, key + 1, .Draw_Background);
	return frame.signal;
}

draw_widget :: (using gui_state: *Gui_State, render_data: Render.render_data_type, widget: *Widget) {
	if widget.flags & .Draw_Background && widget.background_color.a > 0 {
		Render.render_fill_rect(render_data, widget.rect, widget.background_color);
	}
	if widget.flags & .Draw_Border && widget.border_color.a > 0 {
		Render.render_rect(render_data, widget.rect, widget.border_color);
	}
	if widget.flags & .Draw_Text {
		Render.render_text(render_data, widget.x, widget.y, widget.text, widget.text_color, widget.font_size, widget.font);
	}
}

debug_widget :: (using gui_state: *Gui_State, render_data: Render.render_data_type, font: Render.font_type, widget: *Widget, x := 300.0, y := 0.0) -> y: float32 {
	Render.render_text(render_data, x, y, tprint("rect at %", widget.font_size, widget.rect), color = .{0xe3, 0xe3, 0xe3, 0xff}, font_size = 24, font = font);
	y += 24;
	child := widget.first;
	while!is_null_widget(child) {
		y = debug_widget(gui_state, render_data, font, child, x + 24, y);
		child = child.next;
	}
	return y;
}

gui_render :: (using gui_state: *Gui_State, render_data: Render.render_data_type) {
	widget := widget_root;
	while !is_null_widget(widget) {
		draw_widget(gui_state, render_data, widget);
		widget = iterate_children(widget_root, widget);
	}
}

handle_mouse_down :: (using gui_state: *Gui_State, point: Vector2, buttons: Mouse_Buttons_State) {
	for widget: widgets {
		if is_intersecting(widget.rect, point) && widget.flags & .Clickable {
			widget.signal.clicked |= .LEFT;
			widget.signal.holding = true;
		}
	}
}

handle_mouse_up :: (using gui_state: *Gui_State, point: Vector2, buttons: Mouse_Buttons_State) {
	for widget: widgets {
		widget.signal.holding = false;
	}
}

handle_mouse_move :: (using gui_state: *Gui_State, point: Vector2) {
	gui_state.mouse_pos = point;
}

widget_reset_frame_signal :: (using gui_state: *Gui_State) {
	for widget: widgets {
		memset(*widget.signal.frame, 0, size_of(Widget_Frame_Signal));
	}
}

prune_old_widgets :: (using gui_state: *Gui_State) {
	for widget: widgets {
		if widget.last_frame_index < frame_index {
			remove;
		}
	}
	frame_index += 1;
}

calculate_layout_standalone :: (using gui_state: *Gui_State, root: *Widget, dir: Axies) {
	widget := root;
	while !is_null_widget(widget) {
		if widget.pref_size[dir].property == {
			case .Pixels;
			widget.rect.size[dir] = widget.pref_size[dir].value;
			case .Content;
			if dir == .X {
				width := Render.measure_string(widget.font, widget.text, widget.font_size);
				widget.rect.w = width + widget.pref_size[Axies.X].value;
			} else {
				widget.rect.h = widget.font_size;
			}
		}
		widget = iterate_children(root, widget);
	}
}

calculate_layout_upwards :: (using gui_state: *Gui_State, root: *Widget, dir: Axies) {
	widget := root;
	while !is_null_widget(widget) {
		if widget.pref_size[dir].property == {
			case .Percent;
			fixed_parent := *null_widget;
			parent := widget.parent;
			while !is_null_widget(parent) {
				if (parent.pref_size[dir].property == .Pixels ||
				    parent.pref_size[dir].property == .Percent ||
				    parent.pref_size[dir].property == .Content) {
					fixed_parent = parent;
				}
				parent = parent.parent;
				break;
			}
			widget.rect.size[dir] = fixed_parent.rect.size[dir] * widget.pref_size[dir].value;
		}
		widget = iterate_children(root, widget);
	}
}

calculate_layout_downwards :: (using gui_state: *Gui_State, root: *Widget, dir: Axies) {
	widget := root.first;
	while !is_null_widget(widget) {
		calculate_layout_downwards(gui_state, widget, dir);
		widget = widget.next;
	}
	if root.pref_size[dir].property == .Shrink {
		if dir == root.layout_dir {
			sum_size: float32 = 0.0;
			widget = root.first;
			while !is_null_widget(widget) {
				sum_size += widget.rect.size[dir];
				widget = widget.next;
			}
			root.rect.size[dir] = sum_size;
		} else {
			max_size: float32 = 0.0;
			widget = root.first;
			while !is_null_widget(widget) {
				max_size = max(widget.rect.size[dir], max_size);
				widget = widget.next;
			}
			root.rect.size[dir] = max_size;
		}
	}
}

calculate_layout_position :: (using gui_state: *Gui_State, root: *Widget, dir: Axies) {
	widget := root;
	while !is_null_widget(widget) {
		position: float32 = 0.0;
		child := widget.first;
		while !is_null_widget(child) {
			if !(child.flags & (Widget_Flags.Floating_X<<dir)) {
				if widget.layout_dir == dir {
					child.rect.pos[dir] = widget.rect.pos[dir] + position;
					position += child.rect.size[dir];
				} else {
					child.rect.pos[dir] = widget.rect.pos[dir];
				}
			}
			child = child.next;
		}
		widget = iterate_children(root, widget);
	}
}

calculate_layout :: (using gui_state: *Gui_State, root: *Widget, dir: Axies) {
	calculate_layout_standalone(gui_state, root, dir);
	calculate_layout_upwards(gui_state, root, dir);
	calculate_layout_downwards(gui_state, root, dir);
	calculate_layout_position(gui_state, root, dir);
}

gui_panel_begin :: (using gui_state: *Gui_State, name: string) -> *Widget {
	widget := init_widget_by_string(gui_state, name, .Draw_Border | .Draw_Background);
	stack_push(*stacks.parents, widget);
	return widget;
}

gui_panel_end :: (using gui_state: *Gui_State) -> Widget_Signal {
	widget := stack_pop(*stacks.parents);
	return widget.signal;
}

gui_begin :: (using gui_state: *Gui_State, window_state: Window_State) {
	prune_old_widgets(gui_state); // TODO(c4llv07e): I can't even be sure if I need to prune widgets anymore. But I don't want to check it for now.
	init_stacks(*stacks);
	stack_set_next(*stacks.pref_width, .{property = .Pixels, value = xx window_state.width});
	stack_set_next(*stacks.pref_height, .{property = .Pixels, value = xx window_state.height});
	stack_set_next(*stacks.layout_dir, .Y);
	gui_state.widget_root = init_widget_by_string(gui_state, tprint("id = %", gui_state.frame_index), 0);
	stack_push(*stacks.parents, gui_state.widget_root);
}

gui_end :: (using gui_state: *Gui_State) {
	stack_pop(*stacks.parents);
	for dir: enum_values_as_s64(Axies) {
		calculate_layout(gui_state, gui_state.widget_root, cast(Axies)dir);
	}
	widget_reset_frame_signal(gui_state);
}

#import "Math";
#import "Hash";
#import "Basic";