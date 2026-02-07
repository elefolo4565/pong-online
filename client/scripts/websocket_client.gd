extends Node

signal connected
signal disconnected
signal message_received(data: Dictionary)

var _socket: WebSocketPeer = WebSocketPeer.new()
var _connected: bool = false

# サーバーURL（ローカル開発時はws://、本番はwss://）
var server_url: String = "ws://localhost:8080"

func connect_to_server() -> void:
	var err = _socket.connect_to_url(server_url)
	if err != OK:
		push_error("WebSocket接続エラー: %s" % err)
		return
	print("WebSocket: 接続中... %s" % server_url)

func send_message(data: Dictionary) -> void:
	if _connected:
		var json_str = JSON.stringify(data)
		_socket.send_text(json_str)

func close() -> void:
	if _connected:
		_socket.close()
		_connected = false

func _process(_delta: float) -> void:
	_socket.poll()
	var state = _socket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				print("WebSocket: 接続完了")
				connected.emit()
			while _socket.get_available_packet_count() > 0:
				var packet = _socket.get_packet()
				var text = packet.get_string_from_utf8()
				var json = JSON.new()
				var parse_result = json.parse(text)
				if parse_result == OK:
					var data = json.get_data()
					if data is Dictionary:
						message_received.emit(data)
				else:
					push_warning("WebSocket: JSONパースエラー: %s" % text)
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			if _connected:
				_connected = false
				var code = _socket.get_close_code()
				print("WebSocket: 切断 (code: %s)" % code)
				disconnected.emit()

func is_connected_to_server() -> bool:
	return _connected
