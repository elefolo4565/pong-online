extends Node2D

# フィールド定数
const FIELD_W: float = 1280.0
const FIELD_H: float = 720.0
const PADDLE_W: float = 20.0
const PADDLE_H: float = 120.0
const BALL_SIZE: float = 20.0
const PADDLE_SPEED: float = 500.0
const PADDLE_MARGIN: float = 40.0

# パワーアップ色
const POWERUP_COLORS = {
	"paddle_grow": Color(0.2, 1.0, 0.2),     # 緑
	"paddle_shrink": Color(1.0, 0.2, 0.2),   # 赤
	"ball_speed": Color(1.0, 1.0, 0.2),      # 黄
	"multi_ball": Color(0.2, 0.6, 1.0),      # 青
}

# ゲーム状態
var ball_pos: Vector2 = Vector2(FIELD_W / 2, FIELD_H / 2)
var extra_balls: Array = []  # マルチボール用
var paddle1_y: float = FIELD_H / 2
var paddle2_y: float = FIELD_H / 2
var paddle1_h: float = PADDLE_H
var paddle2_h: float = PADDLE_H
var score_p1: int = 0
var score_p2: int = 0
var my_paddle_y: float = FIELD_H / 2
var countdown: int = 0
var game_active: bool = false

# パワーアップ
var powerups: Array = []  # [{id, x, y, type}, ...]
var active_effects: Array = []  # [{type, target_player, remaining}, ...]

# UI参照
@onready var score_label: Label = $UILayer/ScoreLabel
@onready var countdown_label: Label = $UILayer/CountdownLabel
@onready var info_label: Label = $UILayer/InfoLabel

func _ready() -> void:
	WebSocketClient.message_received.connect(_on_message)
	WebSocketClient.disconnected.connect(_on_disconnected)
	_update_score_display()
	info_label.text = "Player %d" % GameState.player_number
	countdown_label.text = ""

func _process(delta: float) -> void:
	if game_active:
		_handle_input(delta)
	queue_redraw()

func _handle_input(delta: float) -> void:
	var direction = 0.0
	if Input.is_action_pressed("move_up"):
		direction -= 1.0
	if Input.is_action_pressed("move_down"):
		direction += 1.0

	if direction != 0.0:
		my_paddle_y += direction * PADDLE_SPEED * delta
		# パドルの高さに応じてクランプ
		var my_h = paddle1_h if GameState.player_number == 1 else paddle2_h
		my_paddle_y = clampf(my_paddle_y, my_h / 2, FIELD_H - my_h / 2)
		WebSocketClient.send_message({"type": "paddle_move", "y": my_paddle_y})

func _on_message(data: Dictionary) -> void:
	var msg_type = data.get("type", "")
	match msg_type:
		"countdown":
			countdown = int(data.get("count", 0))
			countdown_label.text = str(countdown)
			if countdown == 0:
				countdown_label.text = "GO!"
				game_active = true
				await get_tree().create_timer(0.5).timeout
				countdown_label.text = ""
		"game_state":
			_apply_game_state(data)
		"powerup_spawn":
			powerups.append({
				"id": data.get("id", ""),
				"x": float(data.get("x", 0)),
				"y": float(data.get("y", 0)),
				"type": data.get("ptype", ""),
			})
		"powerup_collected":
			var pid = data.get("id", "")
			powerups = powerups.filter(func(p): return p.id != pid)
		"score":
			score_p1 = int(data.get("p1", 0))
			score_p2 = int(data.get("p2", 0))
			_update_score_display()
		"game_over":
			game_active = false
			var winner = int(data.get("winner", 0))
			GameState.winner = winner
			GameState.is_winner = (winner == GameState.player_number)
			GameState.score_p1 = score_p1
			GameState.score_p2 = score_p2
			countdown_label.text = "GAME!"
			await get_tree().create_timer(1.5).timeout
			get_tree().change_scene_to_file("res://scenes/result.tscn")
		"opponent_disconnected":
			game_active = false
			countdown_label.text = "相手が切断しました"
			await get_tree().create_timer(2.0).timeout
			WebSocketClient.close()
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _apply_game_state(data: Dictionary) -> void:
	var ball = data.get("ball", {})
	ball_pos.x = float(ball.get("x", ball_pos.x))
	ball_pos.y = float(ball.get("y", ball_pos.y))

	# マルチボール
	var eb = data.get("extra_balls", [])
	extra_balls.clear()
	for b in eb:
		extra_balls.append(Vector2(float(b.get("x", 0)), float(b.get("y", 0))))

	var paddles = data.get("paddles", {})
	paddle1_y = float(paddles.get("p1_y", paddle1_y))
	paddle2_y = float(paddles.get("p2_y", paddle2_y))
	paddle1_h = float(paddles.get("p1_h", PADDLE_H))
	paddle2_h = float(paddles.get("p2_h", PADDLE_H))

	# パワーアップ同期
	var pups = data.get("powerups", [])
	powerups.clear()
	for p in pups:
		powerups.append({
			"id": p.get("id", ""),
			"x": float(p.get("x", 0)),
			"y": float(p.get("y", 0)),
			"type": p.get("ptype", ""),
		})

	var effects = data.get("effects", [])
	active_effects = effects

	# 自分のパドルは入力値を使うが、反映結果も参照
	if GameState.player_number == 1:
		my_paddle_y = paddle1_y
	else:
		my_paddle_y = paddle2_y

func _update_score_display() -> void:
	score_label.text = "%d  -  %d" % [score_p1, score_p2]

func _draw() -> void:
	# 背景
	draw_rect(Rect2(0, 0, FIELD_W, FIELD_H), Color(0.05, 0.05, 0.12))

	# 中央線
	var dash_length = 15.0
	var gap = 10.0
	var y = 0.0
	while y < FIELD_H:
		draw_rect(Rect2(FIELD_W / 2 - 2, y, 4, dash_length), Color(0.3, 0.3, 0.4))
		y += dash_length + gap

	# パドル1 (左)
	var p1_color = Color(0.2, 1.0, 0.5) if GameState.player_number == 1 else Color(0.8, 0.8, 0.9)
	draw_rect(Rect2(PADDLE_MARGIN - PADDLE_W / 2, paddle1_y - paddle1_h / 2, PADDLE_W, paddle1_h), p1_color)

	# パドル2 (右)
	var p2_color = Color(0.2, 1.0, 0.5) if GameState.player_number == 2 else Color(0.8, 0.8, 0.9)
	draw_rect(Rect2(FIELD_W - PADDLE_MARGIN - PADDLE_W / 2, paddle2_y - paddle2_h / 2, PADDLE_W, paddle2_h), p2_color)

	# ボール
	draw_rect(Rect2(ball_pos.x - BALL_SIZE / 2, ball_pos.y - BALL_SIZE / 2, BALL_SIZE, BALL_SIZE), Color.WHITE)

	# マルチボール
	for eb in extra_balls:
		draw_rect(Rect2(eb.x - BALL_SIZE / 2, eb.y - BALL_SIZE / 2, BALL_SIZE, BALL_SIZE), Color(0.7, 0.7, 1.0))

	# パワーアップアイテム
	for p in powerups:
		var ptype = p.get("type", "")
		var color = POWERUP_COLORS.get(ptype, Color.WHITE)
		var px = float(p.get("x", 0))
		var py = float(p.get("y", 0))
		# ダイヤモンド型で描画
		var points = PackedVector2Array([
			Vector2(px, py - 15),
			Vector2(px + 15, py),
			Vector2(px, py + 15),
			Vector2(px - 15, py),
		])
		draw_colored_polygon(points, color)

	# アクティブエフェクトの表示
	_draw_effects()

func _draw_effects() -> void:
	var y_offset = 50.0
	for effect in active_effects:
		var etype = effect.get("type", "")
		var target = int(effect.get("target_player", 0))
		var remaining = float(effect.get("remaining", 0))
		if remaining <= 0:
			continue
		var color = POWERUP_COLORS.get(etype, Color.WHITE)
		var label = ""
		match etype:
			"paddle_grow":
				label = "PADDLE+" if target == GameState.player_number else "敵PADDLE+"
			"paddle_shrink":
				label = "PADDLE-" if target == GameState.player_number else "敵PADDLE-"
			"ball_speed":
				label = "SPEED UP"
			"multi_ball":
				label = "MULTI BALL"
		if label != "":
			# 効果バーを画面上部に表示
			var bar_width = remaining / 5.0 * 100.0
			draw_rect(Rect2(FIELD_W / 2 - 50, y_offset, bar_width, 8), color)
			y_offset += 15.0

func _on_disconnected() -> void:
	game_active = false
	countdown_label.text = "接続が切断されました"
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _exit_tree() -> void:
	if WebSocketClient.message_received.is_connected(_on_message):
		WebSocketClient.message_received.disconnect(_on_message)
	if WebSocketClient.disconnected.is_connected(_on_disconnected):
		WebSocketClient.disconnected.disconnect(_on_disconnected)
