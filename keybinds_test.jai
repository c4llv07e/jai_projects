#load "keybinds.jai";

main :: () {
	context.print_style.default_format_struct.draw_type_name = true;
	context.print_style.default_format_struct.use_long_form_if_more_than_this_many_members = 1;
	context.print_style.default_format_struct.use_newlines_if_long_form = true;
	keybinds := generate_keybinds("keybinds.conf");
	print("keybinds = %\n", keybinds);
}

#import "Basic";