// This is by far the most complicated thing in the project. I wanted to replicate
// emacs' key sequences system with intention of using with modes by default.
// The result is a very cursed and poorly documented tree generator and traversal
// with semi-bitmasks[1] layering. Please, check keybinds_test.jai if it exists
// to understand how it works.

// [1] - Modes were just a bitmask, but it made "shadowing" not possible so I gave
// up and made it a dynamic array of indexes. Probably not a very smart idea, but
// it is what it is.

// TODO(c4llv07e): Add a global leaf for C-g keybind.

#module_parameters ($key_type: Type = u32, $string_to_key: (string) -> $key_type = string_to_u32) () {}

Keybind_Callback :: #type ();

Modifier :: enum_flags u16 {
	NONE :: 0;
        SHIFT :: 1;
        CTRL :: 2;
        ALT :: 4;
        GUI :: 8;
}

Keybind :: struct {
	key: key_type;
	mod: Modifier;
	next: [..]Keybind;
	commands: [..]string;
	mask: s64; // Mask of modes indexes. Puts hard restrain on modes count.
}

Keybind_Root :: struct {
	root: Keybind;
	modes: [..]string;
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
parse_combo :: (combo: string) -> key: key_type, mod: Modifier {
	mod: Modifier = 0;
	remaing := combo;
	for 0..100 {
		remaing = trim(remaing);
		key_str: string;
		found: bool;
		found, key_str, remaing = split_from_left(remaing, #char "-");
		if !found {
			// it's key
			return string_to_key(key_str), mod;
		}
		if key_str.count > 1 {
			log_error("mod '%' is not single byte, something is wrong with config", key_str);
		}
		mod |= char_to_mod(key_str.data[0]);
	}
	return 0, 0;
}

calculate_modes_indexes :: (root: Keybind_Root, mode_names: []string) -> [..]s64 {
	res: [..]s64;
	for name, name_index: mode_names {
		name_index := find_mode_index(root, name);
		assert(name_index != -1);
		array_add(*res, cast(s64)name_index);
	}
	return res;
}

walk_key :: (keybind: *Keybind, key: key_type, mod: Modifier, mode_indexes: []s64) -> *Keybind {
	for mode: mode_indexes {
		for * next: keybind.next {
			if (next.mask & (1 << mode)) == 0 continue;
			if next.mod == mod && next.key == key {
				return next;
			}
		}
	}
	return null;
}

check_keybind_leaf :: (keybind: *Keybind, mode_indexes: []s64) -> command: string, ok: bool {
	for mode_index: mode_indexes {
		if keybind.commands.count <= mode_index continue;
		if keybind.commands[mode_index].count > 0 return keybind.commands[mode_index], true;
	}
	return "", false;
}

find_mode_index :: (root: Keybind_Root, name: string) -> s64 {
	for root.modes {
		if it == name {
			return it_index;
		}
	}
	return -1;
}

// Taken from Basic/string_to_float.jai
clz64 :: (x: u64) -> n: s32 {
	if !x return 64;
	n: s32;
	mask: u64 = 0x8000_0000_0000_0000;
	while !(x & mask) {
		n += 1;
		mask = mask >> 1;
	}
	return n;
}

count_power_base :: (v: s64) -> s64 {
	return (size_of(type_of(v)) * 8) - clz64(cast(u64)v);
}

// Uses default allocator, doesn't change it any way, feel free to use (,, temp) if you wish.
generate_keybinds :: (filepath: string) -> Keybind_Root {
	content, ok := read_entire_file(filepath);
	if !ok {
		print("Can't read keybinds file %!\n", filepath);
		return .{};
	}
	current_mode_index := 0;
	root := Keybind_Root.{};
	array_add(*root.modes, copy_string("-"));
	while true {
		line, found_line := consume_next_line(*content);
		if !found_line break;
		line_without_comments := stop_at_any(line, "#");
		trimmed_line := trim(line_without_comments);
		if trimmed_line.count <= 0 continue;
		if trimmed_line[0] == #char "[" {
			if trimmed_line[trimmed_line.count - 1] != #char "]" {
				log_error("Line '%' must end with ]", line);
				continue;
			}
			untrimmed_mode_name := advance(trimmed_line);
			untrimmed_mode_name.count -= 1;
			mode_name := trim(untrimmed_mode_name);
			if mode_name.count <= 0 {
				log_error("Empty mode name is not supported, line '%'", line);
				continue;
			}
			mode_index := find_mode_index(root, mode_name);
			if mode_index == -1 {
				array_add(*root.modes, copy_string(mode_name));
				mode_index = root.modes.count - 1;
			}
			current_mode_index = mode_index;
			continue;
		} else {
			found, keys, command := split_from_right(trimmed_line, #char " ");
			if !found {
				log_error("Can't split commands and keys on line '%'", line);
				continue;
			}
			if command.count == 0 || keys.count == 0 {
				log_error("Found only one word on line '%'", line);
				continue;
			}
			parent := *root.root;
			parent.mask |= (1 << current_mode_index);
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
				if !key {
					log_error("probably error on parsing combo '%', value wasn't initialized", combo);
				}
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
					parent.next[found_index].mask = (1 << current_mode_index);
				}
				parent = *parent.next[found_index];
				if parent.commands.count > current_mode_index && parent.commands[current_mode_index].count > 0 {
					// Good luck finding this keybind, because we have no trace back from this!
					// TODO(c4llv07e): Make somehow traverse keybinds back to generate usefull message about duplicates.
					log_error("Keybind % already have a command, but was tried to rebind by line '%'", parent.*, line);
					return root;
				}
				parent.mask |= (1 << current_mode_index);
			}
			modes_count := count_power_base(parent.mask);
			array_resize(*parent.commands, modes_count);
			parent.commands[current_mode_index] = command;
		}
	}
	return root;
}

Math :: #import "Math";
#import "Text_File_Handler";
#import "String";
#import "Basic";
#import "File";