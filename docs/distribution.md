# 配布・運用

claude-code-usage-barの署名、公証、配布チャネル、自動更新、CI/CDパイプライン、およびシステム要件を定義する。

---

## 署名とnotarization

macOS Gatekeeper を通過し、ユーザーがダウンロード後に即座に起動できるようにするため、Developer ID署名とApple notarizationが必須となる。

### Developer ID Application証明書

| 項目 | 値 |
|------|-----|
| 証明書タイプ | Developer ID Application |
| 用途 | Mac App Store外で配布するアプリへの署名 |
| 発行元 | Apple Developer Program（年額$99） |
| 署名対象 | アプリ本体（`.app`）、collector CLIバイナリ、埋め込みフレームワーク |

署名時の注意点:

- アプリバンドル内のすべての実行可能バイナリに署名が必要（collector CLIを含む）
- `--deep` オプションではなく、個別バイナリに対して明示的に署名する
- `codesign --verify --deep --strict` で署名の整合性を検証する

### notarizationワークフロー（xcrun notarytool）

```bash
# 1. アーカイブをZIPまたはDMGにパッケージ
ditto -c -k --keepParent "claude-code-usage-bar.app" "claude-code-usage-bar.zip"

# 2. notarizationに提出
xcrun notarytool submit "claude-code-usage-bar.zip" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_SPECIFIC_PASSWORD" \
  --wait

# 3. staple（オフライン検証用にチケットを埋め込み）
xcrun stapler staple "claude-code-usage-bar.app"
```

`--wait` オプションにより、notarizationの完了を同期的に待機する。CI/CD環境ではタイムアウト設定（`--timeout`）を併用する。

### Hardened Runtime設定

| 設定 | 値 | 理由 |
|------|-----|------|
| Hardened Runtime | 有効 | notarizationの必須要件 |
| `com.apple.security.app-sandbox` | **無効** | `~/.claude/`への常時アクセスが必要（Sandboxでは`user-selected`のみでは不十分） |
| `com.apple.security.network.client` | 有効（Sparkle更新チェックのみ） | Sparkle 2による自動更新に必要 |

**App Sandboxを無効とする理由**: 本アプリはcollectorが`~/.claude/settings.json`を読み書きし、`~/.claude/claude-usage-bar/`配下にセッションデータを常時書き込む。App Sandboxの`files.user-selected.read-write` entitlementではユーザーが明示的に選択したファイルにしかアクセスできず、バックグラウンドでの自動ファイル操作が不可能。そのため、Sandbox無効 + Developer ID署名による配布（Mac App Store外）を前提とする。

ネットワーク通信は自動更新（Sparkle 2のappcast.xmlチェック）のみに限定される。Claude.aiや外部サービスへの接続は行わない。

---

## 配布形式

### DMGパッケージ

主要な配布形式としてDMG（ディスクイメージ）を採用する。

| 項目 | 詳細 |
|------|------|
| 形式 | `.dmg`（UDZO圧縮） |
| 内容 | `claude-code-usage-bar.app` + Applicationsフォルダへのシンボリックリンク |
| 署名 | DMG自体にもDeveloper ID署名を付与 |
| notarization | DMGごとnotarizationしstaple |

```bash
# DMG作成例（create-dmg使用）
create-dmg \
  --volname "claude-code-usage-bar" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --app-drop-link 425 178 \
  "claude-code-usage-bar.dmg" \
  "build/"
```

### Homebrew Cask

広く普及しているパッケージマネージャによるインストールをサポートする。

```ruby
cask "claude-code-usage-bar" do
  version "1.0.0"
  sha256 "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

  url "https://github.com/user/claude-code-usage-bar/releases/download/v#{version}/claude-code-usage-bar-#{version}.dmg"
  name "claude-code-usage-bar"
  desc "Claude Code usage rate monitor for macOS menu bar"
  homepage "https://github.com/user/claude-code-usage-bar"

  depends_on macos: ">= :ventura"

  app "claude-code-usage-bar.app"

  zap trash: [
    "~/.claude/claude-usage-bar/",
    "~/Library/Preferences/com.example.claude-code-usage-bar.plist",
    "~/Library/Caches/com.example.claude-code-usage-bar",
  ]
end
```

インストール・アンインストール:

```bash
# インストール
brew install --cask claude-code-usage-bar

# アンインストール（データも含めて完全削除）
brew uninstall --zap --cask claude-code-usage-bar
```

`zap` スタンザにより、アンインストール時にcollectorが書き出したデータ（`~/.claude/claude-usage-bar/`）や設定ファイルも削除される。`settings.json` への変更（`statusLine` ラッパー登録）のクリーンアップはアプリ側のアンインストーラ機能で対応する。

---

## 自動更新

### Sparkle Framework

| 項目 | 詳細 |
|------|-----|
| フレームワーク | [Sparkle 2.x](https://sparkle-project.org/) |
| プロトコル | EdDSA署名（Sparkle 2標準） |
| チェック間隔 | 24時間ごと（ユーザー変更可能） |
| UI | 標準のSparkle更新ダイアログ |

Sparkleはnotarization済みアプリの更新に対応しており、macOSネイティブアプリの自動更新デファクトスタンダードである。

注意: Sparkleの更新チェックはアプリ内で唯一のネットワーク通信となる。`com.apple.security.network.client` entitlementはSparkle用に限定的に許可するか、Sparkleを埋め込まずHomebrew Cask経由の更新のみとする設計も検討する。

### appcast.xml

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>claude-code-usage-bar</title>
    <item>
      <title>Version 1.0.1</title>
      <sparkle:version>1.0.1</sparkle:version>
      <sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <pubDate>Sun, 20 Apr 2026 00:00:00 +0000</pubDate>
      <enclosure
        url="https://github.com/user/claude-code-usage-bar/releases/download/v1.0.1/claude-code-usage-bar-1.0.1.dmg"
        sparkle:edSignature="..."
        length="12345678"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
```

appcast.xmlはGitHub Releasesと同じリポジトリまたはGitHub Pagesでホストする。

### Delta updates

Sparkle 2はバイナリ差分更新（delta updates）をサポートする。

| 更新方式 | サイズ | 適用条件 |
|---------|--------|---------|
| フルアップデート | DMG全体（数十MB） | 常に利用可能 |
| Delta update | 差分のみ（数MB） | 直前バージョンからの更新時 |

Delta updatesの生成:

```bash
# Sparkle付属のgenerate_appcastツールで自動生成
./bin/generate_appcast --ed-key-file ed25519_key ./releases/
```

MVPではフルアップデートのみで十分。Delta updatesはユーザーベース拡大後に導入を検討する。

---

## CI/CD

### Xcode Cloud / GitHub Actions

GitHub Actionsを主要CI/CDプラットフォームとして採用する。

| 項目 | 選定 | 理由 |
|------|------|------|
| CI/CD | GitHub Actions | リポジトリ統合、macOSランナー利用可能 |
| 代替案 | Xcode Cloud | Apple統合は良いが、スクリプトの柔軟性でGitHub Actionsが優位 |

### 自動署名+notarization

GitHub Actionsワークフローの概要:

```yaml
name: Build and Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Import certificates
        uses: apple-actions/import-codesign-certs@v2
        with:
          p12-file-base64: ${{ secrets.CERTIFICATES_P12 }}
          p12-password: ${{ secrets.CERTIFICATES_PASSWORD }}

      - name: Build
        run: |
          xcodebuild -scheme claude-code-usage-bar \
            -configuration Release \
            -archivePath build/claude-code-usage-bar.xcarchive \
            archive

      - name: Export
        run: |
          xcodebuild -exportArchive \
            -archivePath build/claude-code-usage-bar.xcarchive \
            -exportOptionsPlist ExportOptions.plist \
            -exportPath build/

      - name: Notarize
        run: |
          xcrun notarytool submit build/claude-code-usage-bar.dmg \
            --apple-id "${{ secrets.APPLE_ID }}" \
            --team-id "${{ secrets.TEAM_ID }}" \
            --password "${{ secrets.APP_SPECIFIC_PASSWORD }}" \
            --wait --timeout 600

          xcrun stapler staple build/claude-code-usage-bar.dmg

      - name: Upload to GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: build/claude-code-usage-bar.dmg
```

### リリースフロー

```
1. バージョンタグをpush（git tag v1.0.1 && git push --tags）
    ↓
2. GitHub Actionsが起動
    ↓
3. ビルド → 署名 → notarization → staple
    ↓
4. DMGをGitHub Releaseにアップロード
    ↓
5. appcast.xmlを更新（generate_appcast）
    ↓
6. Homebrew Caskのバージョン・SHA256を更新（PR）
```

Secrets管理:

| Secret | 内容 |
|--------|------|
| `CERTIFICATES_P12` | Developer ID証明書（Base64エンコード） |
| `CERTIFICATES_PASSWORD` | P12ファイルのパスワード |
| `APPLE_ID` | Apple ID（notarization用） |
| `TEAM_ID` | Apple Developer Team ID |
| `APP_SPECIFIC_PASSWORD` | App用パスワード（notarization用） |

---

## システム要件

### macOS最低バージョン（14.0 Sonoma推奨）

| 要件 | 最低バージョン | 推奨バージョン | 理由 |
|------|-------------|-------------|------|
| macOS | 13.0 Ventura | 14.0 Sonoma | `MenuBarExtra` は13.0で導入、14.0で安定性向上 |
| Swift | 5.9以上 | 6.0以上 | `@Observable` マクロ（macOS 14+）、Swift Testing |
| Xcode | 15.0以上 | 16.0以上 | macOS 14 SDK、Swift 6対応 |

macOS 13.0 Venturaを最低バージョンとする根拠:

- **MenuBarExtra**: macOS 13.0で導入されたSwiftUI API。本アプリの中核コンポーネント
- **SMAppService**: macOS 13.0で導入。Login Items管理に必要
- **推奨14.0の理由**: `@Observable` マクロ（Swift 5.9 / macOS 14）による簡潔な状態管理、`MenuBarExtra` の安定性向上
- **macOS 13対応時の注意**: `@Observable` が使えないため `ObservableObject` / `@Published` でフォールバック実装が必要

### Apple Silicon / Intel対応

| アーキテクチャ | 対応 | 備考 |
|--------------|------|------|
| Apple Silicon (arm64) | 必須 | M3 Ultraが主要ターゲット |
| Intel (x86_64) | Universal Binary | Rosetta 2なしでネイティブ動作 |

Universal Binaryとしてビルドし、Apple Silicon / Intel両方でネイティブ動作させる。

```bash
# Universal Binary ビルド
xcodebuild -scheme claude-code-usage-bar \
  -configuration Release \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" \
  build
```

主要ターゲットはApple Silicon（特にM3 Ultra）だが、Intel Macユーザーもclaude-code-usage-barを利用できるようUniversal Binaryで配布する。バイナリサイズの増加は軽微（数MB程度）。

---

## 関連リンク

- [技術選定](tech-decisions.md)
- [実装ベストプラクティス](best-practices.md)
- [概要・前提](overview.md)
- [アーキテクチャ](architecture.md)
