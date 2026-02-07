extends Control

@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var dots_label: Label = $CenterContainer/VBoxContainer/DotsLabel
@onready var cancel_button: Button = $CenterContainer/VBoxContainer/CancelButton

var _dot_count: int = 0
var _dot_timer: float = 0.0

func _ready() -> void:
	cancel_button.pressed.connect(_on_cancel_pressed)
	WebSocketClient.message_received.connect(_on_message)
	WebSocketClient.disconnected.connect(_on_disconnected)
	status_label.text = "対戦相手を探しています"
	# マッチングキューに参加
	WebSocketClient.send_message({"type": "join_queue"})

func _process(delta: float) -> void:
	# ドットアニメーション
	_dot_timer += delta
	if _dot_timer >= 0.5:
		_dot_timer = 0.0
		_dot_count = (_dot_count + 1) % 4
		dots_label.text = ".".repeat(_dot_count)

func _on_message(data: Dictionary) -> void:
	var msg_type = data.get("type", "")
	match msg_type:
		"match_found":
			GameState.player_number = int(data.get("player_number", 0))
			status_label.text = "対戦相手が見つかりました！"
			dots_label.text = ""
			# 少し待ってからゲーム画面へ
			await get_tree().create_timer(0.5).timeout
			get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_cancel_pressed() -> void:
	WebSocketClient.close()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_disconnected() -> void:
	status_label.text = "サーバーから切断されました"
	dots_label.text = ""
	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _exit_tree() -> void:
	WebSocketClient.message_received.disconnect(_on_message)
	WebSocketClient.disconnected.disconnect(_on_disconnected)
