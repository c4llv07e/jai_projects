keybinds_filepath :: "./keybinds.conf";

Keybind_Callback :: #type ();

Keybind :: struct {
	key: u32;
	mod: u16;
	next: []*#this;
	command: Keybind_Callback;
};

generate_keybinds :: () -> *Keybind {
	content, ok := read_entire_file(keybinds_filepath);
	if !ok {
		print("Can't read keybinds file %!\n", keybinds_filepath);
		return null;
	}
	line_start := 0;
	line_end := 0;
	byte := 1;
	print("%\n", content);
	while byte <= content.count {
		if byte == content.count || content[byte] == #char "\n" {
			line_end = byte;
			byte -= 1;
			while byte > 0 && content[byte] != #char " " && content[byte] != #char "\n" {
				byte -= 1;
			}
			if byte == line_end {
				byte += 1;
				line_start = byte;
				continue;
			}
			command := slice(content, byte + 1, line_end - byte - 1);
			// TODO(c4llv07e): Parse key combos here.
			keys: [..]string;
			print("found command '%'!\n", command);
			byte = line_end + 1;
			line_start = byte;
		} else {
			byte += 1;
		}
	}
	return null;
}

#if false {
	keybinds :: #run generate_keybinds();
} else {
	main :: () {
		keybinds := generate_keybinds();
		print("%\n", keybinds);
	}
}

#import "String";
#import "Basic";
#import "File";