class_name GyroDialog
extends Control

signal confirmed

func _ready() -> void:
	%Overlay.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event):
			visible = false
	)
	%OkButton.pressed.connect(func():
		visible = false
		confirmed.emit()
	)
	%CancelButton.pressed.connect(func(): visible = false)

func open(title: String, body: String, ok_text: String = "", cancel_text: String = "") -> void:
	if ok_text == "":
		ok_text = GyroLang.t("ok")
	if cancel_text == "":
		cancel_text = GyroLang.t("cancel")
	%TitleLabel.text = title
	%BodyLabel.text = body
	%OkButton.text = ok_text
	%CancelButton.text = cancel_text
	visible = true
