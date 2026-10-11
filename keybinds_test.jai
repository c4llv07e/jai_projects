#import,file "keybinds.jai" (SDL_Scancode, sdl_scancode_from_string);

root: Keybind_Root;

KeyMod :: struct {
	key: SDL_Scancode;
	mod: Modifier;
}

main :: () {
	context.print_style.default_format_struct.draw_type_name = true;
	context.print_style.default_format_struct.use_long_form_if_more_than_this_many_members = 1;
	context.print_style.default_format_struct.use_newlines_if_long_form = true;
	root = generate_keybinds("test_keybinds.conf");
	current_mode_index := 0;
	print("keybinds = %\n", root);
	current_keybind := *root.root;
	keymods := KeyMod.[.{.X, .CTRL}, .{.F, .CTRL}];
	// Lowest to highest priority, so it would be easier to add and remove temporary modes.
	// In most cases should start with the default mode ("-").
	modes := string.["-", "file_dialog"];
	mode_indexes := calculate_modes_indexes(root, modes);
	log("mode_indexes: %", mode_indexes);
	for keymod: keymods {
		next_keybind := walk_key(current_keybind, keymod.key, keymod.mod, mode_indexes);
		if next_keybind == null {
			log("unknown key combo");
			current_keybind = *root.root;
			break;
		}
		log("step % %", keymod.mod, keymod.key);
		current_keybind = next_keybind;
		command, exists := check_keybind_leaf(current_keybind, mode_indexes);
		if exists {
			log("executing command %", command);
			break;
		}
	}
}

#import,file "sdl3.jai";
#import "Basic";