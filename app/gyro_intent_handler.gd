extends Node
signal project_file_received(file_path: String)

func _ready() -> void:
	if OS.get_name() == "Android":
		call_deferred("_check_intent")

func _check_intent() -> void:
	var AndroidRuntime = Engine.get_singleton("AndroidRuntime")
	if not AndroidRuntime:
		return
	
	var activity = AndroidRuntime.getActivity()
	if not activity:
		return

	var IntentHelper = JavaClassWrapper.wrap("com.godot.game.IntentHelper")

	var temp_path = IntentHelper.copyIntentFile(activity)
	
	if temp_path and temp_path != "":
		var file_name = "imported_" + str(Time.get_unix_time_from_system()) + ".gyroproj"
		var dest_path = "user://" + file_name

		var in_file = FileAccess.open(temp_path, FileAccess.READ)
		if in_file:
			var out_file = FileAccess.open(dest_path, FileAccess.WRITE)
			if out_file:
				out_file.store_buffer(in_file.get_buffer(in_file.get_length()))
				out_file.close()
				in_file.close()

				var intent = activity.getIntent()
				intent.setAction("")
				intent.setData(null)
				project_file_received.emit(dest_path)
