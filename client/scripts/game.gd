extends Node2D

# フィールド定数
const FIELD_W: float = 1280.0
const FIELD_H: float = 720.0
const PADDLE_W: float = 20.0
const PADDLE_H: float = 120.0
const BALL_SIZE: float = 20.0
const PADDLE_SPEED: float = 500.0
const PADDLE_MARGIN: float = 40.0
const LERP_SPEED: float = 20.0
const BALL_SPEED_INIT: float = 400.0
const BALL_SPEED_MAX: float = 800.0
const BALL_SPEED_INCREASE: float = 1.05
const WIN_SCORE: int = 5

# AI定数
const AI_SPEED: float = 400.0         # AIパドル速度（プレイヤーより少し遅い）
const AI_REACTION_DIST: float = 400.0 # この距離以内でボールが向かってきたら反応
const AI_ERROR: float = 30.0          # AIの狙いのブレ幅

# パワーアップ色
const POWERUP_COLORS = {
	"paddle_grow": Color(0.2, 1.0, 0.2),
	"paddle_shrink": Color(1.0, 0.2, 0.2),
	"ball_speed": Color(1.0, 1.0, 0.2),
	"multi_ball": Color(0.2, 0.6, 1.0),
}

# サーバーからの目標値（補間先、オンラインモード用）
var target_ball_pos: Vector2 = Vector2(FIELD_W / 2, FIELD_H / 2)
var target_paddle1_y: float = FIELD_H / 2
var target_paddle2_y: float = FIELD_H / 2

# ボール速度
var ball_velocity: Vector2 = Vector2.ZERO

# 表示用の現在値
var ball_pos: Vector2 = Vector2(FIELD_W / 2, FIELD_H / 2)
var extra_balls: Array = []
var paddle1_y: float = FIELD_H / 2
var paddle2_y: float = FIELD_H / 2
var paddle1_h: float = PADDLE_H
var paddle2_h: float = PADDLE_H
var score_p1: int = 0
var score_p2: int = 0
var my_paddle_y: float = FIELD_H / 2
var countdown: int = 0
var game_active: bool = false

# AI用
var ai_ball_speed: float = BALL_SPEED_INIT
var ai_target_y: float = FIELD_H / 2

# タッチ操作
var touch_active: bool = false
var touch_target_y: float = FIELD_H / 2

# パワーアップ
var powerups: Array = []
var active_effects: Array = []

# UI参照
@onready var score_label: Label = $UILayer/ScoreLabel
@onready var countdown_label: Label = $UILayer/CountdownLabel
@onready var info_label: Label = $UILayer/InfoLabel

func _ready() -> void:
	if not GameState.ai_mode:
		WebSocketClient.message_received.connect(_on_message)
		WebSocketClient.disconnected.connect(_on_disconnected)
	_update_score_display()
	if GameState.ai_mode:
		info_label.text = "VS AI"
		_start_ai_countdown()
	else:
		info_label.text = "Player %d" % GameState.player_number
	countdown_label.text = ""

func _process(delta: float) -> void:
	if game_active:
		_handle_input(delta)
		if GameState.ai_mode:
			_update_ai_game(delta)
		else:
			# オンライン: クライアント予測
			ball_pos += ball_velocity * delta
			if ball_pos.y - BALL_SIZE / 2 <= 0:
				ball_pos.y = BALL_SIZE / 2
				ball_velocity.y = abs(ball_velocity.y)
			if ball_pos.y + BALL_SIZE / 2 >= FIELD_H:
				ball_pos.y = FIELD_H - BALL_SIZE / 2
				ball_velocity.y = -abs(ball_velocity.y)

	if not GameState.ai_mode:
		# オンライン: 相手パドル補間
		if GameState.player_number == 1:
			paddle2_y = lerpf(paddle2_y, target_paddle2_y, delta * LERP_SPEED)
			paddle1_y = my_paddle_y
		else:
			paddle1_y = lerpf(paddle1_y, target_paddle1_y, delta * LERP_SPEED)
			paddle2_y = my_paddle_y
	else:
		paddle1_y = my_paddle_y

	queue_redraw()

# --- AI カウントダウン ---
func _start_ai_countdown() -> void:
	for i in range(3, 0, -1):
		countdown_label.text = str(i)
		await get_tree().create_timer(1.0).timeout
	countdown_label.text = "GO!"
	game_active = true
	_ai_reset_ball()
	await get_tree().create_timer(0.5).timeout
	countdown_label.text = ""

# --- AI ゲームロジック (ローカル物理) ---
func _ai_reset_ball() -> void:
	ball_pos = Vector2(FIELD_W / 2, FIELD_H / 2)
	ai_ball_speed = BALL_SPEED_INIT
	var angle = (randf() * 0.5 - 0.25) * PI
	var dir = 1.0 if randf() < 0.5 else -1.0
	ball_velocity = Vector2(cos(angle) * ai_ball_speed * dir, sin(angle) * ai_ball_speed)
	ai_target_y = FIELD_H / 2 + randf_range(-AI_ERROR, AI_ERROR)

func _update_ai_game(delta: float) -> void:
	# ボール移動
	ball_pos += ball_velocity * delta

	# 上下壁反射
	if ball_pos.y - BALL_SIZE / 2 <= 0:
		ball_pos.y = BALL_SIZE / 2
		ball_velocity.y = abs(ball_velocity.y)
	if ball_pos.y + BALL_SIZE / 2 >= FIELD_H:
		ball_pos.y = FIELD_H - BALL_SIZE / 2
		ball_velocity.y = -abs(ball_velocity.y)

	# パドル1 (プレイヤー, 左) 衝突
	var p1_right = PADDLE_MARGIN + PADDLE_W / 2
	if (ball_velocity.x < 0 and
		ball_pos.x - BALL_SIZE / 2 <= p1_right and
		ball_pos.x + BALL_SIZE / 2 >= PADDLE_MARGIN - PADDLE_W / 2 and
		ball_pos.y >= paddle1_y - paddle1_h / 2 and
		ball_pos.y <= paddle1_y + paddle1_h / 2):
		ball_pos.x = p1_right + BALL_SIZE / 2
		var rel_y = (ball_pos.y - paddle1_y) / (paddle1_h / 2)
		var angle = rel_y * (PI / 3)
		ai_ball_speed = minf(ai_ball_speed * BALL_SPEED_INCREASE, BALL_SPEED_MAX)
		ball_velocity = Vector2(cos(angle) * ai_ball_speed, sin(angle) * ai_ball_speed)
		ai_target_y = ball_pos.y + randf_range(-AI_ERROR, AI_ERROR)

	# パドル2 (AI, 右) 衝突
	var p2_left = FIELD_W - PADDLE_MARGIN - PADDLE_W / 2
	if (ball_velocity.x > 0 and
		ball_pos.x + BALL_SIZE / 2 >= p2_left and
		ball_pos.x - BALL_SIZE / 2 <= FIELD_W - PADDLE_MARGIN + PADDLE_W / 2 and
		ball_pos.y >= paddle2_y - paddle2_h / 2 and
		ball_pos.y <= paddle2_y + paddle2_h / 2):
		ball_pos.x = p2_left - BALL_SIZE / 2
		var rel_y = (ball_pos.y - paddle2_y) / (paddle2_h / 2)
		var angle = rel_y * (PI / 3)
		ai_ball_speed = minf(ai_ball_speed * BALL_SPEED_INCREASE, BALL_SPEED_MAX)
		ball_velocity = Vector2(-cos(angle) * ai_ball_speed, sin(angle) * ai_ball_speed)
		ai_target_y = ball_pos.y + randf_range(-AI_ERROR, AI_ERROR)

	# AI パドル制御
	_update_ai_paddle(delta)

	# 得点判定
	if ball_pos.x < -BALL_SIZE:
		score_p2 += 1
		_update_score_display()
		_check_ai_win()
		if game_active:
			_ai_reset_ball()
	elif ball_pos.x > FIELD_W + BALL_SIZE:
		score_p1 += 1
		_update_score_display()
		_check_ai_win()
		if game_active:
			_ai_reset_ball()

func _update_ai_paddle(delta: float) -> void:
	# ボールが右に向かっている場合はボールを追う
	if ball_velocity.x > 0 and ball_pos.x > FIELD_W - AI_REACTION_DIST:
		var target = ai_target_y
		var diff = target - paddle2_y
		if abs(diff) > 5.0:
			paddle2_y += sign(diff) * minf(AI_SPEED * delta, abs(diff))
	else:
		# ボールが離れているときは中央に戻る
		var diff = FIELD_H / 2 - paddle2_y
		if abs(diff) > 10.0:
			paddle2_y += sign(diff) * minf(AI_SPEED * 0.5 * delta, abs(diff))
	paddle2_y = clampf(paddle2_y, paddle2_h / 2, FIELD_H - paddle2_h / 2)

func _check_ai_win() -> void:
	if score_p1 >= WIN_SCORE:
		game_active = false
		GameState.winner = 1
		GameState.is_winner = true
		GameState.score_p1 = score_p1
		GameState.score_p2 = score_p2
		countdown_label.text = "GAME!"
		await get_tree().create_timer(1.5).timeout
		get_tree().change_scene_to_file("res://scenes/result.tscn")
	elif score_p2 >= WIN_SCORE:
		game_active = false
		GameState.winner = 2
		GameState.is_winner = false
		GameState.score_p1 = score_p1
		GameState.score_p2 = score_p2
		countdown_label.text = "GAME!"
		await get_tree().create_timer(1.5).timeout
		get_tree().change_scene_to_file("res://scenes/result.tscn")

# --- タッチ入力 ---
func _input(event: InputEvent) -> void:
	if not game_active:
		return
	if event is InputEventScreenTouch:
		touch_active = event.pressed
		if touch_active:
			touch_target_y = event.position.y
	elif event is InputEventScreenDrag:
		touch_active = true
		touch_target_y = event.position.y
	elif event is InputEventMouseButton:
		touch_active = event.pressed
		if touch_active:
			touch_target_y = event.position.y
	elif event is InputEventMouseMotion and touch_active:
		touch_target_y = event.position.y

func _handle_input(delta: float) -> void:
	var my_h = paddle1_h if GameState.player_number == 1 else paddle2_h
	var moved = false

	var direction = 0.0
	if Input.is_action_pressed("move_up"):
		direction -= 1.0
	if Input.is_action_pressed("move_down"):
		direction += 1.0

	if direction != 0.0:
		my_paddle_y += direction * PADDLE_SPEED * delta
		moved = true

	if touch_active:
		var diff = touch_target_y - my_paddle_y
		if abs(diff) > 5.0:
			my_paddle_y += sign(diff) * minf(PADDLE_SPEED * delta, abs(diff))
			moved = true

	if moved:
		my_paddle_y = clampf(my_paddle_y, my_h / 2, FIELD_H - my_h / 2)
		if not GameState.ai_mode:
			WebSocketClient.send_message({"type": "paddle_move", "y": my_paddle_y})

# --- オンラインモードのメッセージ処理 ---
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
	target_ball_pos.x = float(ball.get("x", target_ball_pos.x))
	target_ball_pos.y = float(ball.get("y", target_ball_pos.y))
	ball_velocity.x = float(ball.get("vx", 0))
	ball_velocity.y = float(ball.get("vy", 0))
	var diff = ball_pos.distance_to(target_ball_pos)
	if diff > 50.0:
		ball_pos = target_ball_pos
	else:
		ball_pos = ball_pos.lerp(target_ball_pos, 0.5)

	var eb = data.get("extra_balls", [])
	extra_balls.clear()
	for b in eb:
		extra_balls.append(Vector2(float(b.get("x", 0)), float(b.get("y", 0))))

	var paddles = data.get("paddles", {})
	target_paddle1_y = float(paddles.get("p1_y", target_paddle1_y))
	target_paddle2_y = float(paddles.get("p2_y", target_paddle2_y))
	paddle1_h = float(paddles.get("p1_h", PADDLE_H))
	paddle2_h = float(paddles.get("p2_h", PADDLE_H))

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

# --- 共通描画 ---
func _update_score_display() -> void:
	score_label.text = "%d  -  %d" % [score_p1, score_p2]

func _draw() -> void:
	draw_rect(Rect2(0, 0, FIELD_W, FIELD_H), Color(0.05, 0.05, 0.12))

	var dash_length = 15.0
	var gap = 10.0
	var y = 0.0
	while y < FIELD_H:
		draw_rect(Rect2(FIELD_W / 2 - 2, y, 4, dash_length), Color(0.3, 0.3, 0.4))
		y += dash_length + gap

	var p1_color = Color(0.2, 1.0, 0.5)
	draw_rect(Rect2(PADDLE_MARGIN - PADDLE_W / 2, paddle1_y - paddle1_h / 2, PADDLE_W, paddle1_h), p1_color)

	var p2_color = Color(1.0, 0.4, 0.3) if GameState.ai_mode else Color(0.8, 0.8, 0.9)
	draw_rect(Rect2(FIELD_W - PADDLE_MARGIN - PADDLE_W / 2, paddle2_y - paddle2_h / 2, PADDLE_W, paddle2_h), p2_color)

	draw_rect(Rect2(ball_pos.x - BALL_SIZE / 2, ball_pos.y - BALL_SIZE / 2, BALL_SIZE, BALL_SIZE), Color.WHITE)

	for eb in extra_balls:
		draw_rect(Rect2(eb.x - BALL_SIZE / 2, eb.y - BALL_SIZE / 2, BALL_SIZE, BALL_SIZE), Color(0.7, 0.7, 1.0))

	for p in powerups:
		var ptype = p.get("type", "")
		var color = POWERUP_COLORS.get(ptype, Color.WHITE)
		var px = float(p.get("x", 0))
		var py = float(p.get("y", 0))
		var points = PackedVector2Array([
			Vector2(px, py - 15), Vector2(px + 15, py),
			Vector2(px, py + 15), Vector2(px - 15, py),
		])
		draw_colored_polygon(points, color)

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
		var bar_width = remaining / 5.0 * 100.0
		draw_rect(Rect2(FIELD_W / 2 - 50, y_offset, bar_width, 8), color)
		y_offset += 15.0

func _on_disconnected() -> void:
	game_active = false
	countdown_label.text = "接続が切断されました"
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _exit_tree() -> void:
	if not GameState.ai_mode:
		if WebSocketClient.message_received.is_connected(_on_message):
			WebSocketClient.message_received.disconnect(_on_message)
		if WebSocketClient.disconnected.is_connected(_on_disconnected):
			WebSocketClient.disconnected.disconnect(_on_disconnected)
