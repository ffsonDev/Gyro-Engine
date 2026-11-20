class_name GyroCustomBlock
extends Resource

@export var block_id := ""
@export var block_name := ""
@export var author := ""
@export var color := Color(0.55, 0.40, 0.60)
@export var fields: Array = []
@export var body: Array[GyroAction] = []

func renderer_schema() -> Array:
	var out: Array = []
	for f in fields:
		out.append([str(f.get("key", "")), str(f.get("label", "")), str(f.get("pick", ""))])
	return out
