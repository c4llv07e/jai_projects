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
}

Ctx :: struct {
	window: *SDL_Window;
	renderer: *SDL_Renderer;
	buttons: []bool;
	camera: SDL_FPoint;
	player: Player;
	scene: Scene;
	deltatime: float32;
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

render_rect_line_on_point :: (using ctx: *Ctx, point: SDL_FPoint, size: float) {
	rect := SDL_FRect.{
		point.x - size / 2,
		point.y - size / 2,
		size, size,
	};
	SDL_RenderRect(renderer, *rect);
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
			}
		}
		player.pos.y += player.speed * (cast(s8)buttons[SDL_Scancode.DOWN] - cast(s8)buttons[SDL_Scancode.UP]) * deltatime;
		player.pos.x += player.speed * (cast(s8)buttons[SDL_Scancode.RIGHT] - cast(s8)buttons[SDL_Scancode.LEFT]) * deltatime;
		camera = player.pos;
		sdl_set_color(renderer, .{0x00, 0x00, 0x00, 0xff});
		SDL_RenderClear(renderer);
		sdl_set_color(renderer, .{0xff, 0x00, 0x00, 0xff});
		render_rect_line_on_point(*ctx, project_to_camera(*ctx, player.pos), 32);
		render_scene(*ctx);
		render_fan(*ctx);
		SDL_RenderPresent(renderer);
	}
}

#import "Basic";
#import,file "sdl3.jai";