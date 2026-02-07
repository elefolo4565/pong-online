extends Control

@onready var result_label: Label = $CenterContainer/VBoxContainer/ResultLabel
@onready var score_label: Label = $CenterContainer/VBoxContainer/ScoreLabel
@onready var rematch_button: Button = $CenterContainer/VBoxContainer/RematchButton
@onready var menu_button: Button = $CenterContainer/VBoxContainer/MenuButton

func _ready() -> void:
	rematch_button.pressed.connect(_on_rematch_pressed)
	menu_button.pressed.connect(_on_menu_pressed)

	if GameState.is_winner:
		result_label.text = "YOU WIN!"
		result_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	else:
		result_label.text = "YOU LOSE"
		result_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

	score_label.text = "%d  -  %d" % [GameState.score_p1, GameState.score_p2]

func _on_rematch_pressed() -> void:
	GameState.reset()
	if WebSocketClient.is_connected_to_server():
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
	else:
		# 再接続してからロビーへ
		WebSocketClient.connected.connect(func():
			get_tree().change_scene_to_file("res://scenes/lobby.tscn")
		, CONNECT_ONE_SHOT)
		WebSocketClient.connect_to_server()

func _on_menu_pressed() -> void:
	GameState.reset()
	WebSocketClient.close()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
