@abstract class_name VDF
extends Node


static func ParseFile(vdf_path: String, allow_escape_quotes := false) -> KeyValues:
	var kv_master := KeyValues.new()
	
	var lines := FileAccess.open(vdf_path, FileAccess.READ).get_as_text().split("\n")
	var tokens: PackedStringArray
	
	var token_line_array: PackedInt32Array
	
	# remove comments, gather tokens, and associate line numbers
	for i in range(len(lines)):
		var line := SplitString(lines[i], allow_escape_quotes)
		for j in range(len(line)):
			var token := line[j]
			if token.begins_with("//"):
				line.resize(i)
				break
		tokens.append_array(line)
		
		# associate token index with line number
		var last_array_size = token_line_array.size()
		token_line_array.resize(tokens.size())
		for j in range(last_array_size, token_line_array.size()):
			token_line_array[j] = i + 1
	
	var last_key := ""
	var current_superkey: KeyValuePair = null
	for i in range(len(tokens)):
		var token = tokens[i]
		if not last_key:
			match token:
				"{":
					push_error("Subkey with no name! (Line %s)" % token_line_array[i])
					return
				"}":
					# close subkey
					if current_superkey:
						current_superkey = current_superkey.superkey
					else:
						push_error("'}' with no opening bracket! (Line %s)" % token_line_array[i])
						return
				_:
					last_key = token
		else:
			match token:
				"{":
					# open subkey
					current_superkey = KeyValuePair.new(last_key, {}, kv_master, current_superkey)
					last_key = ""
				"}":
					push_error("Expected value, got '}'! (Line %s)" % token_line_array[i])
					return
				_:
					KeyValuePair.new(last_key, token, kv_master, current_superkey)
					last_key = ""
	if last_key:
		push_error("Expected value, got EOF! (Line %s)" % token_line_array[-1])
		return
	return kv_master


static func WriteFile(
		vdf: KeyValues,
		file_path: String,
		readable := true,
		allow_escape_quotes := false
	) -> bool:
	var vdf_text = _WriteRecursive(vdf.root, readable, allow_escape_quotes)
	if not readable:
		vdf_text = vdf_text.replace("{\n", "{").replace("\n}", "}")
	
	return FileAccess.open(file_path, FileAccess.WRITE).store_string(vdf_text)


static func _WriteRecursive(
		keys: Dictionary,
		readable: bool,
		allow_escape_quotes: bool,
		tab_level: int = 0
	) -> String:
	var subkey_text := "\n" if tab_level else ""
	for kv: KeyValuePair in keys.values():
		# quote key if it has whitespace or is a number and add correct number of tabs
		subkey_text += (("\t".repeat(tab_level) if readable else "") +
				('"%s"' % kv.key.c_escape() if
					HasWhitespace(kv.key) or
					str(int(kv.key)) == kv.key or
					str(float(kv.key)) == kv.key
				else kv.key.c_escape())
			)
		if kv.value is Dictionary: # TODO: replace with type enum?
			subkey_text += (
					(" {" if readable else "{") +
					_WriteRecursive(kv.value, readable, allow_escape_quotes, tab_level + 1) +
					("\t".repeat(tab_level) + "}" if readable else "}")
				)
		else:
			subkey_text += " " + kv.GetValueAsString(true)
		
		subkey_text += "\n"
	
	# replace escaped double quotes with backticks
	# (double quotes in the vdf breaks things unless explicitly stated otherwise)
	if not allow_escape_quotes:
		subkey_text.replace('\\"', "`")
	
	return subkey_text


class KeyValues extends VDF:
	var root: Dictionary[int, KeyValuePair]
	var all_keys: Dictionary[int, KeyValuePair]
	
	var saved_searches: Dictionary[StringName, PackedInt32Array]
	
	var next_key_id: int = 0:
		get:
			next_subkey_id += 1
			return next_subkey_id - 1
	
	var next_subkey_id: int = 0:
		get:
			next_subkey_id += 1
			return next_subkey_id - 1


class KeyValuePair extends VDF:
	enum Type {
		TYPE_NONE = 0,
		TYPE_STRING, # String (utf-8)
		TYPE_INT, # int
		TYPE_FLOAT, # float
		TYPE_PTR, # pointer
		TYPE_WSTRING, # String (utf-16)
		TYPE_COLOR, # Vector4
		TYPE_UINT64, # int
	}
	var absolute_id: int
	var subkey_id: int
	var key: StringName
	var value: Variant
	var superkey: KeyValuePair
	var master: KeyValues
	
	var next_subkey_id: int = 0:
		get:
			next_subkey_id += 1
			return next_subkey_id - 1
	
	@warning_ignore("shadowed_variable")
	func _init(key: StringName, value, master: KeyValues, superkey: KeyValuePair = null) -> void:
		self.key = key
		self.value = value
		self.master = master
		self.superkey = superkey
		
		absolute_id = master.next_key_id
		master.all_keys[absolute_id] = self
		if superkey:
			subkey_id = superkey.next_subkey_id
			superkey.value[subkey_id] = self
			superkey.add_child(self)
		else:
			subkey_id = master.next_subkey_id
			master.root[subkey_id] = self
			master.add_child(self)
	
	
	func GetValueAsString(always_quote := false) -> String:
		# TODO: utilize type enum
		var string = value as String
		return '"%s"' % string.c_escape() if always_quote or HasWhitespace(string) or not string \
				else string.c_escape()
	
	
	func GetNextKey() -> KeyValuePair:
		if superkey:
			return superkey.value[(subkey_id + 1) % len(superkey.value)]
		else:
			return master.root[(subkey_id + 1) % len(master.root)]
	
	
	func GetPreviousKey() -> KeyValuePair:
		if superkey:
			return superkey.value[-(-(subkey_id - 1) % len(superkey.value))]
		else:
			return master.root[-(-(subkey_id - 1) % len(master.root))]


static func SplitString(string: String, allow_escape_quotes := false) -> PackedStringArray:
	if allow_escape_quotes:
		assert((string.count('"') - string.count('\\"')) % 2 == 0, "ERROR: Unclosed string!")
	else:
		assert(string.count('"') % 2 == 0, "ERROR: Unclosed string!")
	var string_elements: PackedStringArray = [""]
	var last_char: String
	var in_string := false
	var grouped_elements: Array[int]
	var element_index: int = 0
	string = string.replace("{", " { ").replace("}", " } ")
	for character in string:
		if character == '"' and (not last_char == "\\" or not allow_escape_quotes):
				in_string = not in_string
				if not in_string: grouped_elements.append(element_index)
				element_index += 1
				string_elements.append("")
				continue
		string_elements[element_index] += character
		last_char = character
	var return_array: PackedStringArray
	for i in range(len(string_elements)):
		var element = string_elements[i]
		if i in grouped_elements:
			return_array.append(element.c_unescape())
		else:
			return_array.append_array(SplitWhitespace(element.c_unescape()))
	return return_array


static func SplitWhitespace(string: String) -> PackedStringArray:
	var arr1 := string.split(" ", false)
	var arr2: PackedStringArray
	for str_temp in arr1:
		arr2.append_array(str_temp.split("\r", false))
	arr1 = []
	for str_temp in arr2:
		arr1.append_array(str_temp.split("\n", false))
	arr2 = []
	for str_temp in arr1:
		arr2.append_array(str_temp.split("\t", false))
	
	return arr2


static func HasWhitespace(string: String) -> bool:
	return (
			" " in string or
			"\n" in string or
			"\r" in string or
			"\t" in string
	)
