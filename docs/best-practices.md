# 実装ベストプラクティス

claude-code-usage-barの実装における横断的なベストプラクティスを定義する。`settings.json`の安全な操作、collector性能、複数セッション対応、エラーハンドリング、テスト戦略をカバーする。

---

## settings.json操作の安全性

### 差分更新（丸ごと上書き禁止）

`~/.claude/settings.json`はClaude Codeの全設定を含むファイルであり、丸ごと上書きすると他の設定を破壊する。必ず差分更新を行う。

```swift
// 既存設定を読み込み
let data = try Data(contentsOf: settingsURL)
var settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

// statusLineキーのみ更新
settings["statusLine"] = [
    "command": collectorPath,
    "refreshInterval": 10000,
    "__claude_usage_bar_original": originalStatusLine
]

// 書き戻し
let updated = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
try updated.write(to: settingsURL, options: .atomic)
```

| 操作 | 許可 | 理由 |
|------|------|------|
| `statusLine`キーの更新 | OK | collectorの登録に必要 |
| `statusLine`以外のキーの読み取り | OK | 既存設定の確認に使用 |
| `statusLine`以外のキーの変更 | NG | 他の設定を破壊するリスク |
| ファイル全体の上書き | NG | 読み込み〜書き込み間に別プロセスが変更する可能性 |

### バックアップファイルの作成

`settings.json`を変更する前に必ずバックアップを取る:

```
~/.claude/claude-usage-bar/backup/settings.json.bak
```

バックアップはインストール時に1回作成し、以降の更新では上書きしない。ユーザーが明示的に再バックアップを要求した場合のみ更新する。

### 復元UI

メニューバーアプリのポップオーバーまたは設定画面に「設定を復元」オプションを提供する:

1. バックアップの存在確認
2. 現在の`settings.json`と差分を表示
3. ユーザー確認後に`statusLine`キーをバックアップの値で上書き（またはキー削除）
4. `~/.claude/claude-usage-bar/`ディレクトリの削除オプション

### 並行編集への耐性（ファイルロック）

Claude Code自身やユーザーのエディタが`settings.json`を同時に編集する可能性がある。

| 対策 | 実装 |
|------|------|
| atomic write | `Data.write(to:options:.atomic)`で中間状態を防止 |
| 読み取り→変更→書き込みの最小化 | 3操作を可能な限り短い時間で完了 |
| ファイルロック | `flock(2)`によるアドバイザリロック（タイムアウト付き） |
| リトライ | ロック取得失敗時は最大3回リトライ（100ms間隔） |

```swift
let fd = open(settingsURL.path, O_RDWR)
defer { close(fd) }

var lock = flock()
lock.l_type = Int16(F_WRLCK)
lock.l_whence = Int16(SEEK_SET)

guard fcntl(fd, F_SETLK, &lock) != -1 else {
    // ロック取得失敗 → リトライまたはスキップ
    return
}
defer {
    lock.l_type = Int16(F_UNLCK)
    fcntl(fd, F_SETLK, &lock)
}
// ロック内で読み取り→変更→書き込み
```

---

## collector性能

### 実行時間目標（<50ms）

collectorは`statusLine` hookとして高頻度（デフォルト10秒間隔）で呼ばれる。Claude Codeのレスポンスに影響しないよう、総実行時間を50ms以下に抑える。

| フェーズ | 目標時間 | 備考 |
|---------|---------|------|
| プロセス起動 | < 10ms | コンパイル済みSwiftバイナリ |
| stdin読み取り+パース | < 5ms | JSONのサイズは数KB |
| ファイル書き込み | < 20ms | atomic write 1回 + JSONL追記1回 |
| 元コマンド実行 | < 25ms | タイムアウト設定、ない場合はスキップ |

### I/O最小化（atomic write 1回のみ）

1回のhook呼び出しで行うファイルI/Oを最小限にする:

| I/O操作 | 回数 | 対象 |
|---------|------|------|
| セッションスナップショット書き込み | 1回 | `sessions/session_{session_id}.json` |
| 履歴JSONL追記 | 1回 | `history.jsonl` |
| ログ書き込み | 0〜1回 | エラー時のみ `collector.log` |

ディレクトリの存在確認やファイルの読み取りは初回のみ行い、以降はエラー時にリトライする方式を取る。

### ネットワーク通信禁止

collectorはいかなる状況でもネットワーク通信を行わない。テレメトリ送信、バージョンチェック、外部API呼び出しのすべてが禁止対象。

### プロセス起動コストの最小化

| 方式 | 起動コスト | 採用 |
|------|----------|------|
| コンパイル済みSwiftバイナリ | ~5ms | 推奨 |
| シェルスクリプト（bash/zsh） | ~10ms | 代替案 |
| `node` / `npx` | ~150ms+ | 禁止 |
| `python3` | ~100ms+ | 禁止 |
| `ruby` | ~100ms+ | 禁止 |

---

## 複数セッション対応

### session_idによるファイル分離

各セッションのデータは独立したJSONファイルとして管理する。ファイルパスはセッションIDで一意に決定される。

```
~/.claude/claude-usage-bar/sessions/
├── session_abc123.json
├── session_def456.json
└── session_ghi789.json
```

session_idにファイルシステムで使用できない文字が含まれる可能性があるため、英数字・ハイフン・アンダースコア以外はパーセントエンコーディングする。

### 古いセッションのクリーンアップ

長期間更新のないセッションファイルを定期的に削除する:

| 条件 | アクション | 実行タイミング |
|------|----------|--------------|
| `updated_at`から24時間経過 | 「非アクティブ」に分類 | アプリ読み込み時 |
| `updated_at`から7日経過 | ファイル削除 | アプリ起動時 |

クリーンアップはメニューバーアプリが実行する。collectorは書き込みのみ行い、削除は行わない。

### 「最新のrate_limit値」の選択アルゴリズム

`rate_limits`はアカウント全体の値であり、セッション固有ではない。複数セッションから最も信頼性の高い値を選択する:

```
1. sessions/内の全JSONを読み込む
2. rate_limits != null のセッションをフィルタ
3. updated_at が最新のセッションを選択
4. そのセッションの rate_limits を表示に使用
5. 全セッションの rate_limits が null → 「データなし」状態
```

フィールドの詳細は[データスキーマ](data-schema.md)を参照。

---

## エラーハンドリング

### JSONパースエラー

| 発生箇所 | 原因 | 対処 |
|---------|------|------|
| collector（stdin） | Claude Codeが不正なJSONを送信 | ログに記録、元コマンドがあればそちらに中継、デフォルト文字列を出力 |
| アプリ（ファイル読み込み） | 書き込み途中のファイル（atomic write失敗時） | 該当ファイルをスキップ、次回読み込みで再試行 |
| アプリ（ファイル読み込み） | `schema_version`不一致 | スキップしてログ、ユーザーにアプリ更新を促す |

### ファイルアクセスエラー

| エラー | collector側 | アプリ側 |
|--------|-----------|---------|
| ディレクトリ不存在 | 作成を試みる | 「初期化中」状態を表示 |
| 書き込み権限なし | ログに記録、stdoutのみ出力 | 「設定エラー」状態を表示 |
| ディスク容量不足 | ログに記録、処理続行 | 既存データで表示を継続 |

### 不正なsession_id

session_idが空文字列、異常に長い（>256文字）、またはパス traversal（`../`を含む）を試みる場合:

| 条件 | 対処 |
|------|------|
| 空文字列 | `unknown_session` をデフォルトとして使用 |
| 256文字超 | SHA-256ハッシュに変換 |
| パス traversal文字を含む | 該当文字をパーセントエンコーディング |

---

## テスト戦略

### Unit Test（Swift Testing）

| テスト対象 | テスト内容 |
|-----------|----------|
| JSONパーサ | 正常系・異常系（欠落フィールド、不正な型、空JSON） |
| スナップショット書き込み | atomic write動作、ファイル内容の正確性 |
| 集約ロジック | 複数セッションからの最新rate_limits選択 |
| クリーンアップ | 期限切れセッションの判定・削除 |
| settings.json操作 | 差分更新、バックアップ・復元 |

### collector単体テスト

collectorをCLIとしてテストする:

```bash
# 正常系: JSONを渡して出力を確認
echo '{"model":"claude-sonnet-4-6","cost":{"total_cost":0.1,"currency":"USD"},"context_window":{"total_tokens":200000,"used_tokens":5000,"used_percentage":2.5},"session_id":"test_001"}' | ./collector

# 異常系: 不正なJSONを渡す
echo 'invalid json' | ./collector

# 性能テスト: 実行時間計測
time echo '...' | ./collector
```

テスト実行時は一時ディレクトリを使い、`~/.claude/`の実データに影響しないようにする。環境変数`CLAUDE_USAGE_BAR_DATA_DIR`でデータディレクトリを上書き可能とする。

### UI Test（XCUITest）

| テストシナリオ | 確認内容 |
|--------------|---------|
| 正常表示 | メニューバーに使用率が表示される |
| データ欠落 | 「データなし」状態が正しく表示される |
| 閾値通知 | 70%/85%/95%で通知が発行される |
| ポップオーバー | セッション一覧が正しく表示される |
| 設定復元 | バックアップからの復元が正常に動作する |

---

## 関連リンク

- [collector性能要件](collector.md)
- [アプリ実装](menubar-app.md)
- [データ形式](data-schema.md)
