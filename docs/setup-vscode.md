# VS Code セットアップ: コーディングエージェント & ログ解析

前提: オフィス回線 or 会社 VPN に接続していること（IP allowlist 制限。自宅回線は直接接続不可）。

## 1. キーの取得

```bash
az keyvault secret show --vault-name <KV名> --name editor-openai-key --query value -o tsv | pbcopy
```

**キーは毎週月曜 09:00 にローテーションされる。** Teams 通知を受けたら 1 週間以内に再設定。

## 2-A. GitHub Copilot（BYOK: Bring Your Own Key）

1. Copilot Chat → モデルピッカー → **Manage Models...**
2. プロバイダに **Azure** を選択
3. エンドポイントに `https://<resource>.openai.azure.com/openai/v1/`、API キーを入力
4. deployment 名（`agent-main` / `log-analysis`）をモデルとして追加

以後、チャットのモデルピッカーで用途に応じて切り替える。
システムプロンプトを効かせたい場合はワークスペースの `.github/copilot-instructions.md` に
[prompts/coding-agent.md](../prompts/coding-agent.md) の本文を置く。

## 2-B. Continue 拡張

`~/.continue/config.yaml`:

```yaml
models:
  - name: 社内: コーディングエージェント
    provider: azure
    model: agent-main            # deployment 名
    apiBase: https://<resource>.openai.azure.com/openai/v1/
    apiKey: <ここには書かず、環境変数か Continue の secrets 機能を使う>
    systemMessage: |
      # prompts/coding-agent.md の本文を貼る
  - name: 社内: ログ解析
    provider: azure
    model: log-analysis
    apiBase: https://<resource>.openai.azure.com/openai/v1/
    apiKey: <同上>
    systemMessage: |
      # prompts/log-analysis.md の本文を貼る
```

**キーの平文を設定ファイルに書かない**（利用規約違反）。Continue の secrets / 環境変数参照を使う。

## 3. トラブルシュート

[setup-zed.md](setup-zed.md) §4 と同じ（403 = IP、401 = キー失効 or ハードリミット発動）。
