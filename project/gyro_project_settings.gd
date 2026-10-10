class_name GyroProjectSettings
extends Resource
@export var app_name := ""
@export var package_name := ""
@export var orientation := "auto"
@export var icon_path := ""
@export var version_code := 1
@export var version_name := "1.0.0"
@export var permissions: Array[String] = []
@export var keystore_path := ""
@export var keystore_alias := ""
@export var keystore_password := ""
@export var splash_path := icon_path
@export var build_release_version := false
@export var debug_ks_path := "user://android_keystore.keystore"
@export var debug_ks_alias := "androiddebugkey"
@export var debug_ks_password := "android"

func auto_fill(project_name: String) -> void:
	if app_name == "":
		app_name = project_name

	if package_name == "" or package_name == "com.example.app":
		var clean := project_name.to_lower()
		var sanitized := ""
		for i in clean.length():
			var ch := clean[i]
			if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_":
				sanitized += ch
			elif ch == " " or ch == "-":
				sanitized += "_"
		while sanitized.length() > 0 and (sanitized[0] >= "0" and sanitized[0] <= "9" or sanitized[0] == "_"):
			sanitized = sanitized.substr(1)
		if sanitized == "":
			sanitized = "app"
		package_name = "com.example." + sanitized
