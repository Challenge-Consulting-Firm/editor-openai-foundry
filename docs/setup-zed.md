# Zed セットアップ: コーディングエージェント & ログ解析

前提: オフィス回線 or 会社 VPN に接続していること（IP allowlist 制限。自宅回線は直接接続不可）。

## 1. キーの取得

```bash
az keyvault secret show --vault-name <KV名> --name editor-openai-key --query value -o tsv | pbcopy
```

**キーは毎週月曜 09:00 にローテーションされる。** Teams 通知を受けたら 1 週間以内に再設定
（旧キーは次回ローテで失効）。

## 2. OpenAI 互換プロバイダの登録

Settings → AI → LLM Providers → **Add OpenAI-compatible provider**、または `settings.json`:

```jsonc
{
  "language_models": {
    "openai_compatible": {
      "社内 Azure OpenAI": {
        "api_url": "https://<resource>.openai.azure.com/openai/v1",
        "available_models": [
          {
            "name": "agent-main",        // deployment 名をそのまま指定
            "display_name": "社内: コーディングエージェント",
            "max_tokens": 128000
          },
          {
            "name": "log-analysis",
            "display_name": "社内: ログ解析",
            "max_tokens": 128000
          }
        ]
      }
    }
  }
}
```

- API キーは **UI から入力**（macOS keychain に保管される）。
  **`settings.json` や dotfiles にキーを書かない**（利用規約違反）
- `api_url` の `<resource>` はリソース名（運用者の案内 or `main.bicep` 出力 `openAiV1BaseUrl` 参照）

## 3. 用途別プロファイルの作成

Agent Panel → プロファイル切替 → 用途ごとにモデルとシステムプロンプトを割り当てる:

| プロファイル | モデル | システムプロンプト |
|---|---|---|
| コーディング | `agent-main` | [prompts/coding-agent.md](../prompts/coding-agent.md) の本文 |
| ログ解析 | `log-analysis` | [prompts/log-analysis.md](../prompts/log-analysis.md) の本文 |

プロジェクト単位でコーディング規約を効かせたい場合は、リポジトリ直下の `.rules` に
coding-agent.md の内容を置いてもよい（Zed が自動で読み込む）。

## 4. トラブルシュート

| 症状 | 原因 | 対処 |
|---|---|---|
| 403 | 接続元 IP が allowlist 外 | `curl ifconfig.me` で自 IP 確認。オフィス回線 / VPN に切替 |
| 401 | 旧キー失効 | 手順 1 で最新キーを取得して再設定 |
| 401（全員・突然） | ハードリミット発動 | Teams の発動通知を確認。復旧を待つ |
| モデルが見つからない | deployment 名の typo | `agent-main` / `log-analysis` を確認 |
