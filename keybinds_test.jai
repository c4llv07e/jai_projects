#import,file "keybinds.jai" (SDL_Scancode, sdl_scancode_from_string);

root_keybind: Keybind;

KeyMod :: struct {
	key: SDL_Scancode;
	mod: Modifier;
}

main :: () {
	context.print_style.default_format_struct.draw_type_name = true;
	context.print_style.default_format_struct.use_long_form_if_more_than_this_many_members = 1;
	context.print_style.default_format_struct.use_newlines_if_long_form = true;
	root_keybind = generate_keybinds("keybinds.conf");
	// print("keybinds = %\n", root_keybind);
	current_keybind := *root_keybind;
	keymods := KeyMod.[.{.X, .CTRL}, .{.F, .CTRL}];
	for keymod: keymods {
		next_keybind := walk_key(current_keybind, keymod.key, keymod.mod);
		if next_keybind == null {
			log("unknown key combo");
			current_keybind = *root_keybind;
			break;
		}
		log("step % %", keymod.mod, keymod.key);
		current_keybind = next_keybind;
		if current_keybind.command.count > 0 {
			log("executing command %", current_keybind.command);
			break;
		}
	}
}

#import,file "sdl3.jai";
#import "Basic";