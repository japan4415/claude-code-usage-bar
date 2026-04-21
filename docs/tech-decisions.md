# 技術選定

claude-code-usage-barの開発において採用・不採用とした技術とその判断根拠をまとめる。

---

## 採用技術

### Swift + SwiftUI（言語/UIフレームワーク）

| 項目 | 詳細 |
|------|------|
| 言語 | Swift 5.9+ |
| UIフレームワーク | SwiftUI |
| 最低対象OS | macOS 13.0 Ventura（14.0 Sonoma推奨） |

macOSネイティブのメニューバーアプリを構築する上で、Swift + SwiftUIは最も自然な選択肢である。

- **システム統合**: メニューバー、通知、ログイン時起動など、すべてのmacOS APIにファーストクラスでアクセス可能
- **パフォーマンス**: メモリフットプリントが小さく、常駐アプリとして適切。Electron等と比較して桁違いに軽量
- **配布の容易性**: Xcode標準のビルド・署名・notarizationフローに乗れる
- **型安全性**: JSON解析（`Codable`）で`statusLine`データの型安全なパースが可能

### MenuBarExtra（メニューバー表示）

SwiftUI標準の`MenuBarExtra`を使用してメニューバーアイテムを表示する。

```swift
MenuBarExtra("CC 5h 42% / 7d 18%", systemImage: "gauge.medium") {
    PopoverView()
}
.menuBarExtraStyle(.window)
```

| 利点 | 詳細 |
|------|------|
| 宣言的UI | SwiftUIのビューとして定義でき、状態変化に自動追従 |
| `.window`スタイル | ポップオーバーにSwiftUIビューをそのまま配置可能 |
| Apple公式API | macOS 13+で利用可能、長期サポートが期待できる |

### SMAppService（ログイン時起動）

| 項目 | 詳細 |
|------|------|
| API | `SMAppService.mainApp` |
| 対象OS | macOS 13+ |
| 特徴 | 従来のLogin Itemsより安全で、サンドボックスと互換 |

```swift
try SMAppService.mainApp.register()
```

ユーザーがログイン時にアプリを自動起動するための公式API。従来の`LSSharedFileList`やLaunchAgentに比べて安全で、システム環境設定の「ログイン項目」に自動的に表示される。

### FSEvents（ファイル監視）

collectorが書き出すセッションJSONファイルの変更を監視するために`DispatchSource.makeFileSystemObjectSource`を使用する。

| 項目 | 詳細 |
|------|------|
| API | `DispatchSource.makeFileSystemObjectSource` |
| 監視対象 | `~/.claude/claude-usage-bar/` ディレクトリ |
| イベント | `.write`（ファイル書き込み） |
| フォールバック | 30秒ポーリング（FSEventsが利用できない環境向け） |

ファイルシステムイベントにより、collectorがデータを更新した瞬間にメニューバー表示を更新できる。

### LSUIElement（Dock非表示）

`Info.plist`に`LSUIElement = true`を設定し、Dockアイコンを非表示にする。メニューバー常駐アプリとして、Dockに不要なアイコンを表示せずバックグラウンドagent appとして動作する。

```xml
<key>LSUIElement</key>
<true/>
```

### UserNotifications（通知）

使用率が閾値を超えた際にmacOS通知を表示する。

| 閾値 | 通知内容 |
|------|---------|
| 70% | 注意（使用率が高まっています） |
| 85% | 警告（まもなく制限に達します） |
| 95% | 危険（制限間近です） |

```swift
let content = UNMutableNotificationContent()
content.title = "Claude Code 使用率"
content.body = "5時間枠の使用率が85%に達しました"
```

### UserDefaults（設定永続化）

アプリ設定（表示モード、通知閾値、ログイン時起動）の永続化に`UserDefaults`を使用する。

| 項目 | 詳細 |
|------|------|
| API | `UserDefaults.standard` |
| 保存先 | `~/Library/Preferences/{bundle-id}.plist` |
| 特徴 | Keychain不要、認証情報を扱わない設計と整合 |

認証情報やAPIトークンを一切扱わないため、Keychainは不要。`UserDefaults`で十分な設定項目のみを管理する。

### Sparkle 2（自動更新）

| 項目 | 詳細 |
|------|------|
| フレームワーク | [Sparkle 2](https://sparkle-project.org) |
| 更新チェック | `appcast.xml`ベースのバージョン確認 |
| Delta updates | 差分アップデート対応で帯域節約 |
| 署名検証 | EdDSA署名による安全な更新 |

Mac App Store外での配布時に、ユーザーへ安全な自動更新を提供する。起動時またはユーザー操作時に`appcast.xml`を確認し、新バージョンがあればダウンロード・インストールを促す。

---

## 不採用技術と理由

### Electron — オーバーヘッド過大、メニューバーアプリとしては重い

| 項目 | Electron | Swift/SwiftUI |
|------|----------|---------------|
| メモリ使用量 | 100-200MB+ | 10-30MB |
| バイナリサイズ | 150MB+ | 5-10MB |
| 起動時間 | 数秒 | 即座 |
| macOS統合 | 限定的 | フルアクセス |

メニューバーに使用率を表示するだけのアプリに対して、Chromiumランタイム全体をバンドルするのは過剰。常駐アプリとしてのメモリ消費が許容範囲を大きく超える。

### Tauri — macOS専用統合にはSwiftの方が素直

Tauri v2はTray（システムトレイ/メニューバー）機能を備えた軽量なクロスプラットフォームフレームワークだが、本アプリはmacOS専用であり以下の点でSwiftが優位:

- `MenuBarExtra`, `SMAppService`, `FSEvents`などのmacOS専用APIに直接アクセスできる
- WebViewレイヤーを介さないため、メニューバー表示のカスタマイズに制約がない
- Xcodeの署名・notarizationフローにそのまま乗れる

### SwiftBar — MVP検証には良いが一般配布・オンボーディングに不向き

[SwiftBar](https://github.com/swiftbar/SwiftBar)はスクリプトベースのメニューバーユーティリティであり、プロトタイプ検証には有用。

| 項目 | SwiftBar | ネイティブアプリ |
|------|----------|----------------|
| 初期開発速度 | 速い（シェルスクリプトで可） | やや遅い |
| 配布の容易性 | SwiftBar本体のインストールが前提 | 単体で動作 |
| カスタマイズ性 | スクリプト出力フォーマットに制約 | 自由 |
| 通知・設定UI | 限定的 | フルコントロール |
| ポップオーバー | 未対応 | SwiftUIで自由に設計 |
| 既存`statusLine`との安全マージ | 対応困難 | ラッパー方式で共存可能 |
| 自動更新 | なし | Sparkle 2で対応 |

一般ユーザーへの配布を考えると、SwiftBar依存は導入障壁が高い。さらに、既存の`statusLine`設定を壊さずにcollectorを安全にマージする処理や、Sparkle 2による自動更新など、プロダクション品質に必要な機能はネイティブアプリでなければ実現が困難。

### 非公式API / セッショントークン — 壊れやすい、セキュリティリスク、statusLineで十分

Claude.aiのWeb APIやセッショントークンを使用して使用率を直接取得する方法は以下の理由で不採用:

- **壊れやすい**: 非公式APIはいつでも変更・廃止される可能性がある
- **セキュリティリスク**: セッショントークンの保存・管理が必要となり、漏洩リスクが生じる
- **不要**: `statusLine` hookが公式に使用率情報を提供しており、ネットワーク通信なしで取得可能

### Keychain依存設計 — 認証情報を扱わない設計が安全

本アプリは認証情報を一切扱わない設計としたため、Keychainへのアクセスは不要。

- `statusLine`からローカルJSONを受け取るだけで動作する
- ネットワーク通信を行わないため、APIキーやトークンの管理が不要
- セキュリティ審査の観点でも、認証情報を保持しないアプリの方が安全

---

## collector言語の選択

### Swift CLI（アプリとの一体配布が容易）

| 項目 | 詳細 |
|------|------|
| 言語 | Swift |
| 形式 | コマンドラインツール |
| 配布 | アプリバンドル内に同梱（`Contents/MacOS/collector`） |

collectorをSwiftで実装する利点:

- **一体配布**: メニューバーアプリと同一バンドルに含められる。インストール時にPATH設定やバイナリ配置が不要
- **型共有**: アプリ本体とcollectorでJSON型定義（`Codable`構造体）を共有可能。データスキーマの不整合を防止
- **署名の統一**: 同一のDeveloper ID証明書で署名でき、notarizationも一括で完了

### シェルスクリプト（代替案、クロスプラットフォーム性）

シェルスクリプト（bash/zsh + jq）による代替実装も検討した:

| 項目 | シェルスクリプト | Swift CLI |
|------|-----------------|-----------|
| 実行速度 | jqの起動コストあり | コンパイル済みで高速 |
| 依存 | jqが必要（未インストールの場合あり） | 依存なし |
| 型安全性 | なし | `Codable`で保証 |
| クロスプラットフォーム | Linux/macOS共通 | macOS専用 |
| 保守性 | 複雑化しやすい | 構造化しやすい |

macOS専用アプリであるため、Swift CLIを第一選択とする。ただし、デバッグ・検証目的で簡易なシェルスクリプト版も提供を検討。

---

## 今後再評価する技術

| 技術 | 再評価条件 | 期待される影響 |
|------|-----------|--------------|
| WidgetKit | macOS Widget APIの成熟 | ロック画面・デスクトップウィジェットでの使用率表示 |
| SwiftData | ローカル履歴機能の実装時 | 履歴データの永続化・クエリの簡素化 |
| Shortcuts.app連携 | v1.1以降の拡張時 | 「使用率が高い時に通知」等のユーザーカスタム自動化 |
| App Intents | v1.1以降の拡張時 | Siri / Spotlight連携での使用率照会 |

---

## 関連リンク

- [メニューバーアプリ設計の詳細](menubar-app.md)
- [collector設計](collector.md)
- [配布・署名](distribution.md)
