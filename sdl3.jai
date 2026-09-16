
sdl3 :: #system_library "libSDL3.so";
sdl3_ttf :: #system_library "libSDL3_ttf.so";

SDL_EventType :: enum u32 {
        QUIT :: 0x100;
	
	WINDOW_SHOWN :: 0x202;
	WINDOW_HIDDEN;
	WINDOW_EXPOSED;
	WINDOW_MOVED;
	WINDOW_RESIZED;
	WINDOW_PIXEL_SIZE_CHANGED;
	
	KEY_DOWN :: 0x300;
        KEY_UP;
	TEXT_EDITING;
	TEXT_INPUT;
};

SDL_KeyboardID :: u32;
SDL_WindowID :: u32;

SDL_Scancode :: enum u32 {
        I :: 12;
};
SDL_Keycode :: u32;
SDL_Keymod :: enum u16 {
        NONE :: 0x0000;
        LSHIFT :: 0x0001;
        RSHIFT :: 0x0002;
        LEVEL5 :: 0x0004;
        LCTRL :: 0x0040;
        RCTRL :: 0x0080;
        LALT :: 0x0100;
        RALT :: 0x0200;
        LGUI :: 0x0400;
        RGUI :: 0x0800;
        NUM :: 0x1000;
        CAPS :: 0x2000;
        MODE :: 0x4000;
        SCROLL :: 0x8000;
        CTRL :: (SDL_Keymod.LCTRL | SDL_Keymod.RCTRL);
        SHIFT :: (SDL_Keymod.LSHIFT | SDL_Keymod.RSHIFT);
        ALT :: (SDL_Keymod.LALT | SDL_Keymod.RALT);
        GUI :: (SDL_Keymod.LGUI | SDL_Keymod.RGUI);
};

SDL_WindowEvent :: struct {
	type: SDL_EventType;
	reserved: u32;
	timestamp: u64;
	windowID: SDL_WindowID;
	data1: s32;
	data2: s32;
};

SDL_KeyboardEvent :: struct {
        type: SDL_EventType;
        reserved: u32;
        timestamp: u64;
        windowID: SDL_WindowID;
        which: SDL_KeyboardID;
        scancode: SDL_Scancode;
        key: SDL_Keycode;
        mod: SDL_Keymod;
        raw: u16;
        down: bool;
        repeat: bool;
};

SDL_TextInputEvent :: struct {
	type: SDL_EventType;
	reserved: u32;
	timestamp: u64;
	windowID: SDL_WindowID;
	text: *u8;
};

SDL_Event :: union { 
        type: SDL_EventType;
        padding: [128]u8;
	window: SDL_WindowEvent;
        key: SDL_KeyboardEvent;
	text: SDL_TextInputEvent;
};

SDL_Color :: struct {
        r, g, b, a: u8;
};

SDL_FRect :: struct {
        x, y, w, h: float32;
};

SDL_PixelFormat :: enum u32 {
};

SDL_SurfaceFlags :: u32;

SDL_Texture :: struct {
        format: SDL_PixelFormat;
        w: s32;
        h: s32;
        refcount: s32;
};

SDL_Surface :: struct {
        flags: SDL_SurfaceFlags;
        format: SDL_PixelFormat;
        w: s32;
        h: s32;
        pitch: s32;
        pixels: *void;
        refcount: s32;
        reserved: *void;
};

SDL_WindowFlags :: enum u64 {
        VULKAN :: 0x0000000010000000;
        RESIZABLE :: 0x0000000000000020;
};

SDL_BlendMode :: enum u32 {
        NONE :: 0;
        BLEND :: 1;
        ADD :: 2;
        MOD :: 4;
        MUL :: 8;
        INVALID :: 0x7fffffff;
};

SDL_Renderer :: void;
SDL_Window :: void;

SDL_INIT_FLAGS :: enum u32 {
        INIT_VIDEO :: 0x00000020;
};

SDL_Init :: (subsystems: SDL_INIT_FLAGS) -> bool #foreign sdl3;
SDL_CreateWindow :: (title: *u8, w: int, h: int, flags: SDL_WindowFlags) -> *SDL_Window #foreign sdl3;
SDL_CreateWindowAndRenderer :: (title: *u8, width: int, height: int, window_flags: SDL_WindowFlags, window: **void, renderer: **void) -> bool #foreign sdl3;
SDL_PollEvent :: (event: *SDL_Event) -> bool #foreign sdl3;
SDL_StartTextInput :: (window: *SDL_Window) -> bool #foreign sdl3;
SDL_SetRenderDrawColor :: (renderer: *void, r: u8, g: u8, b: u8, a: u8) -> bool #foreign sdl3;
SDL_RenderClear :: (renderer: *void) -> bool #foreign sdl3;
SDL_RenderPresent :: (renderer: *void) -> bool #foreign sdl3;
SDL_RenderRect :: (renderer: *SDL_Renderer, rect: *SDL_FRect) -> bool #foreign sdl3;
SDL_RenderFillRect :: (renderer: *SDL_Renderer, rect: *SDL_FRect) -> bool #foreign sdl3;
SDL_CreateTextureFromSurface :: (renderer: *SDL_Renderer, surface: *SDL_Surface) -> *SDL_Texture #foreign sdl3;
SDL_SetRenderDrawBlendMode :: (renderer: *SDL_Renderer, blendMode: SDL_BlendMode) -> int #foreign sdl3;
SDL_DestroySurface :: (surface: *SDL_Surface) #foreign sdl3;
SDL_RenderTexture :: (renderer: *SDL_Renderer, texture: *SDL_Texture, srcrect: *SDL_FRect, dstrect: *SDL_FRect) -> bool #foreign sdl3;
SDL_DestroyTexture :: (texture: *SDL_Texture) #foreign sdl3;
SDL_GetError :: () -> *u8 #foreign sdl3;

SDL_floorf :: (x: float32) -> float32 #foreign sdl3;
SDL_floor :: (x: float64) -> float64 #foreign sdl3;

TTF_Font :: void;

TTF_Init :: () -> bool #foreign sdl3_ttf;
TTF_OpenFont :: (file: *u8, ptsize: float32) -> *TTF_Font #foreign sdl3_ttf;
TTF_RenderText_Blended :: (font: *TTF_Font, text: *u8, length: u64, fg: SDL_Color) -> *SDL_Surface #foreign sdl3_ttf;

sdl_get_error :: () -> string {
        return to_string(SDL_GetError());
}

sdl_set_color :: (renderer: *SDL_Renderer, color: SDL_Color) {
        SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
}