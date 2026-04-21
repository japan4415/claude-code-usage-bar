# ドキュメント設計書 — claude-code-usage-bar

Claude Code使用率をmacOSメニューバーに表示するネイティブアプリの設計ドキュメント全体構成。

---

## 1. ディレクトリ構造

```
.
├── README.md                          # 目次・概要・アーキテクチャサマリ・クイックスタート
└── docs/
    ├── DESIGN.md                      # 本ファイル（設計書メタ）
    ├── overview.md                    # 概要・前提（statusLine仕様、JSON構造、Claude Code概説）
    ├── architecture.md                # アーキテクチャ（データフロー図、コンポーネント責務）
    ├── collector.md                   # collector設計（statusLineラッパー、既存設定との共存）
    ├── menubar-app.md                 # メニューバーアプリ設計（Swift/SwiftUI/MenuBarExtra）
    ├── data-schema.md                 # データスキーマ（セッション単位JSON、履歴追記形式）
    ├── ux-design.md                   # UX設計（表示文字列、ポップオーバー、エラー状態）
    ├── tech-decisions.md              # 技術選定（採用/不採用の比較: Electron, Tauri, SwiftBar等）
    ├── mvp-scope.md                   # MVPスコープ（最小機能セット、v1.1以降の拡張ロードマップ）
    ├── distribution.md                # 配布・運用（署名、notarization、Sparkle、Homebrew Cask）
    ├── best-practices.md              # 実装ベストプラクティス（settings.json安全操作、性能）
    └── future.md                      # 将来拡張（OpenTelemetry、履歴分析、複数プロファイル）
```

---

## 2. 各ファイルの見出し構成

### README.md

```markdown
## claude-code-usage-bar
## 特徴
## スクリーンショット
## アーキテクチャ概要
  ### データフロー（図）
## インストール
  ### Homebrew Cask
  ### 手動インストール
## 使い方
  ### 初期設定
  ### メニューバー表示の読み方
## 開発
  ### 必要環境
  ### ビルド手順
## ドキュメント
  ### 目次（docs/以下へのリンク一覧）
## ライセンス
```

### docs/overview.md

```markdown
## はじめに
## Claude Codeとは
## statusLine hookの仕組み
  ### 実行タイミング
  ### stdin JSON構造
  ### stdout出力の規約
  ### refreshInterval
## statusLine JSONフィールド詳細
  ### model
  ### cost
  ### context_window
  ### rate_limits
    #### five_hour（used_percentage, resets_at）
    #### seven_day（used_percentage, resets_at）
## 制約と注意事項
  ### rate_limitsの出現条件（Pro/Max購読者のみ、最初のAPI応答後）
  ### /costの金額はローカル推定（課金とは異なる）
  ### workspace trust要件
## 用語定義
```

### docs/architecture.md

```markdown
## 全体アーキテクチャ
  ### データフロー図
  ### コンポーネント一覧
## コンポーネント責務
  ### Claude Code（データソース）
  ### collector（データ収集・永続化）
  ### メニューバーアプリ（表示・通知）
## プロセス間通信
  ### stdin/stdout（Claude Code ↔ collector）
  ### ファイルシステム（collector ↔ アプリ）
  ### FSEvents / DispatchSource（ファイル変更監視）
## セキュリティモデル
  ### ネットワーク通信なし
  ### 認証情報の非保持
  ### サンドボックス設計
## 複数セッション対応
  ### session_idによる分離
  ### 最新データの選択ロジック
```

### docs/collector.md

```markdown
## 概要
## collectorの役割
## ラッパー方式の設計
  ### 既存statusLine設定との共存
  ### 処理フロー（5ステップ）
## settings.jsonの操作
  ### 差分方式（丸ごと上書き禁止）
  ### バックアップと復元
  ### 既存statusLineの検出と保持
## 保存形式
  ### ディレクトリ構造（~/.claude/claude-usage-bar/）
  ### セッション単位JSON
  ### atomic write（途中状態の防止）
## 性能要件
  ### ネットワーク通信禁止
  ### 実行時間の上限
  ### npx/重いプロセス起動の回避
## インストール・アンインストール
  ### collectorバイナリの配置
  ### settings.jsonへの登録
  ### クリーンなアンインストール
```

### docs/menubar-app.md

```markdown
## 概要
## SwiftUI MenuBarExtra
  ### 基本構成
  ### Window/Menu スタイルの選択
## AppKit NSStatusItem併用条件
  ### MenuBarExtraの制約
  ### NSStatusItemが必要なケース
## ファイル監視
  ### FSEvents / DispatchSourceによるリアルタイム更新
  ### ポーリング間隔（フォールバック）
## 状態管理
  ### @Observable / ObservableObject
  ### セッションデータのマージロジック
## ライフサイクル
  ### Launch at Login（SMAppService）
  ### バックグラウンド動作（LSUIElement）
  ### メモリ使用量の管理
## 通知
  ### UserNotifications
  ### 閾値設定（70/85/95%）
```

### docs/data-schema.md

```markdown
## 概要
## statusLine入力JSON（Claude Code → collector）
  ### 完全フィールド定義
  ### サンプルJSON
## セッションスナップショット（collector → アプリ）
  ### ファイルパス規約
  ### スキーマ定義
  ### サンプルJSON
## 履歴データ（追記形式）
  ### append-only JSONL
  ### ローテーション方針
## 集約データ（アプリ内部）
  ### 最新rate_limitsの選択ロジック
  ### セッション別context/cost
## バージョニング
  ### スキーマバージョンフィールド
  ### 後方互換性の維持
```

### docs/ux-design.md

```markdown
## メニューバー表示
  ### 通常状態: "CC 5h 42% / 7d 18%"
  ### 警告状態: 色変化・アイコン変化
  ### コンパクト表示オプション
## ポップオーバー
  ### 使用率ゲージ（5h / 7d）
  ### リセット時刻カウントダウン
  ### コンテキスト使用率
  ### セッション一覧
  ### 設定へのアクセス
## データ欠落時の表現
  ### 「値なし」（rate_limits未受信）
  ### 「未使用」（セッション未開始）
  ### 「古いデータ」（最終更新からN分経過）
  ### 「非対応プラン」（API/Team等）
## 通知
  ### 使用率閾値通知（70/85/95%）
  ### リセット時刻通知
## アクセシビリティ
  ### VoiceOver対応
  ### Dynamic Type
```

### docs/tech-decisions.md

```markdown
## 採用技術
  ### Swift + SwiftUI（言語/UIフレームワーク）
  ### MenuBarExtra（メニューバー表示）
  ### SMAppService（ログイン時起動）
  ### FSEvents（ファイル監視）
  ### UserNotifications（通知）
## 不採用技術と理由
  ### Electron — オーバーヘッド過大、メニューバーアプリとしては重い
  ### Tauri — macOS専用統合にはSwiftの方が素直
  ### SwiftBar — MVP検証には良いが一般配布・オンボーディングに不向き
  ### 非公式API / セッショントークン — 壊れやすい、セキュリティリスク、statusLineで十分
  ### Keychain依存設計 — 認証情報を扱わない設計が安全
## collector言語の選択
  ### Swift CLI（アプリとの一体配布が容易）
  ### シェルスクリプト（代替案、クロスプラットフォーム性）
## 今後再評価する技術
  ### MLX対応（将来的なMoE最適化時に参照）は削除 — 本プロジェクトとは無関係
```

### docs/mvp-scope.md

```markdown
## MVP（v1.0）機能セット
  ### SwiftUI MenuBarExtraでメニューバー表示
  ### statusLine wrapperのインストール
  ### rate_limits.five_hour / seven_day 表示
  ### context_window.used_percentage 表示
  ### リセット時刻カウントダウン
  ### 閾値通知（70/85/95%）
  ### 既存settings.jsonのバックアップと安全な復元
  ### データ欠落・古いデータ・非対応プランの状態表示
## v1.1 拡張候補
  ### 履歴グラフ（5時間ブロック単位の使用率推移）
  ### 複数プロファイル対応
  ### Claude service status表示
  ### ピーク時間予測
## v2.0 拡張候補
  ### OpenTelemetry連携
  ### ccusage互換のローカルJSONL解析
  ### ウィジェット対応（macOS Widget）
## スコープ外（明示的に除外）
  ### Claude.aiへの直接ログイン
  ### API呼び出し（課金・使用量照会）
  ### 他ユーザーの使用率取得
```

### docs/distribution.md

```markdown
## 署名とnotarization
  ### Developer ID Application証明書
  ### notarizationワークフロー（xcrun notarytool）
  ### Hardened Runtime設定
## 配布形式
  ### DMGパッケージ
  ### Homebrew Cask
## 自動更新
  ### Sparkle Framework
  ### appcast.xml
  ### Delta updates
## CI/CD
  ### Xcode Cloud / GitHub Actions
  ### 自動署名+notarization
  ### リリースフロー
## システム要件
  ### macOS最低バージョン（14.0 Sonoma推奨）
  ### Apple Silicon / Intel対応
```

### docs/best-practices.md

```markdown
## settings.json操作の安全性
  ### 差分更新（丸ごと上書き禁止）
  ### バックアップファイルの作成
  ### 復元UI
  ### 並行編集への耐性（ファイルロック）
## collector性能
  ### 実行時間目標（<50ms）
  ### I/O最小化（atomic write 1回のみ）
  ### ネットワーク通信禁止
  ### プロセス起動コストの最小化
## 複数セッション対応
  ### session_idによるファイル分離
  ### 古いセッションのクリーンアップ
  ### 「最新のrate_limit値」の選択アルゴリズム
## エラーハンドリング
  ### JSONパースエラー
  ### ファイルアクセスエラー
  ### 不正なsession_id
## テスト戦略
  ### Unit Test（Swift Testing）
  ### collector単体テスト
  ### UI Test（XCUITest）
```

### docs/future.md

```markdown
## OpenTelemetry連携
  ### OTEL_LOG_RAW_API_BODIESとの統合
  ### メトリクス送信
## 履歴分析
  ### ccusage互換JSONL解析
  ### 日次・週次レポート
  ### 5時間ブロック単位の使用パターン可視化
## 複数プロファイル
  ### Claude Code設定プロファイルの切り替え
  ### プロファイル別使用率追跡
## ウィジェット対応
  ### macOS Widget Extension
  ### ロック画面ウィジェット
## その他の拡張候補
  ### Claude service statusの統合
  ### ピーク時間予測
  ### Shortcuts.app連携
  ### ヘルスチェック通知（長時間データ未更新時）
```

---

## 3. 相互リンク設計

```
README.md
  ├──→ docs/overview.md（「statusLine仕様の詳細」）
  ├──→ docs/architecture.md（「アーキテクチャの詳細」）
  ├──→ docs/mvp-scope.md（「機能スコープ」）
  └──→ docs/*.md（ドキュメント目次セクションから全ページへ）

docs/overview.md
  ├──→ docs/architecture.md（「アーキテクチャ全体像」）
  ├──→ docs/collector.md（「collector設計の詳細」）
  └──→ docs/data-schema.md（「JSONフィールドの完全定義」）

docs/architecture.md
  ├──→ docs/collector.md（「collectorコンポーネントの詳細」）
  ├──→ docs/menubar-app.md（「メニューバーアプリの詳細」）
  ├──→ docs/data-schema.md（「データスキーマの詳細」）
  └──→ docs/overview.md（「statusLine仕様」）

docs/collector.md
  ├──→ docs/architecture.md（「全体アーキテクチャ」）
  ├──→ docs/data-schema.md（「保存フォーマットの詳細」）
  ├──→ docs/best-practices.md（「settings.json操作の安全性」）
  └──→ docs/overview.md（「statusLine仕様」）

docs/menubar-app.md
  ├──→ docs/ux-design.md（「画面設計の詳細」）
  ├──→ docs/architecture.md（「コンポーネント間通信」）
  ├──→ docs/data-schema.md（「読み込むデータの形式」）
  └──→ docs/tech-decisions.md（「技術選定の根拠」）

docs/data-schema.md
  ├──→ docs/overview.md（「statusLine JSONの仕様元」）
  ├──→ docs/collector.md（「書き込み側の設計」）
  └──→ docs/menubar-app.md（「読み取り側の設計」）

docs/ux-design.md
  ├──→ docs/menubar-app.md（「実装詳細」）
  ├──→ docs/data-schema.md（「表示するデータの定義」）
  └──→ docs/mvp-scope.md（「MVP対象の機能」）

docs/tech-decisions.md
  ├──→ docs/menubar-app.md（「採用技術の実装詳細」）
  ├──→ docs/collector.md（「collector言語選択」）
  └──→ docs/distribution.md（「配布方式の根拠」）

docs/mvp-scope.md
  ├──→ docs/ux-design.md（「MVP対象画面」）
  ├──→ docs/future.md（「v1.1以降の拡張」）
  └──→ docs/architecture.md（「MVP対象コンポーネント」）

docs/distribution.md
  ├──→ docs/tech-decisions.md（「技術選定」）
  └──→ docs/best-practices.md（「CI/CDベストプラクティス」）

docs/best-practices.md
  ├──→ docs/collector.md（「collector性能要件」）
  ├──→ docs/menubar-app.md（「アプリ実装」）
  └──→ docs/data-schema.md（「データ形式」）

docs/future.md
  ├──→ docs/mvp-scope.md（「現在のスコープ」）
  └──→ docs/architecture.md（「拡張ポイント」）
```

---

## 4. 命名規則

| 対象 | ルール | 例 |
|------|--------|-----|
| ドキュメントファイル名 | 英小文字 + ハイフン区切り、`.md` | `menubar-app.md` |
| ディレクトリ名 | 英小文字 + ハイフン区切り | `docs/` |
| コード内の型名 | UpperCamelCase（Swift慣習） | `UsageBarApp`, `SessionSnapshot` |
| コード内の変数/関数名 | lowerCamelCase（Swift慣習） | `usedPercentage`, `fetchLatestSession()` |
| JSON キー | snake_case（Claude Code公式に準拠） | `rate_limits`, `used_percentage`, `resets_at` |
| settings.jsonキー | camelCase（Claude Code公式に準拠） | `statusLine`, `refreshInterval` |
| 見出し | 日本語、簡潔 | `## collector設計` |
| リンクテキスト | 日本語、遷移先が分かる表現 | `[collector設計の詳細](collector.md)` |
| 画像・図表 | `assets/{コンポーネント}-{説明}.{png,svg}` | `assets/architecture-dataflow.svg` |

---

## 5. 執筆担当分け

### 並列配分案（ファイル競合なし）

| 担当 | ファイル | 依存関係 | 備考 |
|------|---------|---------|------|
| **coder-A** | `docs/overview.md` | なし（最初に着手可能） | statusLine仕様の基盤。他ファイルが参照する |
| **coder-A** | `docs/data-schema.md` | overview.md完了後 | JSON仕様を詳細化 |
| **coder-B** | `docs/architecture.md` | なし（並列着手可能） | 全体像・データフロー図 |
| **coder-B** | `docs/collector.md` | architecture.md完了後 | collectorコンポーネントの深掘り |
| **coder-C** | `docs/tech-decisions.md` | なし（並列着手可能） | 独立した意思決定文書 |
| **coder-C** | `docs/menubar-app.md` | tech-decisions.md完了後 | Swift/SwiftUI実装設計 |
| **coder-D** | `docs/ux-design.md` | なし（並列着手可能） | 画面・インタラクション設計 |
| **coder-D** | `docs/mvp-scope.md` | ux-design.md完了後 | スコープ定義 |
| **coder-E** | `docs/best-practices.md` | collector.md, menubar-app.md完了後 | 横断的な実装ガイド |
| **coder-E** | `docs/distribution.md` | なし（並列着手可能） | 配布・署名は独立して書ける |
| **coder-E** | `docs/future.md` | mvp-scope.md完了後 | スコープ決定後に拡張を記述 |
| **coder-F** | `README.md` | 全docs完了後 | 全体を俯瞰してリンク整備 |

### Phase分け

```
Phase 1（全並列）:
  coder-A: overview.md
  coder-B: architecture.md
  coder-C: tech-decisions.md
  coder-D: ux-design.md
  coder-E: distribution.md

Phase 2（Phase 1完了後、並列）:
  coder-A: data-schema.md
  coder-B: collector.md
  coder-C: menubar-app.md
  coder-D: mvp-scope.md

Phase 3（Phase 2完了後）:
  coder-E: best-practices.md
  coder-E: future.md

Phase 4（全完了後）:
  coder-F: README.md
```

### 最小構成（3名の場合）

| 担当 | Phase 1 | Phase 2 | Phase 3 |
|------|---------|---------|---------|
| coder-A | overview.md + architecture.md | data-schema.md + collector.md | best-practices.md |
| coder-B | tech-decisions.md + ux-design.md | menubar-app.md + mvp-scope.md | future.md |
| coder-C | distribution.md | （待機） | README.md |

---

## 6. 執筆ガイドライン

### 統一表現

| 表記 | 統一先 | NG例 |
|------|--------|------|
| アプリ名 | claude-code-usage-bar | ClaudeCodeUsageBar, usage bar |
| Claude Code | Claude Code（スペースあり、先頭大文字） | claude code, ClaudeCode |
| statusLine | `statusLine`（バッククォート、camelCase） | StatusLine, status_line, status line |
| メニューバー | メニューバー | メニュバー, menu bar |
| collector | collector（小文字） | Collector, コレクター |
| 使用率 | 使用率 | 使用量（%の場合は「率」） |
| 5時間枠 | 5時間枠 / `five_hour` | 5h枠（UIの略記は別） |
| 7日枠 | 7日枠 / `seven_day` | 7d枠（UIの略記は別） |

### 記法ルール

- コード・設定キーは`` ` ``で囲む: `statusLine`, `rate_limits.five_hour.used_percentage`
- ファイルパスは`` ` ``で囲む: `~/.claude/settings.json`
- 図はMermaid記法を使用（GitHub上でレンダリング可能）
- JSONサンプルは```json コードブロックで記述
- 表は適宜使用し、比較情報は必ず表形式にする
- 各ファイル末尾に「関連リンク」セクションを設け、相互リンクを配置

### 参照すべき外部情報

| 情報 | 参照先 |
|------|--------|
| statusLine公式仕様 | Claude Code公式ドキュメント（hooks/statusLine） |
| 既存OSS参考 | ClaudeWatch（GitHub: statusLine hookで使用率JSONを書き出す設計） |
| MenuBarExtra仕様 | Apple Developer Documentation |
| SMAppService仕様 | Apple Developer Documentation |
| Sparkle | sparkle-project.org |

### 注意事項

- **ネットワーク通信不要の設計**: このアプリはClaude.aiへ接続しない。statusLineから受け取るローカルJSONのみで動作する点を全ドキュメントで一貫して強調する
- **既存設定との共存**: `statusLine`を既に使っているユーザーの設定を壊さないラッパー方式を前提とする
- **Pro/Max限定データ**: `rate_limits`はPro/Max購読者のみ。APIプラン・Teamプランでは表示できないケースがある点を必ず記載
- **推定値の注意**: `/cost`の金額はローカル推定であり課金額ではない。この点を明確に区別する
