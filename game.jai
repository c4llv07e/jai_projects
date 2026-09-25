ENABLE_VSYNC :: true;
DEBUG :: true;

Brush :: struct {
	rect: SDL_FRect;
	color: SDL_Color;
}

Scene :: struct {
	brushes: [..]Brush;
}

Player :: struct {
	using pos: SDL_FPoint;
	velocity: SDL_FPoint;
	max_speed: float32 = 400.0;
	accel_rate: float32 = 15.0;
	decel_rate: float32 = 25.0;
	size: float32 = 32;
}

Ctx :: struct {
	window: *SDL_Window;
	renderer: *SDL_Renderer;
	buttons: []bool;
	camera: SDL_FPoint;
	player: Player;
	scene: Scene;
	deltatime: float32;
	mouse_x, mouse_y: float32;
	world_mouse_x, world_mouse_y: float32;
	previous_frame_time: u64;
	current_frame_time: u64;
	keymod_state: SDL_Keymod;
#if DEBUG {
		render_fan_state: u8;
	}
	application_state: enum u32 {
		GAME :: 0;
		MAP_EDITOR;
	} = .GAME;
	brush_selector_rect: SDL_FRect = .{0, 0, 100, 100};
	selected_brush_index: s64 = 0;
}

check_sdl :: (status: bool, msg := "Error on calling sdl function", caller_loc := #caller_location) #expand {
	if (!status) {
		log("%: %: %\n", caller_loc, msg, sdl_get_error(), flags=.ERROR);
		exit(-1);
	}
}

project_to_camera :: (using ctx: *Ctx, rect: SDL_FRect) -> SDL_FRect {
	width, height: s32;
	SDL_GetWindowSizeInPixels(window, *width, *height);
	return .{
		rect.x - camera.x + width / 2,
		rect.y - camera.y + height / 2,
		rect.w,
		rect.h,
	};
}

project_to_camera :: (using ctx: *Ctx, point: SDL_FPoint) -> SDL_FPoint {
	width, height: s32;
	SDL_GetWindowSizeInPixels(window, *width, *height);
	return .{
		point.x - camera.x + width / 2,
		point.y - camera.y + height / 2,
	};
}

project_to_camera :: (using ctx: *Ctx, x: float32, y: float32) -> float32, float32 {
	width, height: s32;
	SDL_GetWindowSizeInPixels(window, *width, *height);
	return x - camera.x + width / 2, y - camera.y + height / 2;
}

project_from_camera :: (using ctx: *Ctx, x: float32, y: float32) -> float32, float32 {
	width, height: s32;
	SDL_GetWindowSizeInPixels(window, *width, *height);
	return x + camera.x - width / 2, y + camera.y - height / 2;
}

render_rect_line_on_point :: (using ctx: *Ctx, point: SDL_FPoint, size: float) {
	rect := SDL_FRect.{
		point.x - size / 2,
		point.y - size / 2,
		size, size,
	};
	SDL_RenderRect(renderer, *rect);
}

// ray_direction must be normalized
slab_method :: (aabb: SDL_FRect, ray_origin: SDL_FPoint, ray_direction: SDL_FPoint) -> hit: bool, t_hit: float32, normal: SDL_FPoint {
	tmin := 0.0; // Maybe should be -FLOAT32_INFINITY.
	tmax := FLOAT32_INFINITY;
	rect_min := float32.[aabb.x, aabb.y];
	rect_max := float32.[aabb.x + aabb.w, aabb.y + aabb.h];
	ray_dir  := float32.[ray_direction.x, ray_direction.y];
	ray_orig := float32.[ray_origin.x, ray_origin.y];
	out_normal := SDL_FPoint.{0, 0};
	for 0..1 {
		if SDL_fabsf(ray_dir[it]) < 1.0e-3 {
			if ray_orig[it] < rect_min[it] || ray_orig[it] > rect_max[it] {
				return false, 0, .{0, 0};
			}
		} else {
			ood := 1.0 / ray_dir[it];
			t1 := (rect_min[it] - ray_orig[it]) * ood;
			t2 := (rect_max[it] - ray_orig[it]) * ood;
			if t1 > t2 {
				Swap(*t1, *t2);
			}
			if t1 > tmin {
				tmin = t1;
				sign := ifx ray_dir[it] > 0.0 then -1.0 else 1.0;
				out_normal = .{0, 0}; 
				if it == 0 then out_normal.x = sign;
				else out_normal.y = sign;
			}
			tmax = min(tmax, t2);
			if tmin > tmax return false, 0, .{0, 0};
		}
	}
	if tmin == 0.0 { // Ray inside rect.
		return true, 0.0, .{0, 0}; 
	}
	return true, tmin, out_normal;
}

DEBUG_SLAB :: false;
slab_method :: (aabb: SDL_FRect, ray_origin: SDL_FRect, ray_direction: SDL_FPoint) -> hit: bool, t_hit: float32, normal: SDL_FPoint {
#if DEBUG_SLAB {
		sdl_set_color(_ctx.renderer, .{0xff, 0xff, 0xff, 0xff});
		rect := aabb + SDL_FRect.{-ray_origin.w / 2, -ray_origin.h / 2, ray_origin.w, ray_origin.h};
		projected := project_to_camera(_ctx, rect);
		SDL_RenderRect(_ctx.renderer, *projected);
	}
	hit, t_hit, normal := slab_method(aabb + SDL_FRect.{-ray_origin.w / 2, -ray_origin.h / 2, ray_origin.w, ray_origin.h},
					  SDL_FPoint.{ray_origin.x + ray_origin.w / 2, ray_origin.y + ray_origin.h / 2}, ray_direction);
	return hit, t_hit, normal;
}

render_fan :: (using ctx: *Ctx) {
#if DEBUG {
		render_fan_size :: 0x20;
		sdl_set_color(renderer, .{0x20, 0x20, 0x20, 0xff});
		render_fan_rect := SDL_FRect.{0, 0, render_fan_size, render_fan_size};
		SDL_RenderFillRect(renderer, *render_fan_rect);
		sdl_set_color(renderer, .{0x40, 0x40, 0x40, 0xff});
		render_fan_blade_rect := SDL_FRect.{
			xx ((render_fan_state % 2) * render_fan_size / 2),
			xx ((render_fan_state / 2) * render_fan_size / 2),
			render_fan_size / 2, render_fan_size / 2};
		SDL_RenderFillRect(renderer, *render_fan_blade_rect);
		render_fan_state = (render_fan_state + 1) % 4;
	} else {
	}
}

render_scene :: (using ctx: *Ctx) {
	for scene.brushes {
		sdl_set_color(renderer, it.color);
		rect := project_to_camera(ctx, it.rect);
		SDL_RenderRect(renderer, *rect);
	}
}

save_scene :: (using ctx: *Ctx, filepath: string) {
	sb: String_Builder;
	print(*sb, "brushes\n");
	for scene.brushes {
		print(*sb, "% % % % - % % % %\n", it.rect.x, it.rect.y, it.rect.w, it.rect.h,
		      it.color.r, it.color.g, it.color.b, it.color.a);
	}
	write_entire_file(filepath, *sb);
}

consume_word :: (sentence: *string) -> word: string {
	word, rhs := break_by_spaces(sentence.*);
	sentence.* = rhs;
	return word;
}

consume_float :: (data: *string) -> result: float32 {
	str := consume_word(data);
	res := string_to_float(str);
	return res;
}

consume_int :: (data: *string) -> result: int {
	str := consume_word(data);
	res := string_to_int(str);
	return res;
}

load_scene :: (using ctx: *Ctx, filepath: string) -> bool {
	if ctx.scene.brushes.data != null {
		array_reset(*ctx.scene.brushes);
	}
	data, ok := read_entire_file(filepath,, temp);
	if !ok {
		log("Can't open scene file %", filepath);
		return false;
	}
	state: enum u32 {
		INIT :: 0;
		READING_BRUSHES;
	} = .INIT;
	while true {
		line, has_line := consume_next_line(*data);
		if !has_line break;
		line = eat_spaces(line);
		if line.count == 0 continue;
		if begins_with(line, "brushes") {
			state = .READING_BRUSHES;
			continue;
		}
		if state == {
			case .READING_BRUSHES;
			x := consume_float(*line);
			y := consume_float(*line);
			w := consume_float(*line);
			h := consume_float(*line);
			separator := consume_word(*line);
			if separator != "-" {
				log("Expected separator, got %", separator);
				return false;
			}
			r := consume_int(*line);
			g := consume_int(*line);
			b := consume_int(*line);
			a := consume_int(*line);
			if r > 255 || g > 255 || b > 255 || a > 255 {
				log("Color {%, %, %, %} is too hdr for us", r, g, b, a);
			}
			array_add(*scene.brushes, Brush.{rect=.{x, y, w, h}, color=.{xx r, xx g, xx b, xx a}});
			case;
			log("Can't decide what state we are in");
			return false;
		}
	}
	return true;
}

sdl_render_line :: (renderer: *SDL_Renderer, from: SDL_FPoint, to: SDL_FPoint) {
	SDL_RenderLine(renderer, from.x, from.y, to.x, to.y);
}

vec_length :: inline (using vec: SDL_FPoint) -> float32 {
	return SDL_sqrtf(x*x + y*y);
}

normalize :: (vec: SDL_FPoint) -> SDL_FPoint {
	return vec / vec_length(vec);
}

rect_from_point :: (using point: SDL_FPoint, size: float32) -> SDL_FRect {
	return .{x - size / 2, y - size / 2, size, size};
}

RENDER_FAN :: false;
render :: (using ctx: *Ctx) {
	sdl_set_color(renderer, .{0x00, 0x00, 0x00, 0xff});
	SDL_RenderClear(renderer);
	if application_state == .MAP_EDITOR {
		sdl_set_color(renderer, .{0x80, 0xc0, 0x80, 0xff});
		width, height: s32;
		SDL_GetWindowSizeInPixels(window, *width, *height);
		rect := SDL_FRect.{0, 0, xx width, xx height};
		SDL_RenderRect(renderer, *rect);
	}
	sdl_set_color(renderer, .{0xff, 0x00, 0x00, 0xff});
	render_rect_line_on_point(ctx, project_to_camera(ctx, player.pos), player.size);
	render_scene(ctx);
	if application_state == .MAP_EDITOR {
		sdl_set_color(renderer, .{0x20, 0x20, 0x20, 0xff});
		SDL_RenderFillRect(renderer, *brush_selector_rect);
		sdl_set_color(renderer, .{0x20, 0x60, 0x20, 0xff});
		SDL_RenderRect(renderer, *brush_selector_rect);
		for brush, brush_index: scene.brushes {
			padding :: 4.0;
			element_size :: 16.0;
			sdl_set_color(renderer, brush.color);
			rect := SDL_FRect.{
				brush_selector_rect.x + padding,
				brush_selector_rect.y + padding + ((element_size + padding) * brush_index),
				brush_selector_rect.w - padding * 2,
				element_size,
			};
			if selected_brush_index == brush_index {
				SDL_RenderFillRect(renderer, *rect);
			} else {
				SDL_RenderRect(renderer, *rect);
			}
		}
	}
#if RENDER_FAN {
		render_fan(ctx);
	}
	SDL_RenderPresent(renderer);
}

dot_product :: (a: SDL_FPoint, b: SDL_FPoint) -> float32 {
	return a.x * b.x + a.y * b.y;
}

_ctx: *Ctx;
main :: () {
	using ctx := Ctx.{
	};
	_ctx = *ctx;
	initial_width :: 800;
	initial_height :: 600;
	check_sdl(SDL_Init(.VIDEO), "Can't init SDL");
	check_sdl(SDL_CreateWindowAndRenderer("game", initial_width, initial_height, .RESIZABLE, *window, *renderer), "Can't create SDL output");
#if ENABLE_VSYNC {
		SDL_SetRenderVSync(renderer, 1);
	}
	buttons.data = SDL_GetKeyboardState(xx *buttons.count);
	event: SDL_Event;
	load_scene(*ctx, "main.scene");
	previous_frame_time = SDL_GetTicks();
	player_move: SDL_FPoint;
	player.x = -60;
	while main_loop := true {
		current_frame_time := SDL_GetTicks();
		deltatime = (current_frame_time - previous_frame_time) / 1000.0;
		previous_frame_time = current_frame_time;
		keymod_state = SDL_GetModState();
		while SDL_PollEvent(*event) {
			if event.type == {
				case .QUIT;
				break main_loop;
				case .KEY_DOWN;
				if event.key.scancode == {
					case .S;
					if keymod_state & .CTRL {
						save_scene(*ctx, "main.scene");
					}
					case .L;
					if keymod_state & .CTRL {
						load_scene(*ctx, "main.scene");
					}
					case .M;
					if keymod_state & .CTRL {
						if application_state == .GAME {
							application_state = .MAP_EDITOR;
						} else {
							application_state = .GAME;
						}
					}
				}
				case .MOUSE_MOTION;
				mouse_x = event.motion.x;
				mouse_y = event.motion.y;
			}
		}
		desired_move := SDL_FPoint.{
			x = cast(float32)(cast(s8)buttons[SDL_Scancode.RIGHT] - cast(s8)buttons[SDL_Scancode.LEFT]),
			y = cast(float32)(cast(s8)buttons[SDL_Scancode.DOWN] - cast(s8)buttons[SDL_Scancode.UP]),
		};
		desired_length := vec_length(desired_move);
		if desired_length > 0.0 {
			desired_move /= desired_length;
		}
		desired_move *= player.max_speed;
		if application_state == .GAME {
			rate := SDL_FPoint.{
				x = ifx desired_move.x != 0.0 then player.accel_rate else player.decel_rate,
				y = ifx desired_move.y != 0.0 then player.accel_rate else player.decel_rate,
			};
			player.velocity += (desired_move - player.velocity) * (.{1.0, 1.0} - SDL_expf(rate * -deltatime));
			if SDL_fabsf(player.velocity.x) < 0.1 player.velocity.x = 0.0;
			if SDL_fabsf(player.velocity.y) < 0.1 player.velocity.y = 0.0;
			frame_velocity := player.velocity * deltatime;
			if frame_velocity.x != 0 || frame_velocity.y != 0 {
				for 0..2 {
					move_len := vec_length(player.velocity);
					if move_len < 1.0e-4 break;
					norm_move := frame_velocity / move_len;
					closest_t := move_len;
					closest_normal: SDL_FPoint;
					hit_anything := false;
					for scene.brushes {
						hit, t_hit, normal := slab_method(it.rect, rect_from_point(player.pos, player.size), norm_move);
						if hit && t_hit >= 0 && t_hit < closest_t {
							closest_t = t_hit;
							closest_normal = normal;
							hit_anything = true;
						}
					}
					if hit_anything {
						padding :: 0.01;
						t_to_move := max(0.0, closest_t - padding);
						player.pos += norm_move * t_to_move;
						remaining_length := move_len - closest_t;
						remaining_move := norm_move * remaining_length;
						dot_frame := dot_product(remaining_move, closest_normal);
						frame_velocity = remaining_move - (closest_normal * dot_frame);
						dot_vel := dot_product(player.velocity, closest_normal);
						if dot_vel < 0.0 {
							player.velocity = player.velocity - (closest_normal * dot_vel);
						}
					} else {
						player.pos += frame_velocity;
						break;
					}
				}
			}
		} else {
			player.pos += desired_move * deltatime;
		}
		camera = player.pos;
		world_mouse_x, world_mouse_y = project_from_camera(*ctx, mouse_x, mouse_y);
		render(*ctx);
	}
}

#import "String";
#import "Text_File_Handler";
#import "File";
#import "Basic";
#import "Math";
#import,file "sdl3.jai";