# VS Code セットアップ: コーディングエージェント & ログ解析

前提: オフィス回線 or 会社 VPN に接続していること（IP allowlist 制限。自宅回線は直接接続不可）。

## 1. キーの取得

**Teams のローテ通知に記載された「新しいキー」をコピーする**（毎週月曜 09:00 に自動投稿）。
Azure アクセスがあれば Key Vault から直接取得も可:
```bash
az keyvault secret show --vault-name <KV名> --name editor-openai-key --query value -o tsv | pbcopy
```

**キーは毎週月曜 09:00 にローテーションされる。** Teams 通知の新キーで 1 週間以内に再設定。

## 2-A. GitHub Copilot（BYOK: Bring Your Own Key）

1. Copilot Chat → モデルピッカー → **Manage Models...**
2. プロバイダに **Azure** を選択
3. エンドポイントに `https://<resource>.openai.azure.com/openai/v1/`、API キーを入力
4. deployment 名をモデルとして追加: `gpt5-apac`（既定・主力）。
   フェーズ2で `deepseek-apac`（非OpenAI）も同一エンドポイントで追加可。いずれも APAC 処理

以後、チャットのモデルピッカーで用途・機微度に応じて切り替える（`-apac` は越境）。
システムプロンプトを効かせたい場合はワークスペースの `.github/copilot-instructions.md` に
[prompts/coding-agent.md](../prompts/coding-agent.md) の本文を置く。

## 2-B. Continue 拡張

`~/.continue/config.yaml`:

```yaml
models:
  - name: 社内: GPT-5.2(APAC)
    provider: azure
    model: gpt5-apac       # deployment 名。既定・主力(gpt-5.2)。APAC 処理
    apiBase: https://<resource>.openai.azure.com/openai/v1/
    apiKey: <ここには書かず、環境変数か Continue の secrets 機能を使う>
    systemMessage: |
      # prompts/coding-agent.md の本文を貼る
  # フェーズ2で追加（非 OpenAI も同一エンドポイントで可）:
  # - name: 社内: DeepSeek(APAC)
  #   provider: azure
  #   model: deepseek-apac
  #   apiBase: https://<resource>.openai.azure.com/openai/v1/
  #   apiKey: <同上>
```

ログ解析も既定の `gpt5-apac`（gpt-5.2）を使う。`systemMessage` に
[prompts/log-analysis.md](../prompts/log-analysis.md) を貼ったエントリを別途用意する。

**キーの平文を設定ファイルに書かない**（利用規約違反）。Continue の secrets / 環境変数参照を使う。

## 3. トラブルシュート

[setup-zed.md](setup-zed.md) §4 と同じ（403 = IP、401 = キー失効 or ハードリミット発動）。
