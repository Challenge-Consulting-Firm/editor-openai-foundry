# VS Code セットアップ: コーディングエージェント & ログ解析

社内 Azure AI Foundry エンドポイントを VS Code から使う手順。方法は 2 つあり、**どちらか一方で良い**:

| 方法 | 向いている人 | 特徴 |
|---|---|---|
| **A. GitHub Copilot (BYOK)** | 既に Copilot を使っている人 | Copilot Chat のモデルピッカーに社内モデルが並ぶ。設定は UI から数分 |
| **B. Continue 拡張** | Copilot ライセンスが無い人 | 無料の OSS 拡張。システムプロンプトをモデルごとに固定できる |

## 0. 前提

- **オフィス回線 or 会社 VPN に接続していること**（IP allowlist 制限。自宅回線・モバイル回線からは 403 になる）
- 接続情報（運用者からの案内。以下は現行環境の値）:
  - リソース名: `editor-aoai-sbovt55sy6ujk`
  - エンドポイント（v1）: `https://editor-aoai-sbovt55sy6ujk.openai.azure.com/openai/v1`
  - deployment 名: `gpt5-apac`（gpt-5.2 / APAC 処理）

## 1. API キーの取得

**Teams のローテ通知に記載された「新しいキー」をコピーする**（毎週月曜 09:00 に自動投稿）。

Azure にアクセスできる場合は Key Vault から直接取得してもよい:

```bash
az keyvault secret show --vault-name kv-editor-aoai-sbovt55sy --name editor-openai-key --query value -o tsv | pbcopy
```

> **キーは毎週月曜 09:00 JST に自動ローテーションされる。** 旧キーは 1 週間で失効するため、
> Teams 通知が来たら本ページ「5. キーローテーション時の更新」の手順で貼り替えること。

---

## 2-A. 方法A: GitHub Copilot（BYOK: Bring Your Own Key）

### 手順（UI から）

1. Copilot Chat パネルを開く（`⌃⌘I` / `Ctrl+Alt+I`）
2. チャット入力欄の**モデルピッカー**（現在のモデル名が表示されている部分）をクリック → **「Manage Models...」**
   - またはコマンドパレット（`⇧⌘P`）→ **「Chat: Manage Language Models」**
3. プロバイダ一覧から **「Azure」** を選択
4. **モデル ID** を聞かれたら **deployment 名 `gpt5-apac`** を入力
   （⚠️ モデル ID `gpt-5.2` ではなく deployment 名。間違えると 404）
5. **デプロイメント URL** を聞かれたら **chat/completions までの完全 URL** を入力:
   ```
   https://editor-aoai-sbovt55sy6ujk.openai.azure.com/openai/v1/chat/completions
   ```
6. **API キー**を貼り付け（手順 1 で取得したもの）
7. capabilities を聞かれたら: **tool calling = 有効 / vision = 無効**、トークン上限は既定のままで可
8. モデルピッカーに `gpt5-apac` が並ぶので選択して利用開始

### settings.json で宣言的に設定する場合（任意）

UI の代わりに `github.copilot.chat.azureModels` でも定義できる（**キーはここに書かない**。初回利用時に UI で聞かれる）:

```jsonc
"github.copilot.chat.azureModels": {
  "gpt5-apac": {
    "name": "社内: GPT-5.2 (APAC)",
    "url": "https://editor-aoai-sbovt55sy6ujk.openai.azure.com/openai/v1/chat/completions",
    "maxInputTokens": 128000,
    "maxOutputTokens": 16000,
    "toolCalling": true,
    "vision": false,
    "thinking": true   // GPT-5 系は reasoning モデル。max_tokens 400 が出る場合に有効化
  }
}
```

### Copilot BYOK の注意

- **Responses API 専用モデル（gpt-5.3-codex 等）は BYOK で使えない**（BYOK は Chat Completions のみ対応）。
  本基盤の `gpt5-apac`（gpt-5.2）は Chat Completions 対応なので問題ない
- 認証は **API キーのみ**（Entra ID 不可）— 本基盤の設計と一致
- 組織プランの場合、BYOK は管理者側で有効化が必要なことがある（Enterprise/Business は組織ポリシー依存）

---

## 2-B. 方法B: Continue 拡張

### インストールと設定ファイル

1. 拡張機能で **「Continue」** を検索してインストール
2. サイドバーの Continue アイコン → 右上の **歯車（⚙）→「Open Config File」** で `~/.continue/config.yaml` を開く

### config.yaml（そのまま貼って `<APIキー>` 部分だけ差し替え）

```yaml
models:
  - name: 社内 GPT-5.2 コーディング (APAC)
    provider: azure
    model: gpt-5.2            # ← モデル名。"gpt-5" を含む名前にすること（下記の重要事項）
    apiBase: https://editor-aoai-sbovt55sy6ujk.openai.azure.com
    apiKey: ${{ secrets.AZURE_FOUNDRY_KEY }}   # キーの直書き禁止（後述）
    env:
      deployment: gpt5-apac   # ← 実際の deployment 名はこちらに書く
      apiType: azure-openai
      apiVersion: 2024-10-21
    roles: [chat, edit, apply]
    systemMessage: |
      # prompts/coding-agent.md の本文を貼る

  - name: 社内 GPT-5.2 ログ解析 (APAC)
    provider: azure
    model: gpt-5.2
    apiBase: https://editor-aoai-sbovt55sy6ujk.openai.azure.com
    apiKey: ${{ secrets.AZURE_FOUNDRY_KEY }}
    env:
      deployment: gpt5-apac
      apiType: azure-openai
      apiVersion: 2024-10-21
    roles: [chat]
    systemMessage: |
      # prompts/log-analysis.md の本文を貼る
```

### ⚠️ 重要: `model` と `env.deployment` を分けて書く理由

- Continue は **`model` 名に "gpt-5" が含まれるかどうか**で、GPT-5 系が要求する
  `max_completion_tokens` への変換を行う（[continue#7052](https://github.com/continuedev/continue/issues/7052)）
- `model: gpt5-apac` のように deployment 名だけを書くと変換されず、
  **400「Unsupported parameter: 'max_tokens'」**で失敗する
- そのため **`model` にはモデル名 `gpt-5.2`、`env.deployment` に deployment 名 `gpt5-apac`** を書く
- Continue が古いと GPT-5 検出自体が無いことがある → **拡張を最新に更新**しておく

### キーの安全な設定（直書き禁止）

`config.yaml` にキーの平文を書くのは**利用規約違反**（dotfiles 同期や誤コミットで漏れるため）。どちらかで:

- **Continue の secrets 機能**: 上記例の `${{ secrets.AZURE_FOUNDRY_KEY }}` 参照を使い、
  Continue の設定 UI（歯車 → Secrets）で `AZURE_FOUNDRY_KEY` に値を登録する
- **ローカル環境変数**: `~/.zshrc` 等ではなく、シェル履歴に残らない方法で設定した環境変数を参照する

---

## 3. 動作確認

1. チャットに「こんにちは」と送って応答が返ること
2. コードブロックを選択 → チャットで「この関数を説明して」が動くこと
3. 応答が返らない場合は下のトラブルシュートへ

## 4. トラブルシュート

| 症状 | 原因 | 対処 |
|---|---|---|
| 403 | 接続元 IP が allowlist 外 | `curl ifconfig.me` で自 IP 確認。オフィス回線 / VPN に切替 |
| 401 | 旧キー失効 | 手順 1 で最新キーを取得して再設定 |
| 401（全員・突然） | ハードリミット発動 | Teams の発動通知を確認。復旧を待つ |
| 400 `Unsupported parameter: 'max_tokens'` | クライアントが旧パラメータを送信 | Copilot: `thinking: true` を設定 / Continue: `model` に `gpt-5.2` を書く（上記）+ 拡張を最新化 |
| 404 `deployment does not exist` | deployment 名の誤り | `gpt5-apac` を指定（モデル ID `gpt-5.2` を URL/モデルIDに使わない） |
| Copilot にモデルが出ない | BYOK 未対応プラン / 組織ポリシー | 個人プラン(Free/Pro/Pro+)は利用可。組織プランは管理者に確認 |

## 5. キーローテーション時の更新（毎週）

Teams のローテ通知（毎週月曜 09:00）に新しいキーが記載される。

- **Copilot**: モデルピッカー → Manage Models... → Azure の鍵マーク（API キー再入力）→ 新キーを貼り替え
- **Continue**: 歯車 → Secrets → `AZURE_FOUNDRY_KEY` の値を新キーに更新（環境変数方式ならそちらを更新）

旧キーは次回ローテーション（1 週間後）まで有効なので、失効前に更新すれば作業が中断することはない。
