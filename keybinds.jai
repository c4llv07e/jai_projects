Keybind_Callback :: #type ();

Modifier :: enum_flags u16 {
	NONE :: 0;
        SHIFT :: 1;
        CTRL :: 2;
        ALT :: 4;
        GUI :: 8;
}

Keybind :: struct {
	key: u32;
	mod: Modifier;
	next: [..]Keybind;
	command: string;
}

string_to_u32 :: (s: string) -> u32 {
	if s.count == {
		case 0;
		return 0;
		case 1;
		return s.data[0];
		case 2;
		return (cast(*u16)s.data).*;
		case 3;
		return (cast(*u16)s.data).* | (s.data[2] << (8*2));
		case 4;
		return (cast(*u32)s.data).*;
		case;
		log_error("String '%' is too big for u32", s);
		return 0;
	}
	log_error("unreachable");
	return 0;
}

char_to_mod :: (char: u8) -> Modifier {
	char = to_lower(char);
#insert -> string {
		sb: String_Builder;
		ti :: type_info(Modifier);
		for mod, iter: ti.names {
			if ti.values[iter] == 0 continue;
			print(*sb, "if char == % then return .%;\n", to_lower(mod[0]), mod);
		}
		return builder_to_string(*sb);
	}
	log_error("Keymod % not found", char);
	return .NONE;
}

// Case sensitve because shift considered a layer key (so S-8 wouldn't
// mean the same as numpad's * on qwerty keyboard) -- humble dvorak user.
parse_combo :: (combo: string) -> key: u32, mod: Modifier {
	mod: Modifier = 0;
	remaing := combo;
	for 0..100 {
		remaing = trim(remaing);
		key_str: string;
		found: bool;
		found, key_str, remaing = split_from_left(remaing, #char "-");
		if !found {
			// it's key
			if key_str.count > 1 {
				log_error("key '%' is too big, don't know how to parse it", key_str);
			}
			return string_to_u32(key_str), mod;
		}
		if key_str.count > 1 {
			log_error("mod '%' is not single byte, something is wrong with config", key_str);
		}
		mod |= char_to_mod(key_str.data[0]);
	}
	return 0, 0;
}

generate_keybinds :: (filepath: string) -> Keybind {
	content, ok := read_entire_file(filepath);
	if !ok {
		print("Can't read keybinds file %!\n", filepath);
		return .{};
	}
	root := Keybind.{};
	while true {
		line, found_line := consume_next_line(*content);
		if !found_line break;
		trimmed_line := trim(line);
		if trimmed_line.count <= 0 continue;
		if begins_with(trimmed_line, "#") continue;
		found, keys, command := split_from_right(line, #char " ");
		if !found {
			log_error("Can't split commands and keys on line '%'", line);
		}
		if command.count == 0 || keys.count == 0 {
			log_error("Found only one word on line '%'", line);
		}
		parent := *root;
		remaing := keys;
		for 0..100 {
			remaing = trim(remaing);
			if remaing.count <= 0 break;
			found: bool;
			combo: string;
			found, combo, remaing = split_from_right(remaing, #char " ");
			if !found {
				combo = remaing;
				remaing.count = 0;
			}
			combo = trim(combo);
			key, mod := parse_combo(combo);
			found_index: s64 = -1;
			for child, child_index: parent.next {
				if child.key == key && child.mod == mod {
					found_index = child_index;
				}
			}
			if found_index == -1 {
				found_index = parent.next.count;
				array_add(*parent.next, New(Keybind));
				parent.next[found_index].key = key;
				parent.next[found_index].mod = mod;
			}
			parent = *parent.next[found_index];
			if parent.command {
				// Good luck finding this keybind, because we have no trace back from this!
				log_error("Keybind % already have a command, but was tried to rebind by line '%'", line);
				return root;
			}
		}
		parent.command = command;
	}
	return root;
}

#import "Text_File_Handler";
#import "String";
#import "Basic";
#import "File";