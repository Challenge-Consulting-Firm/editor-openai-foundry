# Runbook: ハードリミット発動時の対応

**発動条件**: 月次 Budget の 100%（Actual）到達 → `hard_stop` Function が
`disableLocalAuth: true` に更新し、api-key 認証を全停止。Teams に発動通知が投稿される。

**復旧は手動のみ**（自動復旧は設計上入れていない）。

## 1. 状況確認（復旧より先に必ず行う）

```bash
RG=rg-editor-openai
RES=$(az cognitiveservices account list -g $RG --query '[0].name' -o tsv)

# 停止状態の確認（true なら発動中）
az cognitiveservices account show -n $RES -g $RG --query 'properties.disableLocalAuth'

# 今月のコスト実績
az consumption usage list --query "[?contains(instanceName, '$RES')]" -o table
```

## 2. 原因調査

Log Analytics（`log-editor-openai`）で発動直前の利用状況を確認する:

```kusto
// 直近 7 日の deployment 別・IP 別リクエスト量（異常な急増元を特定）
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES" and Category == "RequestResponse"
| where TimeGenerated > ago(7d)
| extend deployment = tostring(parse_json(properties_s).modelDeploymentName)
| summarize requests = count() by CallerIPAddress, deployment, bin(TimeGenerated, 1h)
| order by requests desc
```

確認観点:

- [ ] 特定 IP からの異常な呼び出し量がないか（**キー流出の疑い** → 先にキーローテーションを手動実行してから復旧）
- [ ] 特定 deployment（用途）への偏りはないか
- [ ] 正常利用の増加であれば予算額の見直しを検討（`infra/main.bicepparam` の `monthlyBudgetAmount`）

## 3. 復旧手順

原因確認・対処が済んでから実施:

```bash
az cognitiveservices account update -n $RES -g $RG --set properties.disableLocalAuth=false
```

復旧後の確認:

```bash
./scripts/smoke-test.sh <keyVaultName> https://$RES.openai.azure.com/
```

Teams へ復旧報告を投稿する（原因と対処を添える）。

## 4. 注意事項

- **発動中に IaC（deploy.sh）を再実行しない**。bicep は `disableLocalAuth: false` を宣言しているため、意図せず復旧してしまう
- キー流出が疑われる場合の緊急ローテーション: Portal から Function App `func-editor-aoai-*` の
  `rotate_key` を手動実行（Test/Run）。2 回連続実行すれば両キーが更新され、流出キーは即時失効する
- 月替わりで Budget はリセットされるが、`disableLocalAuth` は**自動では戻らない**。復旧はこの runbook のみ
