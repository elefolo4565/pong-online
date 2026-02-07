const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8080;

// ゲーム定数
const FIELD_W = 1280;
const FIELD_H = 720;
const PADDLE_W = 20;
const PADDLE_H = 120;
const PADDLE_MARGIN = 40;
const BALL_SIZE = 20;
const BALL_SPEED_INIT = 400;
const BALL_SPEED_MAX = 800;
const BALL_SPEED_INCREASE = 1.05;
const WIN_SCORE = 5;
const TICK_RATE = 60;
const TICK_MS = 1000 / TICK_RATE;

// パワーアップ定数
const POWERUP_TYPES = ['paddle_grow', 'paddle_shrink', 'ball_speed', 'multi_ball'];
const POWERUP_SPAWN_MIN = 5000; // ms
const POWERUP_SPAWN_MAX = 10000;
const POWERUP_RADIUS = 15;
const POWERUP_DURATION = 5.0; // 秒

// --- サーバー起動 ---
const wss = new WebSocketServer({ port: PORT });
console.log(`Pong Server started on port ${PORT}`);

// マッチングキュー
let matchQueue = [];
// アクティブルーム
let rooms = new Map();
let roomIdCounter = 0;

wss.on('connection', (ws) => {
  ws.isAlive = true;
  ws.roomId = null;
  ws.playerNumber = 0;

  ws.on('message', (raw) => {
    try {
      const data = JSON.parse(raw.toString());
      handleMessage(ws, data);
    } catch (e) {
      console.error('JSON parse error:', e.message);
    }
  });

  ws.on('close', () => {
    handleDisconnect(ws);
  });

  ws.on('pong', () => {
    ws.isAlive = true;
  });
});

// ヘルスチェック (30秒間隔)
const pingInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) {
      ws.terminate();
      return;
    }
    ws.isAlive = false;
    ws.ping();
  });
}, 30000);

wss.on('close', () => {
  clearInterval(pingInterval);
});

// --- メッセージハンドリング ---
function handleMessage(ws, data) {
  switch (data.type) {
    case 'join_queue':
      joinQueue(ws);
      break;
    case 'paddle_move':
      handlePaddleMove(ws, data);
      break;
  }
}

function joinQueue(ws) {
  // 既にキューにいる場合は無視
  if (matchQueue.includes(ws)) return;
  // 既にルームにいる場合は無視
  if (ws.roomId !== null) return;

  matchQueue.push(ws);
  console.log(`Player queued. Queue size: ${matchQueue.length}`);

  // 2人揃ったらマッチング
  if (matchQueue.length >= 2) {
    const p1 = matchQueue.shift();
    const p2 = matchQueue.shift();
    createRoom(p1, p2);
  }
}

function handlePaddleMove(ws, data) {
  const room = rooms.get(ws.roomId);
  if (!room || !room.playing) return;

  const y = Math.max(0, Math.min(FIELD_H, Number(data.y) || FIELD_H / 2));
  if (ws.playerNumber === 1) {
    room.paddle1Y = y;
  } else if (ws.playerNumber === 2) {
    room.paddle2Y = y;
  }
}

function handleDisconnect(ws) {
  // キューから削除
  matchQueue = matchQueue.filter(w => w !== ws);

  // ルームから削除
  if (ws.roomId !== null) {
    const room = rooms.get(ws.roomId);
    if (room) {
      const opponent = ws.playerNumber === 1 ? room.player2 : room.player1;
      if (opponent && opponent.readyState === 1) {
        sendTo(opponent, { type: 'opponent_disconnected' });
      }
      destroyRoom(ws.roomId);
    }
  }
}

// --- ルーム管理 ---
function createRoom(p1, p2) {
  const roomId = ++roomIdCounter;
  console.log(`Room ${roomId} created`);

  p1.roomId = roomId;
  p1.playerNumber = 1;
  p2.roomId = roomId;
  p2.playerNumber = 2;

  const room = {
    id: roomId,
    player1: p1,
    player2: p2,
    playing: false,
    // パドル
    paddle1Y: FIELD_H / 2,
    paddle2Y: FIELD_H / 2,
    paddle1H: PADDLE_H,
    paddle2H: PADDLE_H,
    // ボール
    ballX: FIELD_W / 2,
    ballY: FIELD_H / 2,
    ballVX: 0,
    ballVY: 0,
    ballSpeed: BALL_SPEED_INIT,
    // マルチボール
    extraBalls: [],
    // スコア
    scoreP1: 0,
    scoreP2: 0,
    // パワーアップ
    powerups: [],
    powerupIdCounter: 0,
    nextPowerupTime: 0,
    effects: [],
    // タイマー
    gameLoop: null,
    lastTick: 0,
  };

  rooms.set(roomId, room);

  // マッチ通知
  sendTo(p1, { type: 'match_found', player_number: 1 });
  sendTo(p2, { type: 'match_found', player_number: 2 });

  // カウントダウン → ゲーム開始
  startCountdown(room);
}

function destroyRoom(roomId) {
  const room = rooms.get(roomId);
  if (!room) return;

  if (room.gameLoop) {
    clearInterval(room.gameLoop);
    room.gameLoop = null;
  }
  room.playing = false;

  if (room.player1) {
    room.player1.roomId = null;
    room.player1.playerNumber = 0;
  }
  if (room.player2) {
    room.player2.roomId = null;
    room.player2.playerNumber = 0;
  }

  rooms.delete(roomId);
  console.log(`Room ${roomId} destroyed. Active rooms: ${rooms.size}`);
}

// --- カウントダウン ---
function startCountdown(room) {
  let count = 3;
  const countdownInterval = setInterval(() => {
    broadcastToRoom(room, { type: 'countdown', count });
    count--;
    if (count < 0) {
      clearInterval(countdownInterval);
      broadcastToRoom(room, { type: 'countdown', count: 0 });
      startGame(room);
    }
  }, 1000);
}

// --- ゲーム開始 ---
function startGame(room) {
  room.playing = true;
  room.lastTick = Date.now();
  room.nextPowerupTime = Date.now() + randomInt(POWERUP_SPAWN_MIN, POWERUP_SPAWN_MAX);
  resetBall(room);

  room.gameLoop = setInterval(() => {
    const now = Date.now();
    const dt = (now - room.lastTick) / 1000;
    room.lastTick = now;
    updateGame(room, dt);
  }, TICK_MS);
}

// --- ボールリセット ---
function resetBall(room) {
  room.ballX = FIELD_W / 2;
  room.ballY = FIELD_H / 2;
  room.ballSpeed = BALL_SPEED_INIT;

  // ランダム方向
  const angle = (Math.random() * 0.5 - 0.25) * Math.PI; // -45° ~ 45°
  const dir = Math.random() < 0.5 ? 1 : -1;
  room.ballVX = Math.cos(angle) * room.ballSpeed * dir;
  room.ballVY = Math.sin(angle) * room.ballSpeed;

  // マルチボールクリア
  room.extraBalls = [];
  // ボール加速エフェクトをクリア
  room.effects = room.effects.filter(e => e.type !== 'ball_speed');
}

// --- ゲームループ ---
function updateGame(room, dt) {
  if (!room.playing) return;

  // エフェクト更新
  updateEffects(room, dt);

  // パワーアップ生成
  spawnPowerup(room);

  // メインボール更新
  updateBall(room, dt, 'main');

  // マルチボール更新
  for (let i = room.extraBalls.length - 1; i >= 0; i--) {
    const result = updateExtraBall(room, room.extraBalls[i], dt);
    if (result === 'scored') {
      room.extraBalls.splice(i, 1);
    }
  }

  // ゲーム状態をブロードキャスト
  const state = {
    type: 'game_state',
    ball: { x: room.ballX, y: room.ballY },
    extra_balls: room.extraBalls.map(b => ({ x: b.x, y: b.y })),
    paddles: {
      p1_y: room.paddle1Y,
      p2_y: room.paddle2Y,
      p1_h: room.paddle1H,
      p2_h: room.paddle2H,
    },
    score: { p1: room.scoreP1, p2: room.scoreP2 },
    powerups: room.powerups.map(p => ({
      id: p.id,
      x: p.x,
      y: p.y,
      ptype: p.type,
    })),
    effects: room.effects.map(e => ({
      type: e.type,
      target_player: e.targetPlayer,
      remaining: e.remaining,
    })),
  };
  broadcastToRoom(room, state);
}

function updateBall(room, dt, ballType) {
  // ボール移動
  room.ballX += room.ballVX * dt;
  room.ballY += room.ballVY * dt;

  // 上下壁反射
  if (room.ballY - BALL_SIZE / 2 <= 0) {
    room.ballY = BALL_SIZE / 2;
    room.ballVY = Math.abs(room.ballVY);
  }
  if (room.ballY + BALL_SIZE / 2 >= FIELD_H) {
    room.ballY = FIELD_H - BALL_SIZE / 2;
    room.ballVY = -Math.abs(room.ballVY);
  }

  // パドル1 (左) 衝突
  const p1Left = PADDLE_MARGIN - PADDLE_W / 2;
  const p1Right = PADDLE_MARGIN + PADDLE_W / 2;
  if (
    room.ballVX < 0 &&
    room.ballX - BALL_SIZE / 2 <= p1Right &&
    room.ballX + BALL_SIZE / 2 >= p1Left &&
    room.ballY >= room.paddle1Y - room.paddle1H / 2 &&
    room.ballY <= room.paddle1Y + room.paddle1H / 2
  ) {
    room.ballX = p1Right + BALL_SIZE / 2;
    const relY = (room.ballY - room.paddle1Y) / (room.paddle1H / 2);
    const angle = relY * (Math.PI / 3); // 最大60度
    room.ballSpeed = Math.min(room.ballSpeed * BALL_SPEED_INCREASE, BALL_SPEED_MAX);
    const speed = getEffectiveBallSpeed(room);
    room.ballVX = Math.cos(angle) * speed;
    room.ballVY = Math.sin(angle) * speed;
  }

  // パドル2 (右) 衝突
  const p2Left = FIELD_W - PADDLE_MARGIN - PADDLE_W / 2;
  const p2Right = FIELD_W - PADDLE_MARGIN + PADDLE_W / 2;
  if (
    room.ballVX > 0 &&
    room.ballX + BALL_SIZE / 2 >= p2Left &&
    room.ballX - BALL_SIZE / 2 <= p2Right &&
    room.ballY >= room.paddle2Y - room.paddle2H / 2 &&
    room.ballY <= room.paddle2Y + room.paddle2H / 2
  ) {
    room.ballX = p2Left - BALL_SIZE / 2;
    const relY = (room.ballY - room.paddle2Y) / (room.paddle2H / 2);
    const angle = relY * (Math.PI / 3);
    room.ballSpeed = Math.min(room.ballSpeed * BALL_SPEED_INCREASE, BALL_SPEED_MAX);
    const speed = getEffectiveBallSpeed(room);
    room.ballVX = -Math.cos(angle) * speed;
    room.ballVY = Math.sin(angle) * speed;
  }

  // パワーアップとの衝突判定
  checkPowerupCollision(room, room.ballX, room.ballY);

  // 得点判定
  if (room.ballX < -BALL_SIZE) {
    // P2得点
    room.scoreP2++;
    broadcastToRoom(room, { type: 'score', p1: room.scoreP1, p2: room.scoreP2, scorer: 2 });
    checkWin(room);
    if (room.playing) resetBall(room);
  } else if (room.ballX > FIELD_W + BALL_SIZE) {
    // P1得点
    room.scoreP1++;
    broadcastToRoom(room, { type: 'score', p1: room.scoreP1, p2: room.scoreP2, scorer: 1 });
    checkWin(room);
    if (room.playing) resetBall(room);
  }
}

function updateExtraBall(room, ball, dt) {
  ball.x += ball.vx * dt;
  ball.y += ball.vy * dt;

  // 上下壁反射
  if (ball.y - BALL_SIZE / 2 <= 0) {
    ball.y = BALL_SIZE / 2;
    ball.vy = Math.abs(ball.vy);
  }
  if (ball.y + BALL_SIZE / 2 >= FIELD_H) {
    ball.y = FIELD_H - BALL_SIZE / 2;
    ball.vy = -Math.abs(ball.vy);
  }

  // パドル衝突 (簡易版)
  const p1Right = PADDLE_MARGIN + PADDLE_W / 2;
  if (ball.vx < 0 && ball.x - BALL_SIZE / 2 <= p1Right && ball.x > 0 &&
      ball.y >= room.paddle1Y - room.paddle1H / 2 && ball.y <= room.paddle1Y + room.paddle1H / 2) {
    ball.x = p1Right + BALL_SIZE / 2;
    ball.vx = Math.abs(ball.vx);
  }
  const p2Left = FIELD_W - PADDLE_MARGIN - PADDLE_W / 2;
  if (ball.vx > 0 && ball.x + BALL_SIZE / 2 >= p2Left && ball.x < FIELD_W &&
      ball.y >= room.paddle2Y - room.paddle2H / 2 && ball.y <= room.paddle2Y + room.paddle2H / 2) {
    ball.x = p2Left - BALL_SIZE / 2;
    ball.vx = -Math.abs(ball.vx);
  }

  // パワーアップ衝突
  checkPowerupCollision(room, ball.x, ball.y);

  // 得点判定（マルチボールは得点なし、消えるだけ）
  if (ball.x < -BALL_SIZE || ball.x > FIELD_W + BALL_SIZE) {
    return 'scored';
  }
  return null;
}

// --- パワーアップ ---
function spawnPowerup(room) {
  if (Date.now() < room.nextPowerupTime) return;
  if (room.powerups.length >= 1) return; // フィールド上に最大1個

  const type = POWERUP_TYPES[Math.floor(Math.random() * POWERUP_TYPES.length)];
  const id = ++room.powerupIdCounter;
  const x = FIELD_W / 4 + Math.random() * (FIELD_W / 2); // 中央付近に出現
  const y = 60 + Math.random() * (FIELD_H - 120);

  room.powerups.push({ id, x, y, type });
  broadcastToRoom(room, { type: 'powerup_spawn', id, x, y, ptype: type });
  room.nextPowerupTime = Date.now() + randomInt(POWERUP_SPAWN_MIN, POWERUP_SPAWN_MAX);
}

function checkPowerupCollision(room, bx, by) {
  for (let i = room.powerups.length - 1; i >= 0; i--) {
    const p = room.powerups[i];
    const dx = bx - p.x;
    const dy = by - p.y;
    if (Math.sqrt(dx * dx + dy * dy) < POWERUP_RADIUS + BALL_SIZE / 2) {
      // ボールの進行方向で取得プレイヤーを判定
      const targetPlayer = room.ballVX > 0 ? 1 : 2;
      applyPowerup(room, p.type, targetPlayer);
      broadcastToRoom(room, { type: 'powerup_collected', id: p.id, ptype: p.type, target_player: targetPlayer });
      room.powerups.splice(i, 1);
    }
  }
}

function applyPowerup(room, type, targetPlayer) {
  const opponent = targetPlayer === 1 ? 2 : 1;

  switch (type) {
    case 'paddle_grow':
      // 自分のパドルを拡大
      if (targetPlayer === 1) room.paddle1H = PADDLE_H * 1.5;
      else room.paddle2H = PADDLE_H * 1.5;
      room.effects.push({ type: 'paddle_grow', targetPlayer, remaining: POWERUP_DURATION });
      break;
    case 'paddle_shrink':
      // 相手のパドルを縮小
      if (opponent === 1) room.paddle1H = PADDLE_H * 0.5;
      else room.paddle2H = PADDLE_H * 0.5;
      room.effects.push({ type: 'paddle_shrink', targetPlayer: opponent, remaining: POWERUP_DURATION });
      break;
    case 'ball_speed':
      room.effects.push({ type: 'ball_speed', targetPlayer: 0, remaining: 99 }); // 次の得点まで
      break;
    case 'multi_ball':
      // ボールを複製
      room.extraBalls.push({
        x: room.ballX,
        y: room.ballY,
        vx: room.ballVX * -0.8,
        vy: -room.ballVY * 1.2,
      });
      break;
  }
}

function getEffectiveBallSpeed(room) {
  let speed = room.ballSpeed;
  for (const e of room.effects) {
    if (e.type === 'ball_speed') {
      speed *= 1.5;
    }
  }
  return Math.min(speed, BALL_SPEED_MAX * 1.5);
}

function updateEffects(room, dt) {
  for (let i = room.effects.length - 1; i >= 0; i--) {
    const e = room.effects[i];
    e.remaining -= dt;
    if (e.remaining <= 0) {
      // エフェクト終了 → 元に戻す
      switch (e.type) {
        case 'paddle_grow':
          if (e.targetPlayer === 1) room.paddle1H = PADDLE_H;
          else room.paddle2H = PADDLE_H;
          break;
        case 'paddle_shrink':
          if (e.targetPlayer === 1) room.paddle1H = PADDLE_H;
          else room.paddle2H = PADDLE_H;
          break;
      }
      room.effects.splice(i, 1);
    }
  }
}

// --- 勝利判定 ---
function checkWin(room) {
  let winner = 0;
  if (room.scoreP1 >= WIN_SCORE) winner = 1;
  if (room.scoreP2 >= WIN_SCORE) winner = 2;

  if (winner > 0) {
    room.playing = false;
    if (room.gameLoop) {
      clearInterval(room.gameLoop);
      room.gameLoop = null;
    }
    broadcastToRoom(room, { type: 'game_over', winner });
    // ルーム削除を少し遅延
    setTimeout(() => destroyRoom(room.id), 3000);
  }
}

// --- ユーティリティ ---
function sendTo(ws, data) {
  if (ws && ws.readyState === 1) {
    ws.send(JSON.stringify(data));
  }
}

function broadcastToRoom(room, data) {
  sendTo(room.player1, data);
  sendTo(room.player2, data);
}

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}
