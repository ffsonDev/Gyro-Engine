class_name GyroExpression
extends RefCounted

const MAX_CACHE := 500
const MAX_FAIL_CACHE := 500

static var _ast_cache := {}
static var _fail_cache := {}
static var custom_fn: Callable
static var _ctx_stack: Array = []

static func current_context() -> Dictionary:
	return _ctx_stack.back() if not _ctx_stack.is_empty() else {}

static func is_valid_syntax(text: String) -> bool:
	if text.strip_edges() == "":
		return false
	var p := _Parser.new()
	p.src = text
	if not p.tokenize():
		return false
	if p.toks.is_empty():
		return false
	var ast = p.parse_or()
	return p.ok and p.ti >= p.toks.size() and not ast.is_empty()

static func try_eval(text: String, vars: Dictionary, payload: Dictionary, extra: Callable, out: Array, params: Dictionary = {}) -> bool:
	_ctx_stack.append({"vars": vars, "payload": payload, "extra": extra})
	var ok := _try_eval_inner(text, vars, payload, extra, out, params)
	_ctx_stack.pop_back()
	return ok

static func _try_eval_inner(text: String, vars: Dictionary, payload: Dictionary, extra: Callable, out: Array, params: Dictionary = {}) -> bool:
	if _fail_cache.has(text):
		return false
	if _ast_cache.has(text):
		var ast = _ast_cache[text]
		var err: Array = []
		var val = _eval_node(ast, vars, payload, extra, params, err)
		if not err.is_empty():
			return false
		if val is float and val == floorf(val):
			val = int(val)
		out.append(val)
		return true

	var p := _Parser.new()
	p.src = text
	p.vars = vars
	p.payload = payload
	p.extra = extra
	if not p.tokenize():
		_mark_fail(text)
		return false
	if p.toks.is_empty():
		_mark_fail(text)
		return false
		
	var ast = p.parse_or()
	if not p.ok or p.ti < p.toks.size():
		_mark_fail(text)
		return false

	if _ast_cache.size() >= MAX_CACHE:
		var keys_to_remove := _ast_cache.keys()
		keys_to_remove.resize(MAX_CACHE / 2)
		for k in keys_to_remove:
			_ast_cache.erase(k)
	_ast_cache[text] = ast
	var err2: Array = []
	var val = _eval_node(ast, vars, payload, extra, params, err2)
	if not err2.is_empty():
		return false
	if val is float and val == floorf(val):
		val = int(val)
	out.append(val)
	return true

static func _eval_node(node: Variant, vars: Dictionary, payload: Dictionary, extra: Callable, params: Dictionary = {}, err: Array = []) -> Variant:
	if node is Dictionary:
		var n: Dictionary = node
		match n.get("t", ""):
			"lit": return n.v
			"var": return vars.get(n.n, 0)
			"pay": return payload.get(n.n, 0)
			"param": return params.get(n.n, null)
			"bin":
				var l = _eval_node(n.l, vars, payload, extra, params, err)
				var r = _eval_node(n.r, vars, payload, extra, params, err)
				return _eval_bin(n.op, l, r)
			"un":
				var v = _eval_node(n.v, vars, payload, extra, params, err)
				if n.op == "-": return -_num(v)
				if n.op == "!" or n.op == "not": return not _truthy(v)
			"call":
				var args = []
				for a in n.args:
					args.append(_eval_node(a, vars, payload, extra, params, err))
				return _call(n.n, args, extra, err)
	return null

static func _eval_bin(op: String, a: Variant, b: Variant) -> Variant:
	match op:
		"+": return _add(a, b)
		"-": return _num(a) - _num(b)
		"*": return _num(a) * _num(b)
		"/":
			var d := _num(b)
			return _num(a) / d if d != 0.0 else 0.0
		"%":
			var d := _num(b)
			return fmod(_num(a), d) if d != 0.0 else 0.0
		"==": return _cmp("==", a, b)
		"!=": return _cmp("!=", a, b)
		"<": return _cmp("<", a, b)
		">": return _cmp(">", a, b)
		"<=": return _cmp("<=", a, b)
		">=": return _cmp(">=", a, b)
		"&&": return _truthy(a) and _truthy(b)
		"||": return _truthy(a) or _truthy(b)
	return false

static func _call(name: String, args: Array, extra: Callable, err: Array = []) -> Variant:
	match name:
		"min": return minf(_num(_at(args, 0)), _num(_at(args, 1))) if args.size() >= 2 else 0.0
		"max": return maxf(_num(_at(args, 0)), _num(_at(args, 1))) if args.size() >= 2 else 0.0
		"abs": return absf(_num(_at(args, 0)))
		"round": return roundf(_num(_at(args, 0)))
		"floor": return floorf(_num(_at(args, 0)))
		"ceil": return ceilf(_num(_at(args, 0)))
		"clamp": return clampf(_num(_at(args, 0)), _num(_at(args, 1)), _num(_at(args, 2))) if args.size() >= 3 else 0.0
		"rand": return randf_range(_num(_at(args, 0)), _num(_at(args, 1))) if args.size() >= 2 else randf()
		"len": return float(str(_at(args, 0)).length())
		"num": return _num(_at(args, 0))
		"text": return _to_text(_at(args, 0))
		"sqrt": return sqrt(maxf(0.0, _num(_at(args, 0))))
		"pow": return pow(_num(_at(args, 0)), _num(_at(args, 1))) if args.size() >= 2 else 0.0
		"sin": return sin(deg_to_rad(_num(_at(args, 0))))
		"cos": return cos(deg_to_rad(_num(_at(args, 0))))
		"tan": return tan(deg_to_rad(_num(_at(args, 0))))
		"atan2": return rad_to_deg(atan2(_num(_at(args, 1)), _num(_at(args, 0)))) if args.size() >= 2 else 0.0
		"sign": return signf(_num(_at(args, 0)))
		"lerp": return lerpf(_num(_at(args, 0)), _num(_at(args, 1)), _num(_at(args, 2))) if args.size() >= 3 else 0.0
		"map":
			if args.size() >= 5:
				var a1 := _num(_at(args, 1))
				var a2 := _num(_at(args, 2))
				if a1 == a2:
					return _num(_at(args, 3))
				var t := clampf((_num(_at(args, 0)) - a1) / (a2 - a1), 0.0, 1.0)
				return lerpf(_num(_at(args, 3)), _num(_at(args, 4)), t)
			return 0.0
		"pi": return PI
		"randi": return float(randi_range(int(_num(_at(args, 0))), int(_num(_at(args, 1))))) if args.size() >= 2 else 0.0
		"chance": return randf() < _num(_at(args, 0))
		"upper": return str(_at(args, 0)).to_upper()
		"lower": return str(_at(args, 0)).to_lower()
		"contains": return str(_at(args, 0)).contains(str(_at(args, 1))) if args.size() >= 2 else false
		"substr":
			if args.size() >= 3:
				return str(_at(args, 0)).substr(int(_num(_at(args, 1))), int(_num(_at(args, 2))))
			return str(_at(args, 0))
		"text_round":
			if args.size() >= 2:
				return "%.*f" % [int(_num(_at(args, 1))), _num(_at(args, 0))]
			return _to_text(_at(args, 0))
	if extra.is_valid():
		var r: Variant = extra.call(name, args)
		if r != null:
			return r
	if custom_fn.is_valid():
		var ur: Variant = custom_fn.call(name, args)
		if ur != null:
			return ur
	err.append(true)
	return null

static func _mark_fail(text: String) -> void:
	if _fail_cache.size() >= MAX_FAIL_CACHE:
		_fail_cache.clear()
	_fail_cache[text] = true

static func _at(a: Array, i: int) -> Variant:
	if i < a.size(): return a[i]
	return null

static func _num(v: Variant) -> float:
	if v is float: return float(v)
	if v is int: return float(int(v))
	if v is bool: return 1.0 if bool(v) else 0.0
	if v is String: return str(v).to_float()
	return 0.0

static func _truthy(v: Variant) -> bool:
	if v is bool: return bool(v)
	if v is float or v is int: return _num(v) != 0.0
	if v is String: return str(v) != ""
	return v != null

static func _add(a: Variant, b: Variant) -> Variant:
	if a is String or b is String: return _to_text(a) + _to_text(b)
	return _num(a) + _num(b)

static func _to_text(v: Variant) -> String:
	if v is float:
		var f := float(v)
		if f == floorf(f): return str(int(f))
		return str(f)
	if v == null: return ""
	return str(v)

static func _cmp(op: String, a: Variant, b: Variant) -> Variant:
	var use_str := (a is String) or (b is String)
	if use_str:
		var xs := _to_text(a)
		var ys := _to_text(b)
		match op:
			"==": return xs == ys
			"!=": return xs != ys
			"<": return xs < ys
			">": return xs > ys
			"<=": return xs <= ys
			">=": return xs >= ys
		return false
	var x := _num(a)
	var y := _num(b)
	match op:
		"==": return x == y
		"!=": return x != y
		"<": return x < y
		">": return x > y
		"<=": return x <= y
		">=": return x >= y
	return false

class Token:
	var kind := ""
	var text := ""
	var num := 0.0

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
	const MAX_SRC_LEN := 4096

	func _enter() -> bool:
		depth += 1
		if depth > MAX_DEPTH:
			ok = false
			return false
		return true

	func _leave() -> void:
		depth -= 1

	func tokenize() -> bool:
		if src.length() > MAX_SRC_LEN:
			ok = false
			return false
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
					if word == "var": t.kind = "var"
					elif word == "payload": t.kind = "pay"
					elif word == "param": t.kind = "param"
					else: return false
					t.text = src.substr(start, i - start)
					toks.append(t)
					continue
				return false
			if c == "\"" or c == "'":
				var j := i + 1
				while j < n and src[j] != c:
					j += 1
				if j >= n: return false
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

	func _is_digit(c: String) -> bool: return c >= "0" and c <= "9"
	func _is_ident_start(c: String) -> bool: return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_" or c.unicode_at(0) > 127
	func _is_ident_char(c: String) -> bool: return _is_ident_start(c) or _is_digit(c)

	func _cur() -> Token:
		if ti < toks.size(): return toks[ti] as Token
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

	func parse_or() -> Dictionary:
		if not _enter(): return {}
		var l = parse_and()
		while ok:
			if peek_op("||") or _peek_id("or"):
				var r = parse_and()
				l = {"t": "bin", "op": "||", "l": l, "r": r}
			else: break
		_leave()
		return l

	func parse_and() -> Dictionary:
		var l = parse_cmp()
		while ok:
			if peek_op("&&") or _peek_id("and"):
				var r = parse_cmp()
				l = {"t": "bin", "op": "&&", "l": l, "r": r}
			else: break
		return l

	func parse_cmp() -> Dictionary:
		var l = parse_add()
		while ok:
			var op := ""
			for o in ["==", "!=", "<=", ">=", "<", ">"]:
				var t := _cur()
				if t != null and t.kind == "op" and t.text == o:
					op = o
					ti += 1
					break
			if op == "": break
			l = {"t": "bin", "op": op, "l": l, "r": parse_add()}
		return l

	func parse_add() -> Dictionary:
		var l = parse_mul()
		while ok:
			if peek_op("+"):
				l = {"t": "bin", "op": "+", "l": l, "r": parse_mul()}
			elif peek_op("-"):
				l = {"t": "bin", "op": "-", "l": l, "r": parse_mul()}
			else: break
		return l

	func parse_mul() -> Dictionary:
		var l = parse_unary()
		while ok:
			if peek_op("*"):
				l = {"t": "bin", "op": "*", "l": l, "r": parse_unary()}
			elif peek_op("/"):
				l = {"t": "bin", "op": "/", "l": l, "r": parse_unary()}
			elif peek_op("%"):
				l = {"t": "bin", "op": "%", "l": l, "r": parse_unary()}
			else: break
		return l

	func parse_unary() -> Dictionary:
		if not _enter(): return {}
		var v: Dictionary
		if peek_op("-"):
			v = {"t": "un", "op": "-", "v": parse_unary()}
		elif peek_op("!") or _peek_id("not"):
			v = {"t": "un", "op": "!", "v": parse_unary()}
		else:
			v = parse_primary()
		_leave()
		return v

	func parse_primary() -> Dictionary:
		var t := _cur()
		if t == null:
			ok = false
			return {}
		if t.kind == "num":
			ti += 1
			return {"t": "lit", "v": t.num}
		if t.kind == "str":
			ti += 1
			return {"t": "lit", "v": t.text}
		if t.kind == "var":
			ti += 1
			return {"t": "var", "n": t.text}
		if t.kind == "pay":
			ti += 1
			return {"t": "pay", "n": t.text}
		if t.kind == "param":
			ti += 1
			return {"t": "param", "n": t.text}
		if t.kind == "op" and t.text == "(":
			ti += 1
			var v = parse_or()
			if not peek_op(")"):
				ok = false
			return v
		if t.kind == "id":
			var name := t.text
			ti += 1
			if name == "true": return {"t": "lit", "v": true}
			if name == "false": return {"t": "lit", "v": false}
			var nx := _cur()
			if nx != null and nx.kind == "op" and nx.text == "(":
				ti += 1
				var args: Array = []
				if not peek_op(")"):
					while ok:
						args.append(parse_or())
						if not peek_op(","): break
					if not peek_op(")"):
						ok = false
				return {"t": "call", "n": name, "args": args}
			return {"t": "call", "n": name, "args": []}
		ok = false
		return {}
