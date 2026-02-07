extends Control

@onready var play_button: Button = $CenterContainer/VBoxContainer/PlayButton
@onready var ai_button: Button = $CenterContainer/VBoxContainer/AIButton
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var room_status_label: Label = $CenterContainer/VBoxContainer/RoomStatusLabel

var _http_request: HTTPRequest
var _poll_timer: float = 0.0
const POLL_INTERVAL: float = 3.0
const STATUS_URL: String = "https://pong-online-4xcn.onrender.com/status"

var _room_count: int = -1
var _max_rooms: int = 10
var _is_full: bool = false

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	ai_button.pressed.connect(_on_ai_pressed)
	status_label.text = ""
	room_status_label.text = "ルーム情報取得中..."

	# HTTPリクエスト用ノードを作成
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_status_response)

	# 初回リクエスト
	_request_status()

func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer >= POLL_INTERVAL:
		_poll_timer = 0.0
		_request_status()

func _request_status() -> void:
	if _http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED and \
	   _http_request.get_http_client_status() != HTTPClient.STATUS_CONNECTED:
		return
	_http_request.request(STATUS_URL)

func _on_status_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		room_status_label.text = "サーバー接続待機中..."
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		return

	var data = json.get_data()
	if data is Dictionary:
		_room_count = int(data.get("rooms", 0))
		_max_rooms = int(data.get("max_rooms", 10))
		_is_full = _room_count >= _max_rooms
		_update_room_display()

func _update_room_display() -> void:
	if _is_full:
		room_status_label.text = "ルーム上限に達しています (%d/%d)" % [_room_count, _max_rooms]
		room_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3, 1))
		play_button.disabled = true
	else:
		room_status_label.text = "ルーム: %d/%d" % [_room_count, _max_rooms]
		room_status_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6, 1))
		# 接続中でなければボタンを有効化
		if status_label.text == "" or status_label.text == "接続に失敗しました。再試行してください。":
			play_button.disabled = false

func _on_play_pressed() -> void:
	play_button.disabled = true
	ai_button.disabled = true
	status_label.text = "サーバーに接続中..."
	WebSocketClient.connected.connect(_on_connected, CONNECT_ONE_SHOT)
	WebSocketClient.disconnected.connect(_on_connection_failed, CONNECT_ONE_SHOT)
	WebSocketClient.connect_to_server()

func _on_ai_pressed() -> void:
	GameState.ai_mode = true
	GameState.player_number = 1
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_connected() -> void:
	GameState.ai_mode = false
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_connection_failed() -> void:
	status_label.text = "接続に失敗しました。再試行してください。"
	play_button.disabled = _is_full
	ai_button.disabled = false
