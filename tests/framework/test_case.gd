extends RefCounted

var parent: Node = null
var failures: Array = []
var checks := 0
var skipped := ""

func suite_name() -> String:
	return "unnamed"

func setup() -> void:
	pass

func teardown() -> void:
	pass

func skip(reason: String) -> void:
	skipped = reason

func fail(message: String) -> void:
	failures.append(message)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func eq(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if not deep_equal(actual, expected):
		failures.append("%s: expected [%s], got [%s]" % [label, str(expected), str(actual)])

func ne(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if deep_equal(actual, expected):
		failures.append("%s: value must differ from [%s]" % [label, str(expected)])

func approx(actual: float, expected: float, label: String, tolerance := 0.0001) -> void:
	checks += 1
	if not (absf(actual - expected) <= tolerance):
		failures.append("%s: expected %f +/- %f, got %f" % [label, expected, tolerance, actual])

func is_null(value: Variant, label: String) -> void:
	checks += 1
	if value != null:
		failures.append("%s: expected null, got [%s]" % [label, str(value)])

func not_null(value: Variant, label: String) -> void:
	checks += 1
	if value == null:
		failures.append("%s: unexpected null" % label)

func has(container: Variant, key: Variant, label: String) -> void:
	checks += 1
	var found := false
	if container is Dictionary:
		found = (container as Dictionary).has(key)
	elif container is Array:
		found = (container as Array).has(key)
	elif container is String:
		found = (container as String).contains(str(key))
	if not found:
		failures.append("%s: [%s] not found in [%s]" % [label, str(key), str(container)])

static func deep_equal(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		var ad := a as Dictionary
		var bd := b as Dictionary
		if ad.size() != bd.size():
			return false
		for k in ad:
			if not bd.has(k) or not deep_equal(ad[k], bd[k]):
				return false
		return true
	if a is Array and b is Array:
		var aa := a as Array
		var ba := b as Array
		if aa.size() != ba.size():
			return false
		for i in aa.size():
			if not deep_equal(aa[i], ba[i]):
				return false
		return true
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	return a == b
