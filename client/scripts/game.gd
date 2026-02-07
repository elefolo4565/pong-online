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
const AI_SPEED: float = 450.0         # AIパドル速度（プレイヤーより少し遅い）
const AI_ERROR: float = 25.0          # AIの狙いのブレ幅
const AI_UPDATE_INTERVAL: float = 0.3 # AIの目標更新間隔（秒）

# パワーアップ定数
const POWERUP_TYPES: Array[String] = ["paddle_grow", "paddle_shrink", "ball_speed", "multi_ball"]
const POWERUP_SPAWN_MIN: float = 5.0
const POWERUP_SPAWN_MAX: float = 10.0
const POWERUP_RADIUS: float = 15.0
const POWERUP_DURATION: float = 5.0

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
var ai_update_timer: float = 0.0
var ai_next_powerup_time: float = 0.0
var ai_powerup_id: int = 0
var ai_ball_speed_multiplier: float = 1.0

# タッチ操作
var touch_active: bool = false
var touch_target_y: float = FIELD_H / 2

# ボール残像
const TRAIL_LENGTH: int = 12
const TRAIL_INTERVAL: float = 0.012  # 残像記録間隔（秒）
var ball_trail: Array[Vector2] = []
var trail_timer: float = 0.0

# パワーアップ
var powerups: Array = []
var active_effects: Array = []

# 効果音
var sfx_hit: AudioStreamPlayer
var sfx_wall: AudioStreamPlayer
var sfx_score: AudioStreamPlayer

# UI参照
@onready var score_label: Label = $UILayer/ScoreLabel
@onready var countdown_label: Label = $UILayer/CountdownLabel
@onready var info_label: Label = $UILayer/InfoLabel

func _ready() -> void:
	# 効果音セットアップ
	var ball_sound = load("res://assets/ball.mp3")
	sfx_hit = AudioStreamPlayer.new()
	sfx_hit.stream = ball_sound
	sfx_hit.volume_db = 0.0
	add_child(sfx_hit)
	sfx_wall = AudioStreamPlayer.new()
	sfx_wall.stream = ball_sound
	sfx_wall.volume_db = -4.0
	sfx_wall.pitch_scale = 0.7
	add_child(sfx_wall)
	sfx_score = AudioStreamPlayer.new()
	sfx_score.stream = ball_sound
	sfx_score.volume_db = 2.0
	sfx_score.pitch_scale = 0.5
	add_child(sfx_score)

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
				sfx_wall.play()
			if ball_pos.y + BALL_SIZE / 2 >= FIELD_H:
				ball_pos.y = FIELD_H - BALL_SIZE / 2
				ball_velocity.y = -abs(ball_velocity.y)
				sfx_wall.play()

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

	# ボール残像を記録
	if game_active:
		trail_timer += delta
		if trail_timer >= TRAIL_INTERVAL:
			trail_timer = 0.0
			ball_trail.append(ball_pos)
			if ball_trail.size() > TRAIL_LENGTH:
				ball_trail.remove_at(0)

	queue_redraw()

# --- AI カウントダウン ---
func _start_ai_countdown() -> void:
	for i in range(3, 0, -1):
		countdown_label.text = str(i)
		await get_tree().create_timer(1.0).timeout
	countdown_label.text = "GO!"
	game_active = true
	ai_next_powerup_time = randf_range(POWERUP_SPAWN_MIN, POWERUP_SPAWN_MAX)
	_ai_reset_ball()
	await get_tree().create_timer(0.5).timeout
	countdown_label.text = ""

# --- AI ゲームロジック (ローカル物理) ---
func _ai_reset_ball() -> void:
	ball_pos = Vector2(FIELD_W / 2, FIELD_H / 2)
	ball_trail.clear()
	extra_balls.clear()
	ai_ball_speed = BALL_SPEED_INIT
	ai_ball_speed_multiplier = 1.0
	# ボール加速エフェクトをクリア
	active_effects = active_effects.filter(func(e): return e.get("type", "") != "ball_speed")
	var angle = (randf() * 0.5 - 0.25) * PI
	var dir = 1.0 if randf() < 0.5 else -1.0
	ball_velocity = Vector2(cos(angle) * ai_ball_speed * dir, sin(angle) * ai_ball_speed)
	ai_target_y = FIELD_H / 2
	ai_update_timer = 0.0

func _update_ai_game(delta: float) -> void:
	# ボール移動
	ball_pos += ball_velocity * delta

	# 上下壁反射
	if ball_pos.y - BALL_SIZE / 2 <= 0:
		ball_pos.y = BALL_SIZE / 2
		ball_velocity.y = abs(ball_velocity.y)
		sfx_wall.play()
	if ball_pos.y + BALL_SIZE / 2 >= FIELD_H:
		ball_pos.y = FIELD_H - BALL_SIZE / 2
		ball_velocity.y = -abs(ball_velocity.y)
		sfx_wall.play()

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
		var effective_speed = ai_ball_speed * ai_ball_speed_multiplier
		ball_velocity = Vector2(cos(angle) * effective_speed, sin(angle) * effective_speed)
		ai_update_timer = 0.0
		sfx_hit.play()

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
		var effective_speed = ai_ball_speed * ai_ball_speed_multiplier
		ball_velocity = Vector2(-cos(angle) * effective_speed, sin(angle) * effective_speed)
		ai_update_timer = 0.0
		sfx_hit.play()

	# パワーアップ生成・衝突・エフェクト
	_ai_update_powerups(delta)
	_ai_check_powerup_collision(ball_pos)
	_ai_update_effects(delta)

	# マルチボール更新
	for i in range(extra_balls.size() - 1, -1, -1):
		var eb = extra_balls[i]
		eb.x += eb.vx * delta
		eb.y += eb.vy * delta
		if eb.y - BALL_SIZE / 2 <= 0:
			eb.y = BALL_SIZE / 2
			eb.vy = abs(eb.vy)
		if eb.y + BALL_SIZE / 2 >= FIELD_H:
			eb.y = FIELD_H - BALL_SIZE / 2
			eb.vy = -abs(eb.vy)
		# パドル衝突(簡易)
		if eb.vx < 0 and eb.x - BALL_SIZE / 2 <= p1_right and eb.x > 0 and \
			eb.y >= paddle1_y - paddle1_h / 2 and eb.y <= paddle1_y + paddle1_h / 2:
			eb.x = p1_right + BALL_SIZE / 2
			eb.vx = abs(eb.vx)
		if eb.vx > 0 and eb.x + BALL_SIZE / 2 >= p2_left and eb.x < FIELD_W and \
			eb.y >= paddle2_y - paddle2_h / 2 and eb.y <= paddle2_y + paddle2_h / 2:
			eb.x = p2_left - BALL_SIZE / 2
			eb.vx = -abs(eb.vx)
		_ai_check_powerup_collision(Vector2(eb.x, eb.y))
		if eb.x < -BALL_SIZE or eb.x > FIELD_W + BALL_SIZE:
			extra_balls.remove_at(i)

	# AI パドル制御
	_update_ai_paddle(delta)

	# 得点判定
	if ball_pos.x < -BALL_SIZE:
		score_p2 += 1
		_update_score_display()
		sfx_score.play()
		_check_ai_win()
		if game_active:
			_ai_reset_ball()
	elif ball_pos.x > FIELD_W + BALL_SIZE:
		score_p1 += 1
		_update_score_display()
		sfx_score.play()
		_check_ai_win()
		if game_active:
			_ai_reset_ball()

func _update_ai_paddle(delta: float) -> void:
	# 定期的にAIの目標位置を更新
	ai_update_timer -= delta
	if ai_update_timer <= 0:
		ai_update_timer = AI_UPDATE_INTERVAL
		if ball_velocity.x > 0:
			# ボールが右に向かっている → 到達Y位置を予測
			ai_target_y = _predict_ball_y() + randf_range(-AI_ERROR, AI_ERROR)
		else:
			# ボールが左に向かっている → 中央寄りに待機
			ai_target_y = FIELD_H / 2 + randf_range(-50, 50)

	# 目標位置に向かって移動
	var diff = ai_target_y - paddle2_y
	if abs(diff) > 5.0:
		paddle2_y += sign(diff) * minf(AI_SPEED * delta, abs(diff))
	paddle2_y = clampf(paddle2_y, paddle2_h / 2, FIELD_H - paddle2_h / 2)

func _predict_ball_y() -> float:
	# ボールがAIパドルのx位置に到達する時のy座標を予測（壁反射考慮）
	var target_x = FIELD_W - PADDLE_MARGIN
	if ball_velocity.x <= 0:
		return FIELD_H / 2

	var time_to_arrive = (target_x - ball_pos.x) / ball_velocity.x
	var predicted_y = ball_pos.y + ball_velocity.y * time_to_arrive

	# 壁反射をシミュレーション（上下に跳ね返る）
	while predicted_y < 0 or predicted_y > FIELD_H:
		if predicted_y < 0:
			predicted_y = -predicted_y
		if predicted_y > FIELD_H:
			predicted_y = 2.0 * FIELD_H - predicted_y
	return predicted_y

# --- AI パワーアップ処理 ---
func _ai_update_powerups(_delta: float) -> void:
	if powerups.size() >= 1:
		return
	ai_next_powerup_time -= _delta
	if ai_next_powerup_time <= 0:
		ai_next_powerup_time = randf_range(POWERUP_SPAWN_MIN, POWERUP_SPAWN_MAX)
		ai_powerup_id += 1
		var ptype = POWERUP_TYPES[randi() % POWERUP_TYPES.size()]
		var px = FIELD_W / 4 + randf() * (FIELD_W / 2)
		var py = 60.0 + randf() * (FIELD_H - 120.0)
		powerups.append({"id": ai_powerup_id, "x": px, "y": py, "type": ptype})

func _ai_check_powerup_collision(bpos: Vector2) -> void:
	for i in range(powerups.size() - 1, -1, -1):
		var p = powerups[i]
		var dx = bpos.x - float(p.get("x", 0))
		var dy = bpos.y - float(p.get("y", 0))
		if sqrt(dx * dx + dy * dy) < POWERUP_RADIUS + BALL_SIZE / 2:
			# ボールの進行方向で取得プレイヤーを判定 (1=プレイヤー, 2=AI)
			var target_player = 1 if ball_velocity.x > 0 else 2
			_ai_apply_powerup(p.get("type", ""), target_player)
			powerups.remove_at(i)

func _ai_apply_powerup(ptype: String, target_player: int) -> void:
	var opponent = 2 if target_player == 1 else 1
	match ptype:
		"paddle_grow":
			if target_player == 1:
				paddle1_h = PADDLE_H * 1.5
			else:
				paddle2_h = PADDLE_H * 1.5
			active_effects.append({"type": "paddle_grow", "target_player": target_player, "remaining": POWERUP_DURATION})
		"paddle_shrink":
			if opponent == 1:
				paddle1_h = PADDLE_H * 0.5
			else:
				paddle2_h = PADDLE_H * 0.5
			active_effects.append({"type": "paddle_shrink", "target_player": opponent, "remaining": POWERUP_DURATION})
		"ball_speed":
			ai_ball_speed_multiplier = 1.5
			active_effects.append({"type": "ball_speed", "target_player": 0, "remaining": 99.0})
		"multi_ball":
			extra_balls.append({"x": ball_pos.x, "y": ball_pos.y, "vx": ball_velocity.x * -0.8, "vy": -ball_velocity.y * 1.2})

func _ai_update_effects(delta: float) -> void:
	for i in range(active_effects.size() - 1, -1, -1):
		var e = active_effects[i]
		e["remaining"] = float(e.get("remaining", 0)) - delta
		if float(e.get("remaining", 0)) <= 0:
			var etype = e.get("type", "")
			var tp = int(e.get("target_player", 0))
			match etype:
				"paddle_grow":
					if tp == 1:
						paddle1_h = PADDLE_H
					else:
						paddle2_h = PADDLE_H
				"paddle_shrink":
					if tp == 1:
						paddle1_h = PADDLE_H
					else:
						paddle2_h = PADDLE_H
				"ball_speed":
					ai_ball_speed_multiplier = 1.0
			active_effects.remove_at(i)

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
			sfx_score.play()
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
	var prev_vx = ball_velocity.x
	ball_velocity.x = float(ball.get("vx", 0))
	ball_velocity.y = float(ball.get("vy", 0))
	# パドル反射検出（vxの符号が変わった）
	if prev_vx != 0 and sign(prev_vx) != sign(ball_velocity.x):
		sfx_hit.play()
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

	# ボール残像
	for i in range(ball_trail.size()):
		var t = float(i) / float(TRAIL_LENGTH)
		var alpha = t * 0.4
		var size = BALL_SIZE * (0.3 + t * 0.7)
		var trail_color = Color(0.4, 0.7, 1.0, alpha)
		var tp = ball_trail[i]
		draw_rect(Rect2(tp.x - size / 2, tp.y - size / 2, size, size), trail_color)

	# メインボール
	draw_rect(Rect2(ball_pos.x - BALL_SIZE / 2, ball_pos.y - BALL_SIZE / 2, BALL_SIZE, BALL_SIZE), Color.WHITE)

	for eb in extra_balls:
		var ebx: float
		var eby: float
		if eb is Vector2:
			ebx = eb.x
			eby = eb.y
		else:
			ebx = float(eb.get("x", 0))
			eby = float(eb.get("y", 0))
		draw_rect(Rect2(ebx - BALL_SIZE / 2, eby - BALL_SIZE / 2, BALL_SIZE, BALL_SIZE), Color(0.7, 0.7, 1.0))

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
