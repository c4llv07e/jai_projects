#module_parameters(ENABLE_JAI_FEATURES := true) (ENABLE_TTF := true);

sdl3 :: #system_library "libSDL3.so";

SDL_EventType :: enum u32 {
        QUIT :: 0x100;
	
	WINDOW_SHOWN :: 0x202;
	WINDOW_HIDDEN;
	WINDOW_EXPOSED;
	WINDOW_MOVED;
	WINDOW_RESIZED;
	WINDOW_PIXEL_SIZE_CHANGED;
	WINDOW_METAL_VIEW_RESIZED,
	WINDOW_MINIMIZED,
	WINDOW_MAXIMIZED,
	WINDOW_RESTORED,
	
	KEY_DOWN :: 0x300;
        KEY_UP;
	TEXT_EDITING;
	TEXT_INPUT;
	
	MOUSE_MOTION :: 0x400;
	MOUSE_BUTTON_DOWN;
	MOUSE_BUTTON_UP;
	MOUSE_WHEEL;
};

SDL_KeyboardID :: u32;
SDL_WindowID :: u32;

SDL_Scancode :: enum u32 {
        I :: 12;
	BACKSPACE :: 42;
	RIGHT :: 79;
	LEFT :: 80;
	LCTRL :: 224;
	LSHIFT :: 225;
	LALT :: 226;
	LGUI :: 227;
	RCTRL :: 228;
	RSHIFT :: 229;
	RALT :: 230;
	RGUI :: 231;
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

SDL_MouseButtonCode :: enum u8 {
	LEFT :: 1;
	MIDDLE :: 2;
	RIGHT :: 3;
	X1 :: 4;
	X2 :: 5;
}


SDL_MouseButtonEvent :: struct {
	type: SDL_EventType;
	reserved: u32;
	timestamp: u64;
	windowID: SDL_WindowID;
	which: SDL_MouseID;
	button: SDL_MouseButtonCode;
	down: bool;
	clicks: u8;
	padding: u8;
	x: float32;
	y: float32;
};

SDL_MouseID :: u32;
SDL_MouseWheelDirection :: enum u32 {
	SDL_MOUSEWHEEL_NORMAL;
	SDL_MOUSEWHEEL_FLIPPED;
};

SDL_MouseWheelEvent :: struct {
	type: SDL_EventType;
	reserved: u32;
	timestamp: u64;
	windowID: SDL_WindowID;
	which: SDL_MouseID;
	x: float32;
	y: float32;
	direction: SDL_MouseWheelDirection;
	mouse_x: float32;
	mouse_y: float32;
	integer_x: s32;
	integer_y: s32;
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
	mouse: SDL_MouseButtonEvent;
	wheel: SDL_MouseWheelEvent;
};

SDL_Color :: struct {
        r, g, b, a: u8;
};

SDL_Point :: struct {
	x, y: s32;
};

SDL_FPoint :: struct {
	x, y: float32;
};

SDL_Rect :: struct {
	x, y, w, h: s32;
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
        VIDEO :: 0x00000020;
};

SDL_MAJOR_VERSION :: 3;
SDL_MINOR_VERSION :: 5;
SDL_MICRO_VERSION :: 0;

SDL_Init :: (subsystems: SDL_INIT_FLAGS) -> bool #foreign sdl3;
SDL_CreateWindow :: (title: *u8, w: int, h: int, flags: SDL_WindowFlags) -> *SDL_Window #foreign sdl3;
SDL_CreateWindowAndRenderer :: (title: *u8, width: int, height: int, window_flags: SDL_WindowFlags, window: **void, renderer: **void) -> bool #foreign sdl3;
SDL_GetWindowSize :: (window: *SDL_Window, w: *s32, h: *s32) -> bool #foreign sdl3;
SDL_GetWindowSizeInPixels :: (window: *SDL_Window, w: *s32, h: *s32) -> bool #foreign sdl3;
SDL_PollEvent :: (event: *SDL_Event) -> bool #foreign sdl3;
SDL_WaitEvent :: (event: *SDL_Event) -> bool #foreign sdl3;
SDL_WaitEventTimeout :: (event: *SDL_Event, timeoutMS: s32) -> bool #foreign sdl3;
SDL_StartTextInput :: (window: *SDL_Window) -> bool #foreign sdl3;
SDL_SetRenderClipRect :: (renderer: *void, rect: *SDL_Rect) -> bool #foreign sdl3;
#if OS != .WINDOWS {
	SDL_SetRenderClipRectFloat :: (renderer: *void, rect: *SDL_FRect) -> bool #foreign sdl3;
} else {
	SDL_SetRenderClipRectFloat :: (renderer: *void, rect: *SDL_FRect) -> bool {
		nrect := SDL_Rect.{
			xx rect.x, xx rect.y, xx rect.w, xx rect.h,
		};
		return SDL_SetRenderClipRect(renderer, *nrect);
	}
}
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
SDL_Delay :: (ms: u32) #foreign sdl3;
SDL_GetVersion :: () -> s32 #foreign sdl3;
SDL_GetRevision :: () -> *u8 #foreign sdl3;
SDL_GetRectIntersectionFloat :: (A: *SDL_FRect, B: *SDL_FRect, result: *SDL_FRect) -> bool #foreign sdl3;
SDL_Log :: (fmt: *u8, args: ..Any) #foreign sdl3;
SDL_LogCritical :: (category: s32, fmt: *u8, args: ..Any) #foreign sdl3;
SDL_LogDebug :: (category: s32, fmt: *u8, args: ..Any) #foreign sdl3;
SDL_LogError :: (category: s32, fmt: *u8, args: ..Any) #foreign sdl3;
SDL_LogInfo :: (category: s32, fmt: *u8, args: ..Any) #foreign sdl3;
SDL_LogTrace :: (category: s32, fmt: *u8, args: ..Any) #foreign sdl3;
SDL_LogVerbose :: (category: s32, fmt: *u8, args: ..Any) #foreign sdl3;
SDL_LogWarn :: (category: s32, fmt: *u8, args: ..Any) #foreign sdl3;


SDL_floorf :: (x: float32) -> float32 #foreign sdl3;
SDL_floor :: (x: float64) -> float64 #foreign sdl3;
SDL_ceilf :: (x: float32) -> float32 #foreign sdl3;
SDL_ceil :: (x: float64) -> float64 #foreign sdl3;

#if ENABLE_TTF {
	sdl3_ttf :: #system_library "libSDL3_ttf.so";
	
	TTF_Font :: void;
	
	TTF_Init :: () -> bool #foreign sdl3_ttf;
	TTF_OpenFont :: (file: *u8, ptsize: float32) -> *TTF_Font #foreign sdl3_ttf;
	TTF_RenderText_Blended :: (font: *TTF_Font, text: *u8, length: u64, fg: SDL_Color) -> *SDL_Surface #foreign sdl3_ttf;
	TTF_RenderText_Blended_Wrapped :: (font: *TTF_Font, text: *u8, length: u64, fg: SDL_Color, wrap_width: s32) -> *SDL_Surface #foreign sdl3_ttf;
	TTF_MeasureString :: (font: *TTF_Font, text: *u8, length: u64, max_width: s32, measured_width: *s32, measured_length: *u64) -> bool #foreign sdl3_ttf;
	TTF_SetFontSize :: (font: *TTF_Font, ptsize: float32) -> bool #foreign sdl3_ttf;
	TTF_GetFontSize :: (font: *TTF_Font) -> float32 #foreign sdl3_ttf;
}

#if ENABLE_JAI_FEATURES {
	sdl_get_error :: () -> string {
		return to_string(SDL_GetError());
	}
	
	sdl_set_color :: (renderer: *SDL_Renderer, color: SDL_Color) {
		SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
	}
	
	fill_rect :: (renderer: *SDL_Renderer, rect: SDL_FRect, color: SDL_Color) {
		SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
		SDL_RenderFillRect(renderer, *rect);
	}
	
	draw_rect_lines :: (renderer: *SDL_Renderer, rect: SDL_FRect, color: SDL_Color) {
		SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
		SDL_RenderRect(renderer, *rect);
	}
	
	is_intersecting :: (rect: SDL_FRect, point: SDL_FPoint) -> bool {
		return point.x >= rect.x && point.x <= rect.x + rect.w && point.y >= rect.y && point.y <= rect.y + rect.h;
	}
	
	sdl_debug_version_info :: () {
		ver_int := SDL_GetVersion();
		revision := SDL_GetRevision();
		SDL_Log("Compiled with SDL version %d.%d.%d\nLinked with SDL version %d.%d.%d-%s\n",
			SDL_MAJOR_VERSION, SDL_MINOR_VERSION, SDL_MICRO_VERSION,
			ver_int / 1000000, (ver_int / 1000) % 1000, ver_int % 1000, revision);
	}
	
	operator + :: (a: SDL_FRect, b: SDL_FRect) -> SDL_FRect {
		return .{a.x + b.x, a.y + b.y, a.w + b.w, a.h + b.h};
	}
	
#if ENABLE_TTF {
		sdl_measure_string :: (font: *TTF_Font, text: string, max_width: s32) -> (bool, s32, u64) {
			measured_width: s32;
			measured_length: u64;
			res := TTF_MeasureString(font, text.data, cast(u64)text.count, max_width, *measured_width, *measured_length);
			return res, measured_width, measured_length;
		}
	}
}