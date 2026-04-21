# データスキーマ

claude-code-usage-barで扱うデータの形式・構造・バージョニングを定義する。

---

## 概要

データは3つのレイヤーで流れる:

1. **statusLine入力JSON** — Claude Codeからcollectorへ（stdin）
2. **セッションスナップショット** — collectorからメニューバーアプリへ（ファイル）
3. **履歴データ** — 時系列記録（append-only JSONL）

---

## statusLine入力JSON（Claude Code → collector）

### 完全フィールド定義

Claude Codeが`statusLine`コマンドのstdinに渡すJSON:

| フィールド | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| `model` | string | Yes | 使用中のモデル名 |
| `cost` | object | Yes | セッション内推定コスト |
| `cost.total_cost` | number | Yes | 累計コスト（USD） |
| `cost.currency` | string | Yes | 通貨コード（`"USD"`） |
| `context_window` | object | Yes | コンテキストウィンドウ使用状況 |
| `context_window.total_tokens` | number | Yes | 最大トークン数 |
| `context_window.used_tokens` | number | Yes | 使用中トークン数 |
| `context_window.used_percentage` | number | Yes | 使用率（%） |
| `rate_limits` | object | No | 使用率制限（Pro/Maxのみ、初回API応答後） |
| `rate_limits.five_hour` | object | No | 5時間枠の制限情報 |
| `rate_limits.five_hour.used_percentage` | number | Yes* | 使用率（0.0〜100.0） |
| `rate_limits.five_hour.resets_at` | string | Yes* | リセット時刻（ISO 8601 UTC） |
| `rate_limits.seven_day` | object | No | 7日枠の制限情報 |
| `rate_limits.seven_day.used_percentage` | number | Yes* | 使用率（0.0〜100.0） |
| `rate_limits.seven_day.resets_at` | string | Yes* | リセット時刻（ISO 8601 UTC） |
| `session_id` | string | Yes | セッション識別子 |

*Yes*: 親オブジェクトが存在する場合は必須

### サンプルJSON

```json
{
  "model": "claude-sonnet-4-6",
  "cost": {
    "total_cost": 0.42,
    "currency": "USD"
  },
  "context_window": {
    "total_tokens": 200000,
    "used_tokens": 45000,
    "used_percentage": 22.5
  },
  "rate_limits": {
    "five_hour": {
      "used_percentage": 42.0,
      "resets_at": "2026-04-20T15:30:00Z"
    },
    "seven_day": {
      "used_percentage": 18.5,
      "resets_at": "2026-04-23T00:00:00Z"
    }
  },
  "session_id": "session_abc123def456"
}
```

`rate_limits`が存在しない場合（APIプラン・Teamプラン、または初回応答前）:

```json
{
  "model": "claude-opus-4-6",
  "cost": {
    "total_cost": 0.0,
    "currency": "USD"
  },
  "context_window": {
    "total_tokens": 200000,
    "used_tokens": 1200,
    "used_percentage": 0.6
  },
  "session_id": "session_xyz789"
}
```

---

## セッションスナップショット（collector → アプリ）

### ファイルパス規約

```
~/.claude/claude-usage-bar/sessions/session_{session_id}.json
```

例: `~/.claude/claude-usage-bar/sessions/session_abc123def456.json`

### スキーマ定義

collectorが書き込むスナップショットJSON:

| フィールド | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| `schema_version` | number | Yes | スキーマバージョン（現在: `1`） |
| `session_id` | string | Yes | セッション識別子 |
| `updated_at` | string | Yes | 最終更新時刻（ISO 8601 UTC） |
| `model` | string | Yes | 使用中モデル名 |
| `cost` | object | Yes | 推定コスト（statusLine入力と同構造） |
| `context_window` | object | Yes | コンテキスト使用状況（同上） |
| `rate_limits` | object \| null | Yes | 使用率制限（なければ`null`） |

### サンプルJSON

```json
{
  "schema_version": 1,
  "session_id": "session_abc123def456",
  "updated_at": "2026-04-20T12:05:30Z",
  "model": "claude-sonnet-4-6",
  "cost": {
    "total_cost": 0.42,
    "currency": "USD"
  },
  "context_window": {
    "total_tokens": 200000,
    "used_tokens": 45000,
    "used_percentage": 22.5
  },
  "rate_limits": {
    "five_hour": {
      "used_percentage": 42.0,
      "resets_at": "2026-04-20T15:30:00Z"
    },
    "seven_day": {
      "used_percentage": 18.5,
      "resets_at": "2026-04-23T00:00:00Z"
    }
  }
}
```

---

## 履歴データ（追記形式）

### append-only JSONL

使用率の時系列推移を記録するため、追記専用のJSONLファイルを使用する:

```
~/.claude/claude-usage-bar/history.jsonl
```

各行は独立したJSONオブジェクト:

```json
{"timestamp":"2026-04-20T12:05:30Z","five_hour_pct":42.0,"seven_day_pct":18.5,"session_id":"session_abc123def456"}
{"timestamp":"2026-04-20T12:06:00Z","five_hour_pct":42.5,"seven_day_pct":18.5,"session_id":"session_abc123def456"}
```

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `timestamp` | string | 記録時刻（ISO 8601 UTC） |
| `five_hour_pct` | number \| null | 5時間枠使用率（不明時`null`） |
| `seven_day_pct` | number \| null | 7日枠使用率（不明時`null`） |
| `session_id` | string | 記録元セッションID |

### ローテーション方針

| 条件 | アクション |
|------|----------|
| ファイルサイズ > 10MB | 古い行を削除（先頭から） |
| 30日以上経過したエントリ | クリーンアップ対象 |

ローテーションはメニューバーアプリの起動時に実施する。collectorは追記のみ行い、削除は行わない。

---

## 集約データ（アプリ内部）

### 最新rate_limitsの選択ロジック

複数セッションが同時に存在する場合、`rate_limits`はアカウント全体の値であるため最新のものを採用する:

1. `~/.claude/claude-usage-bar/sessions/`内の全JSONを読み込む
2. `rate_limits`が`null`でないものをフィルタ
3. `updated_at`が最も新しいセッションの`rate_limits`を採用
4. すべて`null`の場合は「データなし」状態を表示

### セッション別context/cost

`context_window`と`cost`はセッション固有の値であるため、セッション別に表示する:

| 表示先 | データ |
|--------|--------|
| メニューバー | 最新セッションの`context_window.used_percentage` |
| ポップオーバー | 全アクティブセッションの一覧（model、cost、context） |

アクティブセッションの判定: `updated_at`から30分以内のもの。

---

## バージョニング

### スキーマバージョンフィールド

セッションスナップショットJSONには`schema_version`フィールドを含める。現在のバージョンは`1`。

### 後方互換性の維持

- メジャーバージョン変更（1→2）: フィールドの削除・型変更を含む破壊的変更
- マイナー変更（フィールド追加）: バージョン番号は変更せず、未知フィールドは無視する方針
- アプリは`schema_version`を確認し、未対応バージョンの場合はファイルをスキップしてユーザーに更新を促す

---

## 関連リンク

- [statusLine JSONの仕様元](overview.md)
- [書き込み側の設計](collector.md)
- [読み取り側の設計](menubar-app.md)
