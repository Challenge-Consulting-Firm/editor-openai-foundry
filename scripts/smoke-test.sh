#!/usr/bin/env bash
# デプロイ後の疎通確認（指示書 §8 受け入れ基準 1・2 の実測用）
#
# 使い方: ./scripts/smoke-test.sh <keyVaultName> <endpoint>
#   例:   ./scripts/smoke-test.sh kv-editor-aoai-xxxx https://editor-aoai-xxxx.openai.azure.com/
#
# キーは画面・履歴に出さない（変数経由でのみ使用）
set -euo pipefail

KV_NAME="${1:?usage: smoke-test.sh <keyVaultName> <endpoint>}"
ENDPOINT="${2:?usage: smoke-test.sh <keyVaultName> <endpoint>}"
# 全モデル（OpenAI / 非 OpenAI）が同一 openai/v1 エンドポイントで応答する
BASE_URL="${ENDPOINT%/}/openai/v1"
# デプロイ済みの deployment 名に合わせる（現状は全て -apac=APAC 処理）。
# 既定はフェーズ1の 2 モデル。フェーズ2で deepseek-apac 等を足したら追記する
DEPLOYMENTS=("gpt5-apac")

echo "== 接続元グローバル IP（allowlist に載っているか確認） =="
curl -s ifconfig.me
echo; echo

echo "== Key Vault から現行キーを取得 =="
API_KEY=$(az keyvault secret show --vault-name "$KV_NAME" --name editor-openai-key --query value -o tsv)
SLOT=$(az keyvault secret show --vault-name "$KV_NAME" --name editor-openai-key --query 'tags.slot' -o tsv)
echo "現用スロット: ${SLOT:-（タグなし）}"
echo

for DEP in "${DEPLOYMENTS[@]}"; do
  echo "== chat completions 疎通: $DEP =="
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/chat/completions" \
    -H "api-key: $API_KEY" \
    -H 'Content-Type: application/json' \
    -d "{\"model\": \"$DEP\", \"messages\": [{\"role\": \"user\", \"content\": \"ping\"}], \"max_completion_tokens\": 16}")
  case "$STATUS" in
    200) echo "OK ($STATUS)" ;;
    401) echo "NG ($STATUS): キーが無効。ローテーション後の旧キー使用 or disableLocalAuth=true（ハードリミット発動中）の可能性" ;;
    403) echo "NG ($STATUS): 接続元 IP が allowlist 外。上記の自 IP を infra/main.bicepparam の台帳と突合すること" ;;
    404) echo "NG ($STATUS): deployment 名 '$DEP' が存在しない" ;;
    *)   echo "NG ($STATUS)" ;;
  esac
  echo
done

unset API_KEY

cat <<'EOF'
-- 追加の手動確認（受け入れ基準） --
基準1: allowlist 外の回線（テザリング等）から本スクリプトを実行し 403 になること
基準2: Zed / VS Code から各 1 回実測すること（docs/setup-zed.md / setup-vscode.md）
EOF
