#!/usr/bin/env bash
# エディタ用 Azure OpenAI 基盤のデプロイ（what-if → 確認 → 実行）
#
# 使い方:
#   export TEAMS_WEBHOOK_URL='https://...'   # Power Automate Workflows の webhook URL
#   ./scripts/deploy.sh [--first-run]        # --first-run: key1 を Key Vault へ初期投入
#
# 前提: az login 済み / 対象サブスクリプションを az account set 済み
set -euo pipefail

cd "$(dirname "$0")/../infra"

LOCATION="japaneast"
DEPLOYMENT_NAME="editor-openai-$(date +%Y%m%d-%H%M%S)"
EXTRA_ARGS=()

if [[ "${1:-}" == "--first-run" ]]; then
  EXTRA_ARGS+=(--parameters seedInitialKey=true)
  echo "*** 初回デプロイモード: key1 を Key Vault へ初期投入します ***"
  echo "*** 2 回目以降のデプロイでは --first-run を付けないこと（ローテーション済みキーを上書きします） ***"
fi

if [[ -z "${TEAMS_WEBHOOK_URL:-}" ]]; then
  echo "ERROR: 環境変数 TEAMS_WEBHOOK_URL が未設定です" >&2
  exit 1
fi

echo "== 対象サブスクリプション =="
az account show --query '{name:name, id:id}' -o table
echo

echo "== what-if =="
az deployment sub what-if \
  --location "$LOCATION" \
  --name "$DEPLOYMENT_NAME" \
  --parameters main.bicepparam \
  "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"

echo
read -r -p "上記の変更を適用しますか? (yes/no): " ANSWER
if [[ "$ANSWER" != "yes" ]]; then
  echo "中止しました"
  exit 0
fi

az deployment sub create \
  --location "$LOCATION" \
  --name "$DEPLOYMENT_NAME" \
  --parameters main.bicepparam \
  "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}" \
  --query 'properties.outputs' -o json

cat <<'EOF'

デプロイ完了。次の手順:
1. Functions のコードデプロイ:
     cd functions && func azure functionapp publish <functionAppName>
2. 疎通確認: ./scripts/smoke-test.sh <keyVaultName> <endpoint>
3. 受け入れ基準の実測: docs/design.md §8
EOF
