# Zed セットアップ: コーディングエージェント & ログ解析

前提: オフィス回線 or 会社 VPN に接続していること（IP allowlist 制限。自宅回線は直接接続不可）。

## 1. キーの取得

**Teams のローテ通知に記載された「新しいキー」をコピーする**（毎週月曜 09:00 に自動投稿）。

Azure にアクセスできる場合は Key Vault から直接取得してもよい:
```bash
az keyvault secret show --vault-name <KV名> --name editor-openai-key --query value -o tsv | pbcopy
```

**キーは毎週月曜 09:00 にローテーションされる。** Teams 通知の新キーで 1 週間以内に再設定
（旧キーは次回ローテで失効）。

## 2. OpenAI 互換プロバイダの登録

Settings → AI → LLM Providers → **Add OpenAI-compatible provider**、または `settings.json`:

OpenAI / 非 OpenAI（DeepSeek 等）とも**同じ 1 プロバイダ**に登録できる（全モデル共通の `openai/v1` エンドポイント）。
`name` は deployment 名をそのまま指定する。`-apac`=APAC 処理（越境）。
※ 現状は全モデルが `-apac`（国内完結は対応モデルが提供終了中のため不可。保管は日本国内）。

```jsonc
{
  "language_models": {
    "openai_compatible": {
      "社内 Foundry": {
        "api_url": "https://<resource>.openai.azure.com/openai/v1",  // 末尾スラッシュなし
        "available_models": [
          {
            "name": "gpt5-apac",      // 必ず deployment 名（モデル名 "gpt-5.2" だと 404）
            "display_name": "社内: GPT-5.2(APAC)",
            "max_tokens": 200000,
            "max_output_tokens": 32000,
            "max_completion_tokens": 200000,
            "capabilities": {
              "tools": true,
              "images": false,
              "parallel_tool_calls": false,
              "prompt_cache_key": false,
              "chat_completions": true,
              // ★必須★ GPT-5 系は旧 max_tokens パラメータを拒否（HTTP 400）するため、
              // false にして Zed に max_completion_tokens を送らせる
              "max_tokens_parameter": false
            }
          }
          // フェーズ2で deepseek-apac 等を追加したら、ここに同形式で足す
        ]
      }
    }
  }
}
```

- **`capabilities.max_tokens_parameter: false` は GPT-5 系で必須**。無いと
  「Azure Foundry's API returned an unexpected error」（実体は 400: Unsupported parameter 'max_tokens'）になる
- **`name` は deployment 名**（`gpt5-apac`）。モデル ID（`gpt-5.2`）を書くと 404 DeploymentNotFound
- API キーは **UI から入力**（macOS keychain に保管される）。
  **`settings.json` や dotfiles にキーを書かない**（利用規約違反）
- `api_url` の `<resource>` はリソース名（運用者の案内 or `main.bicep` 出力 `openAiV1BaseUrl` 参照）
- **display_name に処理範囲を明記**し、越境モデルを選んでいることが分かるようにする（利用規約）

## 3. 用途別プロファイルの作成

Agent Panel → プロファイル切替 → 用途ごとにモデルとシステムプロンプトを割り当てる。
モデルは性能要件で選ぶ（現状は全て APAC 処理。国内完結モデルが出たら機微データはそちらを優先）:

| プロファイル | 推奨モデル | システムプロンプト |
|---|---|---|
| コーディング（既定） | `gpt5-apac` | [prompts/coding-agent.md](../prompts/coding-agent.md) の本文 |
| ログ解析 | `gpt5-apac` | [prompts/log-analysis.md](../prompts/log-analysis.md) の本文 |
| （フェーズ2）代替コーディング | `deepseek-apac` | coding-agent.md 同上 |

プロジェクト単位でコーディング規約を効かせたい場合は、リポジトリ直下の `.rules` に
coding-agent.md の内容を置いてもよい（Zed が自動で読み込む）。

## 4. トラブルシュート

| 症状 | 原因 | 対処 |
|---|---|---|
| 403 | 接続元 IP が allowlist 外 | `curl ifconfig.me` で自 IP 確認。オフィス回線 / VPN に切替 |
| 401 | 旧キー失効 | 手順 1 で最新キーを取得して再設定 |
| 401（全員・突然） | ハードリミット発動 | Teams の発動通知を確認。復旧を待つ |
| unexpected error | Zed が `max_tokens` を送っている（GPT-5 系は 400 で拒否） | モデル設定に `"capabilities": {"max_tokens_parameter": false}` を追加（手順 2） |
| 404 / モデルが見つからない | `name` にモデル ID を書いている | `name` は deployment 名 `gpt5-apac`（P2で `deepseek-apac`） |
