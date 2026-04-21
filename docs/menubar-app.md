# メニューバーアプリ設計

claude-code-usage-barのメニューバーアプリコンポーネントの実装設計。Swift/SwiftUIによるネイティブ実装で、`statusLine`から取得した使用率データをリアルタイムに表示する。

---

## 概要

メニューバーアプリはclaude-code-usage-barのフロントエンドコンポーネントであり、以下の責務を持つ:

- collectorが書き出したセッションJSONファイルを監視・読み込み
- 使用率データをメニューバーに常時表示
- ポップオーバーで詳細情報を提供
- 閾値超過時にmacOS通知を送信

| 項目 | 詳細 |
|------|------|
| 言語 | Swift 5.9+ |
| UIフレームワーク | SwiftUI |
| メニューバーAPI | `MenuBarExtra`（macOS 13+） |
| 最低対象OS | macOS 13.0 Ventura（14.0 Sonoma推奨） |
| アプリ形態 | バックグラウンドagent app（`LSUIElement = true`） |

技術選定の根拠は[技術選定](tech-decisions.md)を参照。

---

## SwiftUI MenuBarExtra

### 基本構成

`MenuBarExtra`はSwiftUIの宣言的構文でメニューバーアイテムを定義する。

```swift
@main
struct UsageBarApp: App {
    @State private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(viewModel: viewModel)
        } label: {
            UsageLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
```

`UsageLabel`はメニューバーに表示するテキスト・アイコンを動的に生成する。表示フォーマットの詳細は[UX設計](ux-design.md)を参照。

### Window/Menu スタイルの選択

`MenuBarExtra`には2つのスタイルがある:

| スタイル | 特徴 | 用途 |
|---------|------|------|
| `.window` | SwiftUIビューをポップオーバーとして表示 | ゲージ・グラフ等のリッチUI |
| `.menu` | 標準メニューアイテムのリスト | シンプルなアクション一覧 |

本アプリは使用率ゲージ、リセットカウントダウン、セッション一覧等のリッチUIが必要なため、`.window`スタイルを採用する。

```swift
.menuBarExtraStyle(.window)
```

`.window`スタイルでは、ポップオーバーのサイズは内部ビューの`frame`で制御する。

---

## AppKit NSStatusItem併用条件

### MenuBarExtraの制約

`MenuBarExtra`は以下の操作に対応していない:

| 制約 | 詳細 |
|------|------|
| 右クリックメニュー | `MenuBarExtra`は左クリックのみハンドル |
| 動的なアイコン更新 | `Label`内のSF Symbolsは更新可能だが、カスタムNSImageの直接制御は不可 |
| ドラッグ&ドロップ | メニューバーアイテムへのドロップ非対応 |

### NSStatusItemが必要なケース

MVP段階では`MenuBarExtra`で十分だが、以下の拡張で`NSStatusItem`への移行を検討:

- **右クリックでクイックアクション**: 右クリック → 設定画面、左クリック → ポップオーバーの使い分け
- **カスタムレンダリング**: メニューバーアイコンにミニゲージを直接描画する場合
- **ドラッグ操作**: 将来的なウィジェット連携等

移行時は`NSStatusItem` + `NSPopover`の組み合わせで、SwiftUIビューを`NSHostingView`でラップする:

```swift
let popover = NSPopover()
popover.contentViewController = NSHostingController(rootView: PopoverView())
popover.behavior = .transient
```

---

## ファイル監視

### FSEvents / DispatchSourceによるリアルタイム更新

collectorが`~/.claude/claude-usage-bar/`に書き出すJSONファイルの変更を検知し、メニューバー表示をリアルタイムに更新する。

```swift
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?

    func watch(directory: URL) {
        let fd = open(directory.path, O_EVTONLY)
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        source?.setEventHandler { [weak self] in
            self?.reloadSessionData()
        }
        source?.setCancelHandler {
            close(fd)
        }
        source?.resume()
    }
}
```

| 項目 | 詳細 |
|------|------|
| 監視対象 | `~/.claude/claude-usage-bar/sessions/` ディレクトリ |
| イベント | `.write`（ファイル書き込み完了） |
| 反応速度 | ほぼ即時（ファイルシステムイベント駆動） |
| リソース消費 | 極小（カーネルイベント待ち、CPU消費なし） |

セッションファイルは`sessions/`サブディレクトリに保存されるため、監視対象は親ディレクトリではなく`sessions/`を直接指定する。親ディレクトリ（`~/.claude/claude-usage-bar/`）を監視すると`backup/`やログファイルの変更でも不要な再読み込みが発生する。

### ポーリング間隔（フォールバック）

FSEventsが利用できない環境（ネットワークマウント等）向けのフォールバック:

| 項目 | 詳細 |
|------|------|
| 間隔 | 30秒 |
| 方式 | `Timer.publish`によるファイルタイムスタンプ確認 |
| 切り替え条件 | FSEventsソース作成失敗時に自動フォールバック |

```swift
Timer.publish(every: 30, on: .main, in: .common)
    .autoconnect()
    .sink { [weak self] _ in
        self?.checkFileTimestamp()
    }
```

---

## 状態管理

### @Observable / ObservableObject

アプリの状態管理には`@Observable`マクロ（macOS 14+）を使用する。

```swift
@Observable
final class UsageViewModel {
    var fiveHourPercentage: Double?
    var sevenDayPercentage: Double?
    var fiveHourResetsAt: Date?
    var sevenDayResetsAt: Date?
    var contextPercentage: Double?
    var model: String?
    var sessionID: String?
    var lastUpdate: Date?
    var displayMode: DisplayMode = .standard
}
```

| 項目 | 詳細 |
|------|------|
| マクロ | `@Observable`（macOS 14+ / Observation framework） |
| フォールバック | `ObservableObject` + `@Published`（macOS 13互換が必要な場合） |
| スレッド安全性 | メインスレッドでの状態更新を保証（`@MainActor`） |

macOS 13互換が不要な場合（最低対象がmacOS 14 Sonoma）、`@Observable`を優先する。`@Observable`は`@Published`と比べてビューの再描画が効率的。

### セッションデータのマージロジック

複数のClaude Codeセッションが同時に稼働する場合、以下のロジックで表示データを決定する:

1. `~/.claude/claude-usage-bar/sessions/`内の全セッションJSONを読み込み
2. `rate_limits`を持つセッションのうち、最も新しい`updated_at`を持つものを選択
3. `context_window`と`cost`はセッションごとに個別表示（ポップオーバーのセッション一覧）
4. `rate_limits`はアカウント単位で共通のため、最新データを1つ表示

```swift
func selectLatestRateLimits(sessions: [SessionSnapshot]) -> RateLimits? {
    sessions
        .filter { $0.rateLimits != nil }
        .max(by: { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) })
        .flatMap(\.rateLimits)
}
```

---

## ライフサイクル

### Launch at Login（SMAppService）

ログイン時にアプリを自動起動する。ユーザーが設定から有効/無効を切り替え可能。

```swift
import ServiceManagement

func setLaunchAtLogin(_ enabled: Bool) {
    if enabled {
        try? SMAppService.mainApp.register()
    } else {
        try? SMAppService.mainApp.unregister()
    }
}
```

登録状態はシステム環境設定の「一般 > ログイン項目」に反映される。`UserDefaults`にも設定値を保存し、UIの表示と同期する。

### バックグラウンド動作（LSUIElement）

`Info.plist`に`LSUIElement = true`を設定し、Dockアイコンを非表示にする。

| 項目 | 詳細 |
|------|------|
| Dockアイコン | 非表示 |
| メニューバー | 表示（`MenuBarExtra`で管理） |
| Cmd+Tab | 表示されない |
| アプリ終了 | メニューバーのコンテキストメニューまたはActivity Monitor |

アプリの終了手段として、ポップオーバー下部に「終了」ボタンを配置する。

### メモリ使用量の管理

常駐アプリとして長時間稼働するため、メモリ使用量を最小限に抑える。

| 対策 | 詳細 |
|------|------|
| 目標メモリ | 20MB以下（アイドル時） |
| セッションデータ | 最新N件のみ保持、古いデータはディスクに残すがメモリから解放 |
| ポップオーバー | 閉じた際にビュー階層を解放（`@State`のリセット） |
| 画像キャッシュ | SF Symbolsのみ使用、カスタム画像なし |

メモリ使用量が異常に増加した場合のセルフヒーリング:

```swift
func didReceiveMemoryWarning() {
    sessionCache.removeAll()
    reloadLatestOnly()
}
```

---

## 通知

### UserNotifications

使用率が閾値を超えた際にmacOS通知を送信する。

```swift
import UserNotifications

func requestNotificationPermission() {
    UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .sound]) { granted, error in
            // 権限の結果をUserDefaultsに保存
        }
}
```

### 閾値設定（70/85/95%）

| 閾値 | 通知タイトル | 備考 |
|------|------------|------|
| 70% | Claude Code 使用率 | 注意レベル |
| 85% | Claude Code 使用率（警告） | 警告レベル |
| 95% | Claude Code 使用率（危険） | 危険レベル |

通知の制御ロジック:

- 各閾値につき、同一リセット期間内で1回のみ通知
- `resets_at`が更新されたら閾値カウンターをリセット
- 5時間枠と7日枠を独立に追跡
- ユーザーが設定で各閾値を個別に有効/無効化可能

```swift
struct ThresholdTracker {
    var notifiedThresholds: Set<Int> = []
    var lastResetsAt: Date?

    mutating func shouldNotify(percentage: Double, resetsAt: Date) -> Int? {
        if lastResetsAt != resetsAt {
            notifiedThresholds.removeAll()
            lastResetsAt = resetsAt
        }
        for threshold in [95, 85, 70] {
            if percentage >= Double(threshold) && !notifiedThresholds.contains(threshold) {
                notifiedThresholds.insert(threshold)
                return threshold
            }
        }
        return nil
    }
}
```

---

## 関連リンク

- [UX設計（画面設計の詳細）](ux-design.md)
- [アーキテクチャ（コンポーネント間通信）](architecture.md)
- [データスキーマ（読み込むデータの形式）](data-schema.md)
- [技術選定の根拠](tech-decisions.md)
