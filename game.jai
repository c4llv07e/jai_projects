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
	speed: float32 = 100;
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
#if DEBUG {
		render_fan_state: u8;
	}
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
			sign := ifx ood < 0.0 then 1.0 else -1.0;
			if t1 > t2 {
				Swap(*t1, *t2);
				sign = -sign;
			}
			if t1 > tmin {
				tmin = t1;
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

slab_method :: (aabb: SDL_FRect, ray_origin: SDL_FRect, ray_direction: SDL_FPoint) -> hit: bool, t_hit: float32, normal: SDL_FPoint {
	hit, t_hit, normal := slab_method(aabb + SDL_FRect.{-ray_origin.w, -ray_origin.h, ray_origin.w, ray_origin.h},
					  SDL_FPoint.{ray_origin.x, ray_origin.y}, ray_direction);
	return hit, t_hit, normal;
}

render_fan :: (using ctx: *Ctx) {
#if DEBUG {
		sdl_set_color(renderer, .{0x20, 0x20, 0x20, 0xff});
		render_fan_rect := SDL_FRect.{0, 0, 0x40, 0x40};
		SDL_RenderFillRect(renderer, *render_fan_rect);
		sdl_set_color(renderer, .{0x40, 0x40, 0x40, 0xff});
		render_fan_blade_rect := SDL_FRect.{
			xx ((render_fan_state % 2) * 0x20),
			xx ((render_fan_state / 2) * 0x20),
			0x20, 0x20};
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

load_scene :: (using ctx: *Ctx) {
	if ctx.scene.brushes.data != null {
		array_free(ctx.scene.brushes);
	}
	array_add(*ctx.scene.brushes, .{
			  rect = .{0, 0, 200, 20},
			  color = .{0x40, 0x60, 0x40, 0xff},
		  });
	array_add(*ctx.scene.brushes, .{
			  rect = .{200, 0, 20, 200},
			  color = .{0x40, 0x60, 0x40, 0xff},
		  });
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

render :: (using ctx: *Ctx) {
	sdl_set_color(renderer, .{0x00, 0x00, 0x00, 0xff});
	SDL_RenderClear(renderer);
	sdl_set_color(renderer, .{0xff, 0x00, 0x00, 0xff});
	render_rect_line_on_point(ctx, project_to_camera(ctx, player.pos), player.size);
	sdl_set_color(renderer, .{0xff, 0x00, 0x00, 0xff});
	render_rect_line_on_point(ctx, .{mouse_x, mouse_y}, 32);
	sdl_set_color(renderer, .{0x00, 0x00, 0xff, 0xff});
	render_rect_line_on_point(ctx, project_to_camera(ctx, .{world_mouse_x, world_mouse_y}), 16);
	sdl_set_color(renderer, .{0xff, 0xff, 0x00, 0xff});
	sdl_render_line(renderer, project_to_camera(ctx, player.pos), .{mouse_x, mouse_y});
	for scene.brushes {
		line := SDL_FPoint.{world_mouse_x, world_mouse_y} - player.pos;
		line_length := vec_length(line);
		hit, t_hit, normal := slab_method(it.rect, rect_from_point(player.pos, player.size), line / line_length);
		if hit && t_hit <= line_length {
			sdl_set_color(renderer, .{0x00, 0xff, 0xff, 0xff});
			render_rect_line_on_point(ctx, project_to_camera(ctx, player.pos + line / line_length * t_hit), 32);
		}
	}
	render_scene(ctx);
	render_fan(ctx);
	SDL_RenderPresent(renderer);
}

main :: () {
	using ctx := Ctx.{
	};
	initial_width :: 800;
	initial_height :: 600;
	check_sdl(SDL_Init(.VIDEO), "Can't init SDL");
	check_sdl(SDL_CreateWindowAndRenderer("game", initial_width, initial_height, .RESIZABLE, *window, *renderer), "Can't create SDL output");
#if ENABLE_VSYNC {
		SDL_SetRenderVSync(renderer, 1);
	}
	buttons.data = SDL_GetKeyboardState(xx *buttons.count);
	event: SDL_Event;
	load_scene(*ctx);
	player.speed = 400;
	previous_frame_time = SDL_GetTicks();
	while main_loop := true {
		current_frame_time := SDL_GetTicks();
		deltatime = (current_frame_time - previous_frame_time) / 1000.0;
		previous_frame_time = current_frame_time;
		while SDL_PollEvent(*event) {
			if event.type == {
				case .QUIT;
				break main_loop;
				case .MOUSE_MOTION;
				mouse_x = event.motion.x;
				mouse_y = event.motion.y;
			}
		}
		player.pos.y += player.speed * (cast(s8)buttons[SDL_Scancode.DOWN] - cast(s8)buttons[SDL_Scancode.UP]) * deltatime;
		player.pos.x += player.speed * (cast(s8)buttons[SDL_Scancode.RIGHT] - cast(s8)buttons[SDL_Scancode.LEFT]) * deltatime;
		camera = player.pos;
		world_mouse_x, world_mouse_y = project_from_camera(*ctx, mouse_x, mouse_y);
		render(*ctx);
	}
}

#import "Basic";
#import "Math";
#import,file "sdl3.jai";