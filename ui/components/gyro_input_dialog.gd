class_name GyroInputDialog
extends Control

signal confirmed_text(text: String)

func _ready() -> void:
	%Overlay.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event):
			visible = false
	)
	%OkButton.pressed.connect(func():
		visible = false
		confirmed_text.emit(%Input.text)
	)
	%CancelButton.pressed.connect(func(): visible = false)

func open(title: String, placeholder: String, initial: String, ok_text: String = "", cancel_text: String = "") -> void:
	if ok_text == "":
		ok_text = GyroLang.t("ok")
	if cancel_text == "":
		cancel_text = GyroLang.t("cancel")
	%TitleLabel.text = title
	%Input.placeholder_text = placeholder
	%Input.text = initial
	%OkButton.text = ok_text
	%CancelButton.text = cancel_text
	visible = true
