# MVPスコープ

claude-code-usage-barのMVP（v1.0）で実装する機能セットと、v1.1以降の拡張ロードマップを定義する。

---

## MVP（v1.0）機能セット

### SwiftUI MenuBarExtraでメニューバー表示

- [x] `MenuBarExtra(.window)`スタイルでメニューバーに使用率を常時表示
- [x] 表示フォーマット: `CC 5h {n}% / 7d {n}%`（[UX設計](ux-design.md)参照）
- [x] 使用率に応じた色変化・アイコン変化（通常/注意/警告/危険の4段階）
- [x] コンパクト表示オプション（標準 / 数値のみ / 5時間枠のみ / アイコンのみ）

### statusLine wrapperのインストール

- [x] アプリ初回起動時にcollectorの`statusLine`登録を案内
- [x] `~/.claude/settings.json`への安全な差分書き込み（丸ごと上書き禁止）
- [x] 既存の`statusLine`設定を検出し、ラッパー方式で共存
- [x] collectorバイナリはアプリバンドル内に同梱（`Contents/MacOS/collector`）

### rate_limits.five_hour / seven_day 表示

- [x] 5時間枠の使用率（`rate_limits.five_hour.used_percentage`）をゲージ表示
- [x] 7日枠の使用率（`rate_limits.seven_day.used_percentage`）をゲージ表示
- [x] メニューバーとポップオーバーの両方に表示

### context_window.used_percentage 表示

- [x] コンテキストウィンドウの使用率をポップオーバーに表示
- [x] 使用トークン数 / 最大トークン数の表示

### リセット時刻カウントダウン

- [x] `resets_at`から現在時刻との差分を計算
- [x] 相対時間表示（`N時間M分後` / `M分後` / `まもなく`）
- [x] リセット済み（過去の時刻）の適切な表示

### 閾値通知（70/85/95%）

- [x] 使用率が70%/85%/95%を超えた際にmacOS通知を送信
- [x] 同一リセット期間内での重複通知防止
- [x] 5時間枠と7日枠を独立に追跡
- [x] 設定で各閾値の通知を個別に有効/無効化

### 既存settings.jsonのバックアップと安全な復元

- [x] `statusLine`登録前に`~/.claude/settings.json`のバックアップを作成
- [x] バックアップファイルのパス: `~/.claude/claude-usage-bar/backup/settings.json.bak`
- [x] アプリのアンインストール時またはUI操作で元の設定に復元可能
- [x] 復元UIをポップオーバーの設定セクションに配置

### データ欠落・古いデータ・非対応プランの状態表示

- [x] `rate_limits`未受信時: `CC —` + 「Open Claude Code or run a prompt to refresh usage.」
- [x] セッション未開始時: `CC —` + 「No active session.」
- [x] 古いデータ時: 経過時間に応じた3段階の表示変化（5分/30分/2時間）
- [x] 非対応プラン（API/Team）: `CC —` + 「Rate limits are available on Pro/Max plans.」+ `context_window`と`cost`のみ表示

---

## v1.1 拡張候補

### 履歴グラフ（5時間ブロック単位の使用率推移）

- 過去の使用率データをJSONL形式で蓄積
- 5時間ブロック単位の使用率推移をSwift Chartsでグラフ表示
- 直近24時間〜7日間のトレンド確認

### 複数プロファイル対応

- Claude Codeの設定プロファイル（ワークスペース別等）の切り替え
- プロファイル別の使用率追跡
- メニューバーでのアクティブプロファイル表示

### Claude service status表示

- Anthropicのステータスページ情報をポップオーバーに統合
- サービス障害時の視覚的なインジケーター
- ステータス変化時の通知（オプション）

### ピーク時間予測

- 過去の使用パターンから、残り枠の使い切り時刻を予測
- 「このペースで使い続けるとN時間後に制限に達します」表示
- ペース配分のアドバイス

---

## v2.0 拡張候補

### OpenTelemetry連携

- `OTEL_LOG_RAW_API_BODIES`環境変数との統合
- 使用率メトリクスのOTELフォーマットでのエクスポート
- 外部のモニタリングシステム（Grafana等）への接続

### ccusage互換のローカルJSONL解析

- [ccusage](https://github.com/ryoppippi/ccusage)が生成するローカルJSONLファイルの解析
- 日次・週次のコスト集計レポート
- モデル別・プロジェクト別のコスト分析

### ウィジェット対応（macOS Widget）

- macOS Widget Extensionによるデスクトップウィジェット
- ロック画面ウィジェット
- 複数サイズ（small/medium）対応

---

## スコープ外（明示的に除外）

以下の機能は設計方針（ネットワーク通信不要・認証情報非保持）に反するため、全バージョンを通じてスコープ外とする。

### Claude.aiへの直接ログイン

- セッショントークンの取得・管理はセキュリティリスクが高い
- `statusLine`で必要な情報は取得可能であり不要

### API呼び出し（課金・使用量照会）

- Anthropic APIへの直接アクセスは認証情報の管理が必要
- `cost.total_cost`はローカル推定値として表示（課金額との差異を明記）
- 正確な課金確認はAnthropicダッシュボードを案内

### 他ユーザーの使用率取得

- マルチユーザー環境での他アカウント情報へのアクセスは設計範囲外
- `statusLine`は実行中ユーザーのセッション情報のみ提供

---

## 関連リンク

- [UX設計（MVP対象画面）](ux-design.md)
- [将来拡張の詳細](future.md)
- [アーキテクチャ（MVP対象コンポーネント）](architecture.md)
