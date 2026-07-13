# Runbook: キーローテーション運用

**通常運用**: 毎週月曜 09:00 JST に `rotate_key` Function が自動実行。
key1/key2 を交互に regenerate し、新キーを Key Vault `editor-openai-key` へ保存、Teams へ通知。
**旧キーは次回ローテーションまで 1 週間有効**（無停止ローテーション）。

## 利用者向け: キーの更新手順

Teams のローテーション通知を受けたら **1 週間以内**に更新する。**通知本文に新しいキーが記載**されているので、
それをコピーしてエディタのキー設定を貼り替える（[setup-zed.md](setup-zed.md) / [setup-vscode.md](setup-vscode.md)）。

Azure にアクセスできる場合は Key Vault から直接取得してもよい:
```bash
az keyvault secret show --vault-name <KV名> --name editor-openai-key --query value -o tsv | pbcopy
```

突然 401 になった場合 → 更新を忘れて旧キーが失効した可能性が高い。上記手順で最新キーを取得する。

## 運用者向け: 失敗時の対応

失敗は App Insights の scheduled query alert（15 分間隔）→ 運用者メールで検知される。

### 切り分け

Portal → Function App `func-editor-aoai-*` → `rotate_key` → Invocations でエラーを確認:

| 失敗箇所 | 状態 | 対応 |
|---|---|---|
| regenerate 失敗 | キー・KV とも変更なし | RBAC（Cognitive Services Contributor）や一時障害を確認し、手動再実行 |
| KV 保存失敗 | **新キー生成済みだが KV は旧キー** | 下記「手動ローテーション」で最初からやり直す（同じスロットを再 regenerate すれば整合する） |
| Teams 通知失敗 | **キーは更新済み。利用者が気づかない（最悪パターン）** | 手動で Teams へ周知 → webhook URL（KV `teams-webhook-url`）を修復 |

### 手動ローテーション（Function が使えない場合の代替）

指示書 §3 のコマンドをそのまま使う:

```bash
RES=<resource-name>; RG=rg-editor-openai; KV=<keyvault>
ACTIVE=$(az keyvault secret show --vault-name $KV --name editor-openai-key --query "tags.slot" -o tsv)
NEXT=$([ "$ACTIVE" = "key1" ] && echo key2 || echo key1)

NEW_KEY=$(az cognitiveservices account keys regenerate \
  -n $RES -g $RG --key-name $NEXT --query $NEXT -o tsv)
az keyvault secret set --vault-name $KV --name editor-openai-key \
  --value "$NEW_KEY" --tags slot=$NEXT -o none

# 方針: ローテ通知に新キー本文を含める（利用者はこれをエディタに貼り替える）
curl -sf -X POST "$TEAMS_WEBHOOK_URL" -H 'Content-Type: application/json' \
  -d "$(printf '{"text":"エディタ用 OpenAI API キーをローテーションしました。\\n新しいキー:\\n%s\\nエディタのキー設定をこの値に貼り替えてください。旧キーは次回ローテーション（1週間後）で失効します。"}' "$NEW_KEY")"
unset NEW_KEY
```

### 手動実行（Portal から）

Function App → `rotate_key` → Code + Test → Test/Run。
緊急失効（流出疑い）は **2 回連続実行**で両キーを更新する。

## よくある問い合わせ

- **401 が出る** → 旧キー失効。最新キーを KV から取得（本ページ上部）
- **403 が出る** → キーではなく IP の問題。`curl ifconfig.me` で自 IP を確認し、オフィス回線 / VPN 経由かを確認（[usage-policy.md](usage-policy.md)）
- **全員 401（月曜以外）** → ハードリミット発動の可能性。Teams の発動通知と [runbook-hard-limit.md](runbook-hard-limit.md) を確認
