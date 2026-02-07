extends Node

# プレイヤー情報
var player_number: int = 0  # 1 or 2
var is_in_game: bool = false
var ai_mode: bool = false

# スコア
var score_p1: int = 0
var score_p2: int = 0

# 結果
var winner: int = 0  # 0=未決, 1=P1勝利, 2=P2勝利
var is_winner: bool = false

func reset() -> void:
	player_number = 0
	is_in_game = false
	ai_mode = false
	score_p1 = 0
	score_p2 = 0
	winner = 0
	is_winner = false
