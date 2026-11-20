class_name GyroBuildDialog
extends Control

signal build_completed(success: bool, output_path: String)

var _builder: GyroApkBuilder = null
var _out_path := ""
var _log_lines: Array[String] = []
var _start_time := 0
var _finished := false

@onready var overlay: ColorRect = $Overlay
@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var stage_label: Label = $Panel/VBox/StageLabel
@onready var progress_bar: ProgressBar = $Panel/VBox/ProgressBar
@onready var log_label: RichTextLabel = $Panel/VBox/LogScroll/LogLabel
@onready var cancel_btn: Button = $Panel/VBox/ButtonsHBox/CancelButton
@onready var close_btn: Button = $Panel/VBox/ButtonsHBox/CloseButton

func _ready() -> void:
	visible = false
	_apply_styles()
	cancel_btn.pressed.connect(_on_cancel)
	close_btn.pressed.connect(func(): visible = false)
	overlay.gui_input.connect(func(event: InputEvent):
		if GyroUI.is_tap(event) and _finished:
			visible = false
	)
	_update_lang()

func _apply_styles() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = DesignTokens.PANEL_BG
	style.set_corner_radius_all(DesignTokens.RADIUS_XL)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = DesignTokens.PANEL_BORDER
	style.content_margin_left = DesignTokens.SPACING_XL
	style.content_margin_right = DesignTokens.SPACING_XL
	style.content_margin_top = DesignTokens.SPACING_XL
	style.content_margin_bottom = DesignTokens.SPACING_XL
	panel.add_theme_stylebox_override("panel", style)
	title_label.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	title_label.add_theme_font_size_override("font_size", GyroUI.fs(22))
	stage_label.add_theme_color_override("font_color", Color.WHITE)
	stage_label.add_theme_font_size_override("font_size", GyroUI.fs(14))
	progress_bar.custom_minimum_size = Vector2(0, GyroUI.sz(28))
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.175, 0.192, 0.22, 1.0)
	fill.set_corner_radius_all(DesignTokens.RADIUS_FULL)
	progress_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.107, 0.129, 1.0)
	bg.set_corner_radius_all(DesignTokens.RADIUS_FULL)
	progress_bar.add_theme_stylebox_override("background", bg)

func _update_lang() -> void:
	title_label.text = GyroLang.t("build_apk")
	cancel_btn.text = GyroLang.t("cancel")
	close_btn.text = GyroLang.t("close")

func is_building() -> bool:
	return _builder != null and _builder.is_running()

func start_build(project: GyroProject, project_path: String, out_path: String) -> void:
	if is_building():
		return
	if project == null or project.settings == null:
		return
	_begin_build(project, project_path, out_path)

func _begin_build(project: GyroProject, project_path: String, out_path: String) -> void:
	_out_path = out_path
	_log_lines.clear()
	_finished = false
	_start_time = Time.get_ticks_msec()
	progress_bar.value = 0.0
	stage_label.text = ""
	stage_label.add_theme_color_override("font_color", Color.WHITE)
	log_label.text = ""
	cancel_btn.visible = true
	cancel_btn.disabled = false
	close_btn.visible = false
	visible = true
	_builder = GyroApkBuilder.new()
	_builder.progress_changed.connect(_on_progress, CONNECT_DEFERRED)
	_builder.log_added.connect(_on_log, CONNECT_DEFERRED)
	_builder.build_finished.connect(_on_build_done, CONNECT_DEFERRED)
	_builder.start(project, project_path, out_path)

func _on_progress(value: float, stage: String) -> void:
	progress_bar.value = value * 100.0
	var names := {
		"validate": "1/4 " + GyroLang.t("build_stage_validate"),
		"compile": "2/4 " + GyroLang.t("build_stage_compile"),
		"link": "3/4 " + GyroLang.t("build_stage_link"),
		"sign": "4/4 " + GyroLang.t("build_stage_sign"),
		"done": GyroLang.t("build_stage_done"),
	}
	stage_label.text = names.get(stage, stage)
	stage_label.add_theme_color_override("font_color", Color.WHITE)

func _on_log(text: String) -> void:
	var elapsed := (Time.get_ticks_msec() - _start_time) / 1000.0
	_log_lines.append("[color=#6b7280][%.1fs][/color] %s" % [elapsed, text])
	log_label.text = "\n".join(_log_lines)
	log_label.scroll_to_line(log_label.get_line_count() - 1)

func _on_cancel() -> void:
	if _builder != null and _builder.is_running():
		_builder.cancel()
		cancel_btn.disabled = true
		_on_log("[color=#f59e0b]%s[/color]" % GyroLang.t("build_cancelled"))

func _on_build_done(success: bool, error: String, output_path: String) -> void:
	_finished = true
	cancel_btn.visible = false
	close_btn.visible = true
	var elapsed := (Time.get_ticks_msec() - _start_time) / 1000.0
	if error == GyroApkBuilder.CANCELLED:
		stage_label.text = GyroLang.t("build_cancelled")
		stage_label.add_theme_color_override("font_color", DesignTokens.COLOR_ERROR)
		build_completed.emit(false, "")
		return
	if success:
		progress_bar.value = 100.0
		stage_label.text = GyroLang.t("build_stage_done")
		stage_label.add_theme_color_override("font_color", Color.WHITE)
		_on_log("[color=#22c55e]%s (%.1fs)[/color]" % [GyroLang.t("build_success"), elapsed])
		build_completed.emit(true, output_path)
	else:
		stage_label.text = GyroLang.t("build_failed")
		stage_label.add_theme_color_override("font_color", DesignTokens.COLOR_ERROR)
		if error != "":
			_on_log("[color=#ef4444]%s[/color]" % error)
		_on_log("[color=#6b7280]Time: %.1fs[/color]" % elapsed)
		build_completed.emit(false, "")

func _exit_tree() -> void:
	if _builder != null:
		_builder.cancel()
		_builder.wait_finish()
		if _builder.progress_changed.is_connected(_on_progress):
			_builder.progress_changed.disconnect(_on_progress)
		if _builder.log_added.is_connected(_on_log):
			_builder.log_added.disconnect(_on_log)
		if _builder.build_finished.is_connected(_on_build_done):
			_builder.build_finished.disconnect(_on_build_done)
		_builder = null
