Xml_Parser :: struct {
	state: enum u32 {
		INITIAL :: 0;
		ERROR;
		TAG_START;
		PROPERTIES;
		TAG_END;
		TAG_INNER;
		TEXT;
	}
	buffer: [..]u8;
	names_stack: [..]string;
	last_token_name: string;
	last_text: string;
}

Xml_Message :: enum u32 {
	PARSED:: 0;
	ERROR;
	TAG_BEGIN;
	TAG_NAME;
	TAG_PROPERTY;
	TAG_END;
	TAG_BODY;
}

append :: (using parser: *Xml_Parser, text: string) -> (added: s64) {
	array_add(*buffer, ..cast([]u8)text);
	return text.count;
}

get_unparsed :: (using parser: Xml_Parser) -> string {
	result: string = ---;
	result.data = buffer.data;
	result.count = buffer.count;
	return result;
}

peek_first :: (data: []u8, offset: s64 = 0) -> u8 {
	if data.count <= offset return 0;
	return data[offset];
}

advance_move :: inline (array: *[..]u8, amount: s64 = 1) {
	assert(amount >= 0);
	assert(array.count >= amount);
	memcpy(array.data, array.data + amount, array.count - amount);
	array.count -= amount;
}

advance_view :: inline (array: *[]u8, amount: s64 = 1) {
	assert(amount >= 0);
	assert(array.count >= amount);
	array.data += amount;
	array.count -= amount;
}

find_whitespace_end :: (buffer: []u8) -> s64 {
	iter := 0;
	while buffer.count > iter && is_space(buffer[iter]) {
		iter += 1;
	}
	if is_space(buffer[iter]) return -1;
	return iter;
}

skip_spaces :: (buffer: *[..]u8) {
	end := find_whitespace_end(buffer.*);
	if end == -1 return;
	advance_move(buffer, end);
}

try_consume_name :: (buffer: *[..]u8) -> bool, string { // Allocates name with default allocator or returns *sttaic* "" on error.
	cursor: []u8 = buffer.*;
	while is_alnum(peek_first(cursor)) {
		advance_view(*cursor);
	}
	if cursor.count <= 0 return false, "";
	name: string = ---;
	name.data = buffer.data;
	name.count = cursor.data - buffer.data;
	name = copy_string(name);
	advance_move(buffer, name.count);
	return true, name;
}

get_tag_name :: (using parser: Xml_Parser) -> string {
	return parser.last_token_name;
}

get_message :: (using parser: *Xml_Parser) -> Xml_Message {
	if state == {
		case .INITIAL;
		if buffer.count <= 0 return .PARSED;
		skip_spaces(*buffer);
		if peek_first(buffer) != #char "<" {
			state = .ERROR;
			return .ERROR; // TODO(c4llv07e): Think what to do with errors and how to recover from them.
		}
		advance_move(*buffer);
		state = .TAG_START;
		return .TAG_BEGIN;
		case .TAG_START;
		save := buffer;
		ok, name := try_consume_name(*buffer);
		if ok {
			if last_token_name.data != null free(last_token_name.data);
			last_token_name = name;
			array_add(*names_stack, copy_string(name));
			state = .PROPERTIES;
			return .TAG_NAME;
		} else {
			buffer = save;
			return .PARSED;
		}
		case .PROPERTIES;
		skip_spaces(*buffer);
		if peek_first(buffer) == #char "/" {
			if peek_first(buffer, 1) != #char ">" {
				log("Got char / but not > after that");
				state = .ERROR;
				return .ERROR;
			}
			advance_move(*buffer, 2);
			state = .TAG_END;
			return .TAG_END;
		} else if (peek_first(buffer) == #char ">") {
			state = .TAG_INNER;
			advance_move(*buffer);
			return .TAG_END;
		}
		state = .ERROR;
		return .ERROR;
		case .TAG_INNER;
		if buffer.count <= 0 return .PARSED;
		if peek_first(buffer) == #char "<" {
			if peek_first(buffer, 1) != #char "/" {
				log("Found closing brace, but not slash after that");
				state = .ERROR;
				return .ERROR;
			}
			advance_move(*buffer, 2);
			skip_spaces(*buffer);
			ok, name := try_consume_name(*buffer);
			if !ok {
				log("Can't consume a name");
				state = .ERROR;
				return .ERROR;
			}
			if names_stack.count <= 0 {
				log("tags are unbalanced");
				state = .ERROR;
				return .ERROR;
			}
			opened_tag_name := peek(names_stack);
			if name != opened_tag_name {
				log("tag names missmatch");
				state = .ERROR;
				return .ERROR;
			}
			free(peek_pointer(names_stack));
			names_stack.count -= 1;
			skip_spaces(*buffer);
			if peek_first(buffer) != #char ">" {
				log("No > after `</tag_name'");
				state = .ERROR;
				return .ERROR;
			}
			advance_move(*buffer);
			if last_token_name.data != null free(last_token_name);
			last_token_name = copy_string(name);
			state = .INITIAL;
			return .TAG_END;
		}
		found_element, element_begin := array_find(buffer, #char "<");
		if last_text.data != null free(last_text);
		text: string = ---;
		text.data = buffer.data;
		if found_element
			text.count = element_begin;
		else
			text.count = buffer.count;
		last_text = copy_string(text);
		advance_move(*buffer, text.count);
		return .TAG_BODY;
		case;
		log("Unknown parser state: %\n", state);
		state = .ERROR;
		return .ERROR;
	}
	return .PARSED;
}

#run main();
main :: () {
	parser: Xml_Parser;
	append(*parser, "   <tag>  ");
	append(*parser, "Test");
	append(*parser, "</tag>");
	iter := 0;
	while true {
		log("text = `%'", get_unparsed(parser));
		msg := get_message(*parser);
		log("message = %", msg);
		if msg == .ERROR break;
		if msg == .PARSED break;
		iter += 1;
		if iter > 50 break;
	}
}

#import "Basic";