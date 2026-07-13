#!/usr/bin/env bash
# エディタ用 Azure AI Foundry 基盤のデプロイ（.env 読み込み → what-if → 確認 → 実行）
#
# 使い方:
#   cp .env.sample .env   # 初回のみ。.env の値を実値に置き換える
#   ./scripts/deploy.sh [--first-run]   # --first-run: key1 を Key Vault へ初期投入
#
# 前提: az login 済み。デプロイ先は .env の AZURE_SUBSCRIPTION_ID（空なら現在の az account）
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

# ---- .env 読み込み ----------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE がありません。'cp .env.sample .env' して値を設定してください" >&2
  exit 1
fi
set -a            # 以降の変数を export（bicepparam の readEnvironmentVariable が参照）
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# ---- 必須値バリデーション ---------------------------------------------------
fail=0
require() { if [[ -z "${!1:-}" ]]; then echo "ERROR: .env の $1 が未設定です" >&2; fail=1; fi; }
require TEAMS_WEBHOOK_URL
require ALLOWED_IPS
require OPS_EMAILS
require MONTHLY_BUDGET_AMOUNT
require BUDGET_START_DATE

# プレースホルダのまま実行するのを防ぐ
if [[ "${ALLOWED_IPS:-}" == *"203.0.113."* ]]; then
  echo "ERROR: ALLOWED_IPS がサンプル値(203.0.113.x)のままです。実 IP に置き換えてください" >&2
  fail=1
fi
if [[ "${OPS_EMAILS:-}" == *"ops@example.com"* ]]; then
  echo "ERROR: OPS_EMAILS がサンプル値のままです。実メールに置き換えてください" >&2
  fail=1
fi
[[ "$fail" -eq 0 ]] || exit 1

# --first-run は .env の SEED_INITIAL_KEY より優先
if [[ "${1:-}" == "--first-run" ]]; then
  export SEED_INITIAL_KEY=true
fi
if [[ "${SEED_INITIAL_KEY:-false}" == "true" ]]; then
  echo "*** 初回デプロイモード: key1 を Key Vault へ初期投入します ***"
  echo "*** 2 回目以降は SEED_INITIAL_KEY=false / --first-run なしで実行（ローテ済みキーを上書きしないため） ***"
fi

LOCATION="${LOCATION:-japaneast}"
DEPLOYMENT_NAME="editor-openai-$(date +%Y%m%d-%H%M%S)"
cd "$REPO_ROOT/infra"

# ---- サブスクリプション選択 -------------------------------------------------
if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
  az account set --subscription "$AZURE_SUBSCRIPTION_ID"
fi
echo "== 対象サブスクリプション =="
az account show --query '{name:name, id:id}' -o table
echo

# ---- what-if ----------------------------------------------------------------
echo "== what-if =="
az deployment sub what-if \
  --location "$LOCATION" \
  --name "$DEPLOYMENT_NAME" \
  --parameters main.bicepparam

echo
read -r -p "上記の変更を適用しますか? (yes/no): " ANSWER
if [[ "$ANSWER" != "yes" ]]; then
  echo "中止しました"
  exit 0
fi

# ---- 適用 -------------------------------------------------------------------
az deployment sub create \
  --location "$LOCATION" \
  --name "$DEPLOYMENT_NAME" \
  --parameters main.bicepparam \
  --query 'properties.outputs' -o json

cat <<'EOF'

デプロイ完了。次の手順:
1. Functions のコードデプロイ:
     cd functions && func azure functionapp publish <functionAppName>
2. 疎通確認: ./scripts/smoke-test.sh <keyVaultName> <endpoint>
3. 受け入れ基準の実測: docs/design.md §8
EOF
