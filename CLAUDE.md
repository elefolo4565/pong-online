# プロジェクト構成ガイド

## アーキテクチャ（Godotオンラインゲーム共通）
- **クライアント**: Godot 4.x (GDScript) → HTML5エクスポートでブラウザ対応
- **サーバー**: Node.js + ws (WebSocketライブラリ)
- **通信**: WebSocket (JSON形式)
- **サーバー方式**: サーバー権威型（ゲームロジックはサーバーで処理）

## ディレクトリ構成
```
project-name/
  client/          # Godotプロジェクト
    project.godot
    scenes/        # .tscnファイル
    scripts/       # .gdスクリプト
    assets/        # フォント・画像など
    export/        # HTML5エクスポート出力先
  server/          # Node.jsサーバー
    package.json
    server.js
    render.yaml    # Render.comデプロイ設定
  CLAUDE.md
  .gitignore
```

## Autoload（クライアント共通）
- `websocket_client.gd` - WebSocket通信管理
- `game_state.gd` - ゲーム状態保持（シーン間共有）

## デプロイ先
- **クライアント（HTML）**: GitHub Pages (`client/export/` を公開)
- **サーバー**: Render.com (無料プラン, Root Directory: `server`)

## デプロイ手順
1. Godotエディタでプロジェクトをエクスポート → `client/export/index.html`
2. `git add . && git commit && git push` でGitHubにプッシュ
3. GitHub Pages: リポジトリ設定でmaster, `/` を公開 → `https://<user>.github.io/<repo>/client/export/index.html`
4. Render.com: GitHubリポジトリ接続、Root Directory=`server`、Build=`npm install`、Start=`node server.js`

## 通信遅延対策（必須）
オンラインゲームでは常に以下の対策を実装すること:
- **クライアント予測**: ボールなど移動物体はサーバーから速度を受信し、クライアント側で毎フレーム予測移動する
- **補間(lerp)**: 相手プレイヤーの位置はlerpで滑らかに追従する
- **自分の入力は即座反映**: 自分のパドル/キャラクターはサーバー応答を待たずにローカルで即座に反映する
- **送信頻度の最適化**: 物理演算は60fpsで行い、ネットワーク送信は20fps程度に抑える
- **スナップ補正**: サーバーとのズレが大きい場合は即座にスナップ、小さい場合は補間で修正

## WebSocket接続先
- ローカル開発: `ws://localhost:8080`
- 本番: `wss://<app-name>.onrender.com`
- `websocket_client.gd` の `server_url` を切り替える

## GitHubアカウント
- ユーザー名: elefolo4565
- gh CLI認証済み
