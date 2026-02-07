extends Control

@onready var play_button: Button = $CenterContainer/VBoxContainer/PlayButton
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	status_label.text = ""

func _on_play_pressed() -> void:
	play_button.disabled = true
	status_label.text = "サーバーに接続中..."
	WebSocketClient.connected.connect(_on_connected, CONNECT_ONE_SHOT)
	WebSocketClient.disconnected.connect(_on_connection_failed, CONNECT_ONE_SHOT)
	WebSocketClient.connect_to_server()

func _on_connected() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_connection_failed() -> void:
	status_label.text = "接続に失敗しました。再試行してください。"
	play_button.disabled = false
