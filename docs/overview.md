# 概要・前提

Claude Codeの使用率をmacOSメニューバーに表示するアプリ「claude-code-usage-bar」の背景情報と前提条件をまとめる。

---

## はじめに

claude-code-usage-barは、Claude Codeの`statusLine` hookから取得できる使用率情報をmacOSメニューバーに常時表示するネイティブアプリである。ネットワーク通信を一切行わず、ローカルのJSON情報のみで動作する。

---

## Claude Codeとは

Claude CodeはAnthropicが提供するCLIツールで、ターミナル上でClaudeと対話しながらソフトウェア開発を行うことができる。Pro/Maxプランでは使用率に上限があり（5時間枠・7日枠）、現在の使用率を把握することが運用上重要となる。

---

## statusLine hookの仕組み

Claude Codeの`statusLine`は、IDE拡張やカスタムツールに対してセッション情報をリアルタイムに提供するhook機構である。

### 実行タイミング

`statusLine`に登録されたコマンドは以下のタイミングで実行される:

- セッション開始時
- APIレスポンス受信後
- `refreshInterval`で指定された間隔（定期更新）

### stdin JSON構造

`statusLine`コマンドには標準入力としてJSON文字列が渡される:

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
  "session_id": "abc123"
}
```

### stdout出力の規約

`statusLine`コマンドのstdout出力はIDEのステータスバーに表示される文字列となる。本アプリのcollectorはこの仕組みをラップし、元の出力を保持しつつデータを収集する。

### refreshInterval

`~/.claude/settings.json`の`statusLine`設定内で`refreshInterval`（ミリ秒）を指定することで、定期的にhookが再実行される。デフォルトは10000（10秒）。

```json
{
  "statusLine": {
    "command": "/path/to/collector",
    "refreshInterval": 10000
  }
}
```

---

## statusLine JSONフィールド詳細

### model

現在使用中のモデル名。例: `"claude-sonnet-4-6"`, `"claude-opus-4-6"`

### cost

セッション内の推定コスト情報。

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `total_cost` | number | セッション累計の推定コスト（USD） |
| `currency` | string | 通貨コード（常に`"USD"`） |

### context_window

コンテキストウィンドウの使用状況。

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `total_tokens` | number | コンテキストウィンドウの最大トークン数 |
| `used_tokens` | number | 現在使用中のトークン数 |
| `used_percentage` | number | 使用率（%） |

### rate_limits

使用率制限の情報。**Pro/Max購読者のみ提供される。**

#### five_hour（used_percentage, resets_at）

5時間枠の使用率制限。

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `used_percentage` | number | 5時間枠の使用率（0.0〜100.0） |
| `resets_at` | string (ISO 8601) | リセット時刻（UTC） |

#### seven_day（used_percentage, resets_at）

7日枠の使用率制限。

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `used_percentage` | number | 7日枠の使用率（0.0〜100.0） |
| `resets_at` | string (ISO 8601) | リセット時刻（UTC） |

---

## 制約と注意事項

### rate_limitsの出現条件（Pro/Max購読者のみ、最初のAPI応答後）

`rate_limits`フィールドは以下の条件を満たす場合のみ含まれる:

- ユーザーがPro/Maxプランに加入している
- セッション内で少なくとも1回のAPI応答を受信済み

APIプラン・Teamプランのユーザーには`rate_limits`が提供されないため、アプリは「非対応プラン」状態を適切に表示する必要がある。

### /costの金額はローカル推定（課金とは異なる）

`cost.total_cost`はClaude Codeがローカルで推定した値であり、Anthropicの実際の課金額とは異なる場合がある。この値はあくまで参考情報であり、正確な課金確認にはAnthropicのダッシュボードを使用する必要がある。

### workspace trust要件

`statusLine` hookはworkspaceのtrust設定に依存する。信頼されていないworkspaceでは`statusLine`が実行されない場合がある。

---

## 用語定義

| 用語 | 定義 |
|------|------|
| Claude Code | Anthropicが提供するCLI開発ツール |
| `statusLine` | Claude CodeのIDEステータスバー向けhook機構 |
| collector | `statusLine`をラップしてデータを収集・永続化するコンポーネント |
| メニューバー | macOS画面上部のシステムメニュー領域 |
| 使用率 | rate_limitsにおける上限に対する消費割合（%） |
| 5時間枠 | `rate_limits.five_hour` — 5時間ローリングウィンドウの使用率制限 |
| 7日枠 | `rate_limits.seven_day` — 7日ローリングウィンドウの使用率制限 |
| `refreshInterval` | `statusLine` hookの再実行間隔（ミリ秒） |
| session_id | Claude Codeの個別セッションを識別するID |


---

## 関連リンク

- [アーキテクチャ全体像](architecture.md)
- [collector設計の詳細](collector.md)
- [JSONフィールドの完全定義](data-schema.md)
