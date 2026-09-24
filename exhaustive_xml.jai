Parse_Status :: enum u32 {
	OK;
	INCOMPLETE;
	ERROR;
}

Property :: struct {
	key: string;
	value: string;
}

Tag :: struct {
	name: string;
	properties: [..]Property;
	children: [..]#this;
	content: string;
}

expect :: (s: *string, char: u8) -> bool {
	if s.count <= 0 return false;
	if s.*[0] != char return false;
	advance(s);
	return true;
}

expect :: (s: *string, ss: string) -> bool {
	if s.count < ss.count return false;
	if s.* == ss return false;
	advance(s, ss.count);
	return true;
}

peek :: (s: string) -> u8 {
	if s.count <= 0 return 0;
	return s[0];
}

try_parse_tag_name :: (buffer: *string) -> Parse_Status, string {
	start := buffer.*;
	while buffer.count > 0 && is_alnum(buffer.*[0]) {
		advance(buffer);
	}
	if buffer.count == 0 return .INCOMPLETE, start;
	if start.data == buffer.data return .ERROR, "";
	start.count = buffer.data - start.data;
	return .OK, start;
}

consume_name :: (buffer: *string) -> Parse_Status, string {
	end := buffer.*;
	while end.count > 0 && is_alnum(end[0]) {
		advance(*end);
	}
	name := buffer.*;
	name.count = end.data - buffer.data;
	buffer.* = end;
	if end.count == 0 return .INCOMPLETE, name;
	return .OK, name;
}

consume_until :: (buffer: *string, c: u8) -> Parse_Status, string {
	begin := buffer.*;
	while buffer.count > 0 && buffer.*[0] != c {
		advance(buffer);
	}
	if buffer.count == 0 return .INCOMPLETE, begin;
	begin.count = buffer.data - begin.data;
	return .OK, begin;
}

try_parse_attribute :: (buffer: *string) -> Parse_Status, string, string {
	ok, key := consume_name(buffer);
	if ok != .OK {
		return ok, "", "";
	}
	buffer.* = eat_spaces(buffer.*);
	if !expect(buffer, #char "=") return .ERROR, key, "";
	buffer.* = eat_spaces(buffer.*);
	quotes := peek(buffer.*);
	if quotes != #char "'" && quotes != #char "\"" return .ERROR, key, "";
	advance(buffer);
	value: string;
	ok, value = consume_until(buffer, quotes);
	if ok != .OK {
		return ok, key, value;
	}
	if !expect(buffer, quotes) return .ERROR, key, value;
	return .OK, key, value;
}

try_parse_tag :: (buffer: *string) -> Parse_Status, Tag {
	tag: Tag;
	if buffer.count <= 0 return .INCOMPLETE, .{};
	assert(!is_space(buffer.*[0]), "Trying to parse tag with spaces before it. Fix whitespace problem before calling this function.");
	if !expect(buffer, cast(u8)#char "<") return .ERROR, .{};
	if peek(buffer.*) == #char "/" return .ERROR, .{};
	buffer.* = eat_spaces(buffer.*);
	name_res, name := try_parse_tag_name(buffer);
	tag.name = name;
	if name_res != .OK {
		return name_res, tag;
	}
	while true {
		buffer.* = eat_spaces(buffer.*);
		if peek(buffer.*) == #char ">" || peek(buffer.*) == #char "/" then break;
		ok, attr_key, attr_value := try_parse_attribute(buffer);
		if ok != .OK {
			return ok, tag;
		}
		array_add(*tag.properties, .{key = attr_key, value = attr_value});
	}
	buffer.* = eat_spaces(buffer.*);
	if expect(buffer, cast(u8)#char "/") {
		if !expect(buffer, cast(u8)#char ">") return .ERROR, tag;
		return .OK, tag;
	}
	if !expect(buffer, cast(u8)#char ">") return .ERROR, tag;
	while true {
		saved := buffer.*;
		ok, child := try_parse_tag(buffer);
		if ok == .OK {
			array_add(*tag.children, child);
			continue;
		}
		if ok != .OK {
			buffer.* = saved;
		}
		text: string;
		ok, text = consume_until(buffer, #char "<");
		tag.content = text;
		if ok != .OK {
			return ok, tag;
		}
		break;
	}
	if buffer.count <= 0 return .INCOMPLETE, tag;
	if !expect(buffer, #char "<") return .ERROR, tag;
	if !expect(buffer, #char "/") return .ERROR, tag;
	buffer.* = eat_spaces(buffer.*);
	if !expect(buffer, tag.name) return .ERROR, tag;
	buffer.* = eat_spaces(buffer.*);
	if !expect(buffer, #char ">") return .ERROR, tag;
	return .OK, tag;
}

main :: () {
	content := "<tag prop=\"value\"><elem/><field>Some text</field></tag>";
	ok, tag := try_parse_tag(*content);
	print("status(%): %\n", ok, tag);
	log("content = %\n", content);
}

#import "Basic";