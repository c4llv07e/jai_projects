#import "Basic";
#import "String";
#import,file "sdl3.jai";
#import,file "theme.jai";

cool :: true;

Acme_Indent :: struct {
        rows: [..]struct {
                width: float;
                columns: [..]struct {
                        using buffer: Text_Buffer;
                        height: float;
                };
        };
        selected_row: s32;
        selected_col: s32;
};

Text_Buffer :: struct {
        text: string;
        cursor: s64;
};

Ctx :: struct {
        window: *void;
        renderer: *void;
        font: *TTF_Font;
        using win_size : struct {
                width : u32;
                height : u32;
        };
        is_running: bool;
        acme: Acme_Indent;
};

font_path :: "/usr/share/fonts/TTF/liberation/LiberationMono-Regular.ttf";

render_text :: (using ctx: *Ctx, x: float, y: float, color: SDL_Color, text: string) -> bool {
        surface: *SDL_Surface = TTF_RenderText_Blended(font, text.data, xx text.count, color);
        if surface == null {
                print("Can't render text on surface: %\n", sdl_get_error());
                return false;
        }
        defer SDL_DestroySurface(surface);
        texture: *SDL_Texture = SDL_CreateTextureFromSurface(renderer, surface);
        if texture == null {
                print("Can't convert surface to texture: %\n", sdl_get_error());
                return false;
        }
        defer SDL_DestroyTexture(texture);
        text_bounds := SDL_FRect.{
                x = SDL_floorf(x),
                y = SDL_floorf(y),
                w = xx texture.w,
                h = xx texture.h,
        };
        if !SDL_RenderTexture(renderer, texture, null, *text_bounds) {
                print("Can't blit texture: %\n", sdl_get_error());
                return false;
        }
        return true;
}

rect_line :: (using ctx: *Ctx, rect: SDL_FRect, color: SDL_Color) {
        SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
        SDL_RenderRect(renderer, *rect);
}

fill_rect :: (using ctx: *Ctx, rect :SDL_FRect, color: SDL_Color) {
        SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
        SDL_RenderFillRect(renderer, *rect);
}

postprocessing :: (using ctx: *Ctx) {
        y : float = 0;
        panel_height :: 2.0;
        while xx y < height {
                fill_rect(ctx, .{0, y, xx width, panel_height}, .{0x10, 0x10, 0x10, 0x50});
                y += panel_height * 2;
        }
}

main :: () {
        using ctx := Ctx.{
                width = 800,
                height = 600,
        };
        if !SDL_Init(.INIT_VIDEO) {
                print("Can't init SDL: %\n", sdl_get_error());
        }
        if !SDL_CreateWindowAndRenderer("editor", ctx.width, ctx.height, .RESIZABLE, *ctx.window, *ctx.renderer) {
                print("Can't create SDL window: %\n", sdl_get_error());
        }
        if !SDL_SetRenderDrawBlendMode(renderer, .BLEND) { 
                print("Can't set blend mode to blending: %\n", sdl_get_error());
        }
        if !TTF_Init() {
                print("Can't init SDL_TTF: %\n", sdl_get_error());
        }
        font = TTF_OpenFont(font_path.data, 24);
        if font == null {
                print("Can't load font at %: %\n", font_path, sdl_get_error());
        }
        array_add(*acme.rows, .{
                          width = xx width,
                  });
        array_add(*acme.rows[0].columns, .{
                          text = "Hello world",
                          height = xx (height / 2),
                  });
        array_add(*acme.rows[0].columns, .{
                          text = "Second panel",
                          height = xx (height / 2),
                  });
        print("Entering main loop...\n");
        is_running = true;
        event: SDL_Event;
        while is_running {
                while event_handler := SDL_PollEvent(*event) {
                        if event.type == {
                                case .QUIT;
                                is_running = false;
                                break event_handler;
                                case .KEY_DOWN;
                                if event.key.scancode == .I {
                                        if event.key.mod & .CTRL {
                                                acme.selected_col = cast(s32)((acme.selected_col + 1) % acme.rows[acme.selected_row].columns.count);
                                        }
                                }
                                case .KEY_UP;
                        }
                }
                sdl_set_color(renderer, background_color);
                SDL_RenderClear(renderer);
                x: float = 0;
                y: float = 0;
                for row, row_index: acme.rows {
                        for col, col_index: row.columns {
                                border_color : SDL_Color = ifx row_index == acme.selected_row && col_index == acme.selected_col {
                                        SDL_Color.{0x00, 0xff, 0xff, 0xff};
                                } else {
                                        SDL_Color.{0xff, 0x00, 0x00, 0xff};
                                }
                                rect_line(*ctx, .{x, y, row.width, col.height}, border_color);
                                render_text(*ctx, x, y, .{0x00, 0xff, 0x00, 0xff}, col.text);
                                y += col.height;
                        }
                        x += row.width;
                        y = 0;
                }
#if cool {
                        postprocessing(*ctx);
                }
                SDL_RenderPresent(renderer);
        }
}
