class_name TimerSystem
extends GyroSystem

var _timer_repeats := {}

func execute(action: GyroAction, payload: Dictionary) -> void:
	match action.type:
		"StartTimer":
			var timer_name := str(runtime._resolve_value(action.data.get("name", ""), payload))
			if timer_name == "":
				return
			var wait := runtime._to_float(runtime._resolve_value(action.data.get("wait", 1.0), payload))
			var one_shot := runtime._to_bool(runtime._resolve_value(action.data.get("one_shot", true), payload))
			var repeat := int(runtime._to_float(runtime._resolve_value(action.data.get("repeat", 1), payload)))
			if repeat > 1:
				_timer_repeats[timer_name] = {"repeat": repeat - 1, "wait": maxf(0.05, wait)}
			host.start_timer(timer_name, maxf(0.05, wait), one_shot)
		"StopTimer":
			var timer_name := str(runtime._resolve_value(action.data.get("name", ""), payload))
			if timer_name == "":
				return
			host.stop_timer(timer_name)

func on_timer_fired(timer_name: String) -> void:
	var meta = _timer_repeats.get(timer_name, null)
	if meta == null:
		return
	if int(meta.repeat) > 0:
		meta.repeat = int(meta.repeat) - 1
		if host != null:
			host.start_timer(timer_name, float(meta.wait), true)
	else:
		_timer_repeats.erase(timer_name)
