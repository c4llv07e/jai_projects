on_demand_renderer :: true;

Elf64 :: struct {
	header: struct {
		magic: u32;
		bitformat: u8;
		endianness: u8;
		version: u8;
		abi: u8;
		abiver: u8;
		pad: [7]u8;
		type: u16;
		machine: u16;
		elfver: u32;
		entry: u64;
		prog_header: u64;
		section_header: u64;
		flags: u32;
		header_size: u16;
		program_header_size: u16;
		program_header_length: u16;
		section_header_size: u16;
		section_header_length: u16;
		section_header_names_entry: u16;
	};
	section_header: struct {
		name: u32;
		type: u32;
		flags: u64;
		addr: u64;
		offset: u64;
		size: u64;
		info: u32;
		addralign: u64;
		entsize: u64;
	};
}
elf64_ti :: type_info(Elf64);

Linking_Uint :: struct {
	name: string;
	elf: Elf64;
}

Ctx :: struct {
	unit: Linking_Uint;
}

using ctx: Ctx;

type_to_u64 :: (addr: *u8, ti: *Type_Info) -> u64 {
	if ti.type == {
		case .INTEGER;
		tii := (cast(*Type_Info_Integer)ti).*;
		if tii.signed {
			if ti.runtime_size == {
				case 1;
				return cast,no_check(u64)((cast(*s8)addr).*);
				case 2;
				return cast,no_check(u64)((cast(*s16)addr).*);
				case 4;
				return cast,no_check(u64)((cast(*s32)addr).*);
				case 8;
				return cast,no_check(u64)((cast(*s64)addr).*);
			}
			log("signed integer have weird runtime_size %", ti.runtime_size);
		} else {
			if ti.runtime_size == {
				case 1;
				return (cast(*u8)addr).*;
				case 2;
				return (cast(*u16)addr).*;
				case 4;
				return (cast(*u32)addr).*;
				case 8;
				return (cast(*u64)addr).*;
			}
			log("unsigned integer have weird runtime_size %", ti.runtime_size);
		}
	}
	return cast,no_check(u64)-1;
}

logic_render :: () {
	name_width := mesaure_text(unit.name);
	draw_text(0, 0, unit.name);
	draw_rect(0, 0, name_width, font_height, .{0xff, 0x00, 0x00, 0xff});
	y := cast(float32)font_height;
	x := 0.0;
	for elf64_ti.members {
		bytes := ((cast(*u8)*unit.elf) + it.offset_in_bytes);
		if it.type.type == .STRUCT {
			draw_text(x, y, it.name);
		} else {
			draw_text(x, y, tprint("% = %", it.name, (cast(*u64)bytes).*));
		}
		y += font_height;
		if it.type.type == .STRUCT {
			x += 24.0;
			member_addr := bytes;
			for (cast(*Type_Info_Struct)it.type).members {
				subbytes := member_addr + it.offset_in_bytes;
				draw_text(x, y, tprint("% = %", it.name, type_to_u64(subbytes, it.type)));
				y += font_height;
			}
			x -= 24.0;
		}
	}
}

check_elf_header :: (using header: type_of(Elf64.header)) -> bool {
	if magic != 1179403647 {
		log("wrong header magic");
		return false;
	}
	if bitformat != 2 {
		log("elf is not x64 bit");
		return false;
	}
	if endianness != 1 {
		log("Brick your computer, please");
		return false;
	}
	if version != 1 {
		log("We don't support future people");
		return false;
	}
#if false { // For some reason, it is ignored by compilers.
		if abi != 3 {
			log("Elf not for linux");
			return false;
		}
	}
	if machine != 0x3e {
		log("Elf is not AMD64");
		return false;
	}
	if elfver != 1 {
		log("elf ver is from the future");
		return false;
	}
	if header_size != 64 {
		log("header size is not default one");
		return false;
	}
	if section_header_size != size_of(type_of(Elf64.section_header)) {
		log("section header size is invalid");
		return false;
	}
	return true;
}

parse_elf :: (content: string) -> Elf64, bool {
	if size_of(type_of(Elf64.header)) > content.count return .{}, false;
	elf := Elf64.{};
	memcpy(*elf.header, content.data, size_of(type_of(Elf64.header)));
	if !check_elf_header(elf.header) return elf, false;
	return elf, true;
}

logic_init :: () {
	unit.name = "test.o";
	elf_content, ok := read_entire_file(unit.name);
	assert(ok, "Can't read elf file!");
	unit.elf = parse_elf(elf_content);
	print("%\n", unit.elf);
}

#import "File";
#load "system.jai";