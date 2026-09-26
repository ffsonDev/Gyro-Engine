class_name GyroExpression
extends RefCounted

static func try_eval(text: String, vars: Dictionary, payload: Dictionary, extra: Callable, out: Array) -> bool:
	var p := _Parser.new()
	p.src = text
	p.vars = vars
	p.payload = payload
	p.extra = extra
	if not p.tokenize():
		return false
	if p.toks.is_empty():
		return false
	var value: Variant = p.parse_or()
	if not p.ok or p.ti < p.toks.size():
		return false
	if value is float:
		var f := float(value)
		if f == floorf(f):
			value = int(f)
	out.append(value)
	return true


class Token:
	var kind := ""
	var text := ""
	var num := 0


class _Parser:
	var src := ""
	var toks: Array = []
	var ti := 0
	var ok := true
	var depth := 0
	const MAX_DEPTH := 64 
	var vars: Dictionary
	var payload: Dictionary
	var extra: Callable
	
	func _enter() -> bool:
		depth += 1
		if depth > MAX_DEPTH:
			ok = false
			return false
		return true

	func _leave() -> void:
		depth -= 1

	func tokenize() -> bool:
		var i := 0
		var n := src.length()
		while i < n:
			var c := src[i]
			if c == " " or c == "\t" or c == "\n":
				i += 1
				continue
			if _is_digit(c) or (c == "." and i + 1 < n and _is_digit(src[i + 1])):
				var j := i
				while j < n and (_is_digit(src[j]) or src[j] == "."):
					j += 1
				var t := Token.new()
				t.kind = "num"
				t.num = src.substr(i, j - i).to_float()
				toks.append(t)
				i = j
				continue
			if c == "$":
				i += 1
				var start := i
				while i < n and _is_ident_char(src[i]):
					i += 1
				var word := src.substr(start, i - start)
				if i < n and src[i] == ".":
					i += 1
					start = i
					while i < n and _is_ident_char(src[i]):
						i += 1
					var t := Token.new()
					if word == "var":
						t.kind = "var"
					elif word == "payload":
						t.kind = "pay"
					else:
						return false
					t.text = src.substr(start, i - start)
					toks.append(t)
					continue
				return false
			if c == "\"" or c == "'":
				var j := i + 1
				while j < n and src[j] != c:
					j += 1
				if j >= n:
					return false
				var t := Token.new()
				t.kind = "str"
				t.text = src.substr(i + 1, j - i - 1)
				toks.append(t)
				i = j + 1
				continue
			if _is_ident_start(c):
				var start := i
				while i < n and _is_ident_char(src[i]):
					i += 1
				var t := Token.new()
				t.kind = "id"
				t.text = src.substr(start, i - start)
				toks.append(t)
				continue
			var two := src.substr(i, 2)
			if two == "==" or two == "!=" or two == "<=" or two == ">=" or two == "&&" or two == "||":
				var t := Token.new()
				t.kind = "op"
				t.text = two
				toks.append(t)
				i += 2
				continue
			if c == "+" or c == "-" or c == "*" or c == "/" or c == "%" or c == "(" or c == ")" or c == "<" or c == ">" or c == "!" or c == ",":
				var t := Token.new()
				t.kind = "op"
				t.text = c
				toks.append(t)
				i += 1
				continue
			return false
		return true

	func _is_digit(c: String) -> bool:
		return c >= "0" and c <= "9"

	func _is_ident_start(c: String) -> bool:
		return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_" or c.unicode_at(0) > 127

	func _is_ident_char(c: String) -> bool:
		return _is_ident_start(c) or _is_digit(c)

	func _cur() -> Token:
		if ti < toks.size():
			return toks[ti] as Token
		return null

	func peek_op(op: String) -> bool:
		var t := _cur()
		if t != null and t.kind == "op" and t.text == op:
			ti += 1
			return true
		return false

	func _peek_id(word: String) -> bool:
		var t := _cur()
		if t != null and t.kind == "id" and t.text == word:
			ti += 1
			return true
		return false

	func parse_or() -> Variant:
		if not _enter():
			return null
		var v: Variant = parse_and()
		while ok:
			if peek_op("||") or _peek_id("or"):
				v = _truthy(v) or _truthy(parse_and())
			else:
				break
		_leave()
		return v

	func parse_and() -> Variant:
		var v: Variant = parse_cmp()
		while ok:
			if peek_op("&&") or _peek_id("and"):
				v = _truthy(v) and _truthy(parse_cmp())
			else:
				break
		return v

	func parse_cmp() -> Variant:
		var v: Variant = parse_add()
		while ok:
			var op := ""
			for o in ["==", "!=", "<=", ">=", "<", ">"]:
				var t := _cur()
				if t != null and t.kind == "op" and t.text == o:
					op = o
					ti += 1
					break
			if op == "":
				break
			v = _cmp(op, v, parse_add())
		return v

	func parse_add() -> Variant:
		var v: Variant = parse_mul()
		while ok:
			if peek_op("+"):
				v = _add(v, parse_mul())
			elif peek_op("-"):
				v = _num(v) - _num(parse_mul())
			else:
				break
		return v

	func parse_mul() -> Variant:
		var v: Variant = parse_unary()
		while ok:
			if peek_op("*"):
				v = _num(v) * _num(parse_unary())
			elif peek_op("/"):
				var d := _num(parse_unary())
				v = _num(v) / d if d != 0.0 else 0.0
			elif peek_op("%"):
				var d := _num(parse_unary())
				v = fmod(_num(v), d) if d != 0.0 else 0.0
			else:
				break
		return v

	func parse_unary() -> Variant:
		if not _enter():
			return null
		var v: Variant
		if peek_op("-"):
			v = -_num(parse_unary())
		elif peek_op("!") or _peek_id("not"):
			v = not _truthy(parse_unary())
		else:
			v = parse_primary()
		_leave()
		return v

	func parse_primary() -> Variant:
		var t := _cur()
		if t == null:
			ok = false
			return null
		if t.kind == "num":
			ti += 1
			return t.num
		if t.kind == "str":
			ti += 1
			return t.text
		if t.kind == "var":
			ti += 1
			return vars.get(t.text, 0)
		if t.kind == "pay":
			ti += 1
			return payload.get(t.text, 0)
		if t.kind == "op" and t.text == "(":
			ti += 1
			var v: Variant = parse_or()
			if not peek_op(")"):
				ok = false
			return v
		if t.kind == "id":
			var name := t.text
			ti += 1
			if name == "true":
				return true
			if name == "false":
				return false
			var nx := _cur()
			if nx != null and nx.kind == "op" and nx.text == "(":
				ti += 1
				var args: Array = []
				if not peek_op(")"):
					while ok:
						args.append(parse_or())
						if not peek_op(","):
							break
					if not peek_op(")"):
						ok = false
				return _call(name, args)
			if extra.is_valid():
				var r: Variant = extra.call(name, [])
				if r == null:
					ok = false
				return r
			ok = false
			return null
		ok = false
		return null

	func _call(name: String, args: Array) -> Variant:
		match name:
			"min":
				return minf(_num(_at(args, 0)), _num(_at(args, 1))) if args.size() >= 2 else 0.0
			"max":
				return maxf(_num(_at(args, 0)), _num(_at(args, 1))) if args.size() >= 2 else 0.0
			"abs":
				return absf(_num(_at(args, 0)))
			"round":
				return roundf(_num(_at(args, 0)))
			"floor":
				return floorf(_num(_at(args, 0)))
			"ceil":
				return ceilf(_num(_at(args, 0)))
			"clamp":
				return clampf(_num(_at(args, 0)), _num(_at(args, 1)), _num(_at(args, 2))) if args.size() >= 3 else 0.0
			"rand":
				return randf_range(_num(_at(args, 0)), _num(_at(args, 1))) if args.size() >= 2 else randf()
			"len":
				return float(str(_at(args, 0)).length())
			"num":
				return _num(_at(args, 0))
			"text":
				return _to_text(_at(args, 0))
		if extra.is_valid():
			var r: Variant = extra.call(name, args)
			if r == null:
				ok = false
			return r
		ok = false
		return null

	func _at(a: Array, i: int) -> Variant:
		if i < a.size():
			return a[i]
		return null

	func _num(v: Variant) -> float:
		if v is float:
			return float(v)
		if v is int:
			return float(int(v))
		if v is bool:
			return 1.0 if bool(v) else 0.0
		if v is String:
			return str(v).to_float()
		return 0.0

	func _truthy(v: Variant) -> bool:
		if v is bool:
			return bool(v)
		if v is float or v is int:
			return _num(v) != 0.0
		if v is String:
			return str(v) != ""
		return v != null

	func _add(a: Variant, b: Variant) -> Variant:
		if a is String or b is String:
			return _to_text(a) + _to_text(b)
		return _num(a) + _num(b)

	func _to_text(v: Variant) -> String:
		if v is float:
			var f := float(v)
			if f == floorf(f):
				return str(int(f))
			return str(f)
		if v == null:
			return ""
		return str(v)

	func _cmp(op: String, a: Variant, b: Variant) -> Variant:
		var use_str := (a is String) or (b is String)
		if use_str:
			var xs := _to_text(a)
			var ys := _to_text(b)
			match op:
				"==":
					return xs == ys
				"!=":
					return xs != ys
				"<":
					return xs < ys
				">":
					return xs > ys
				"<=":
					return xs <= ys
				">=":
					return xs >= ys
			return false
		var x := _num(a)
		var y := _num(b)
		match op:
			"==":
				return x == y
			"!=":
				return x != y
			"<":
				return x < y
			">":
				return x > y
			"<=":
				return x <= y
			">=":
				return x >= y
		return false
