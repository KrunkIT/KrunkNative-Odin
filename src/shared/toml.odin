package shared

import "core:fmt"
import "core:strconv"
import "core:strings"

Toml_Value :: union {
	string,
	i64,
	f64,
	bool,
	[]Toml_Value,
}

Toml_Table :: struct {
	values: map[string]Toml_Value,
	tables: map[string]^Toml_Table,
}

// toml_parse parses a minimal TOML subset: [section], [section.sub], key = value,
// comments (#), strings, booleans, integers (incl. 0x hex), floats, and arrays
// (including arrays that span multiple lines).
toml_parse :: proc(source: string) -> (root: ^Toml_Table, ok: bool) {
	root = new(Toml_Table)
	current := root

	lines := strings.split_lines(source)
	defer delete(lines)

	// When a value starts with '[' it may continue onto following lines.
	// Accumulate the value text until its brackets balance.
	pending_key: string
	value_builder := strings.builder_make()
	defer strings.builder_destroy(&value_builder)
	collecting_value := false

	for &line in lines {
		line = toml_strip_comment(line)
		line = strings.trim_space(line)

		if collecting_value {
			if len(line) > 0 {
				strings.write_string(&value_builder, line)
			}

			if toml_brackets_balanced(strings.to_string(value_builder)) {
				value_text := strings.trim_space(strings.to_string(value_builder))
				if value, v_ok := toml_parse_value(value_text); v_ok {
					current.values[pending_key] = value
				} else {
					fmt.eprintf("config: failed to parse value for %q\n", pending_key)
				}
				collecting_value = false
				pending_key = ""
			}
			continue
		}

		if len(line) == 0 {
			continue
		}

		if line[0] == '[' {
			close := strings.index(line, "]")
			if close < 0 {
				continue
			}

			header := strings.trim_space(line[1:close])
			current = root

			parts := strings.split(header, ".")
			defer delete(parts)

			for &part in parts {
				part = strings.trim_space(part)
				if len(part) == 0 {
					continue
				}

				next, has := current.tables[part]
				if !has {
					next = new(Toml_Table)
					current.tables[part] = next
				}
				current = next
			}
			continue
		}

		eq := strings.index(line, "=")
		if eq < 0 {
			continue
		}

		key := strings.trim_space(line[:eq])
		value_text := strings.trim_space(line[eq + 1:])

		if strings.has_prefix(value_text, "[") && !toml_brackets_balanced(value_text) {
			pending_key = key
			strings.builder_reset(&value_builder)
			strings.write_string(&value_builder, value_text)
			collecting_value = true
			continue
		}

		value, v_ok := toml_parse_value(value_text)
		if !v_ok {
			fmt.eprintf("config: failed to parse value for %q\n", key)
			continue
		}

		current.values[key] = value
	}

	return root, true
}

// toml_brackets_balanced reports whether every '[' has a matching ']' outside
// of quoted strings.
toml_brackets_balanced :: proc(text: string) -> bool {
	depth := 0
	in_string := false

	for i := 0; i < len(text); i += 1 {
		c := text[i]

		if in_string {
			if c == '"' && (i == 0 || text[i - 1] != '\\') {
				in_string = false
			}
			continue
		}

		if c == '"' {
			in_string = true
		} else if c == '[' {
			depth += 1
		} else if c == ']' {
			depth -= 1
		}
	}

	return depth <= 0
}

toml_strip_comment :: proc(line: string) -> string {
	in_string := false

	for i in 0 ..< len(line) {
		c := line[i]

		if in_string {
			if c == '"' {
				in_string = false
			}
			continue
		}

		if c == '"' {
			in_string = true
			continue
		}

		if c == '#' {
			return line[:i]
		}
	}

	return line
}

toml_parse_value :: proc(original: string) -> (Toml_Value, bool) {
	text := original
	text = strings.trim_space(text)
	if len(text) == 0 {
		return nil, false
	}

	switch text[0] {
	case '"':
		end, ok := toml_find_string_end(text)
		if !ok {
			return nil, false
		}
		return toml_unescape(text[1:end]), true
	case '[':
		return toml_parse_array(text)
	case 't', 'f':
		if text == "true" {
			return true, true
		}
		if text == "false" {
			return false, true
		}
	}

	if strings.contains(text, ".") {
		if f, ok := strconv.parse_f64(text); ok {
			return f, true
		}
		return nil, false
	}

	if i, ok := strconv.parse_i64_maybe_prefixed(text); ok {
		return i, true
	}

	if f, ok := strconv.parse_f64(text); ok {
		return f, true
	}

	return nil, false
}

toml_find_string_end :: proc(text: string) -> (int, bool) {
	if len(text) < 2 || text[0] != '"' {
		return -1, false
	}

	for i := 1; i < len(text); i += 1 {
		if text[i] == '\\' {
			i += 1
			continue
		}
		if text[i] == '"' {
			return i, true
		}
	}

	return -1, false
}

toml_unescape :: proc(s: string) -> string {
	if !strings.contains(s, "\\") {
		return s
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for i := 0; i < len(s); i += 1 {
		c := s[i]

		if c == '\\' && i + 1 < len(s) {
			i += 1
			switch s[i] {
			case 'n':
				strings.write_byte(&builder, '\n')
			case 't':
				strings.write_byte(&builder, '\t')
			case '"':
				strings.write_byte(&builder, '"')
			case '\\':
				strings.write_byte(&builder, '\\')
			case:
				strings.write_byte(&builder, '\\')
				strings.write_byte(&builder, s[i])
			}
		} else {
			strings.write_byte(&builder, c)
		}
	}

	return strings.to_string(builder)
}

toml_parse_array :: proc(text: string) -> (Toml_Value, bool) {
	if len(text) < 2 || text[0] != '[' {
		return nil, false
	}

	elements: [dynamic]Toml_Value

	depth := 0
	in_string := false
	start := 1

	for i := 1; i < len(text); i += 1 {
		c := text[i]

		if in_string {
			if c == '\\' {
				i += 1
				continue
			}
			if c == '"' {
				in_string = false
			}
			continue
		}

		switch c {
		case '"':
			in_string = true
		case '[', '{':
			depth += 1
		case ']', '}':
			if depth == 0 {
				element := strings.trim_space(text[start:i])
				if len(element) > 0 {
					if value, value_ok := toml_parse_value(element); value_ok {
						append(&elements, value)
					}
				}
				return elements[:], true
			}
			depth -= 1
		case ',':
			if depth == 0 {
				element := strings.trim_space(text[start:i])
				if len(element) > 0 {
					if value, value_ok := toml_parse_value(element); value_ok {
						append(&elements, value)
					}
				}
				start = i + 1
			}
		}
	}

	return nil, false
}

toml_destroy :: proc(table: ^Toml_Table) {
	if table == nil {
		return
	}

	for _, value in table.values {
		toml_value_destroy(value)
	}
	delete(table.values)

	for _, sub in table.tables {
		toml_destroy(sub)
	}
	delete(table.tables)

	free(table)
}

toml_value_destroy :: proc(value: Toml_Value) {
	if arr, ok := value.([]Toml_Value); ok {
		for elem in arr {
			toml_value_destroy(elem)
		}
		delete(arr)
	}
}

// ---- typed accessors -------------------------------------------------------

toml_get :: proc(table: ^Toml_Table, key: string) -> (Toml_Value, bool) {
	if table == nil {
		return nil, false
	}
	return table.values[key]
}

toml_get_string :: proc(table: ^Toml_Table, key: string) -> (string, bool) {
	value, present := toml_get(table, key)
	if !present {
		return "", false
	}
	s, ok := value.(string)
	return s, ok
}

toml_get_bool :: proc(table: ^Toml_Table, key: string) -> (bool, bool) {
	value, present := toml_get(table, key)
	if !present {
		return false, false
	}
	b, ok := value.(bool)
	return b, ok
}

toml_get_f32 :: proc(table: ^Toml_Table, key: string) -> (f32, bool) {
	value, present := toml_get(table, key)
	if !present {
		return 0, false
	}

	#partial switch n in value {
	case f64:
		return f32(n), true
	case i64:
		return f32(n), true
	}

	return 0, false
}

toml_get_i64 :: proc(table: ^Toml_Table, key: string) -> (i64, bool) {
	value, present := toml_get(table, key)
	if !present {
		return 0, false
	}
	n, ok := value.(i64)
	return n, ok
}

toml_get_array :: proc(table: ^Toml_Table, key: string) -> ([]Toml_Value, bool) {
	value, present := toml_get(table, key)
	if !present {
		return nil, false
	}
	arr, ok := value.([]Toml_Value)
	return arr, ok
}

toml_array_get_f32 :: proc(array: []Toml_Value, index: int) -> (f32, bool) {
	if index < 0 || index >= len(array) {
		return 0, false
	}

	#partial switch n in array[index] {
	case f64:
		return f32(n), true
	case i64:
		return f32(n), true
	}

	return 0, false
}

toml_array_get_i64 :: proc(array: []Toml_Value, index: int) -> (i64, bool) {
	if index < 0 || index >= len(array) {
		return 0, false
	}

	n, ok := array[index].(i64)
	return n, ok
}

toml_array_get_string :: proc(array: []Toml_Value, index: int) -> (string, bool) {
	if index < 0 || index >= len(array) {
		return "", false
	}

	s, ok := array[index].(string)
	return s, ok
}

toml_array_get_array :: proc(array: []Toml_Value, index: int) -> ([]Toml_Value, bool) {
	if index < 0 || index >= len(array) {
		return nil, false
	}

	arr, ok := array[index].([]Toml_Value)
	return arr, ok
}
