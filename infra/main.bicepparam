// 環境パラメータ。
// 環境ごとに変わる値・秘密は .env（.env.sample をコピー）で管理し、deploy.sh が読み込む。
// このファイルは env を読むだけで、直接編集が要るのはモデル catalog（modelDeployments）のみ。
using 'main.bicep'

// ---- .env 由来（環境依存・秘密）-----------------------------------------------
param resourceGroupName = readEnvironmentVariable('RESOURCE_GROUP', 'rg-editor-openai')
param location = readEnvironmentVariable('LOCATION', 'japaneast')
param baseName = readEnvironmentVariable('BASE_NAME', 'editor-aoai')

// ALLOWED_IPS: カンマ区切りのグローバル IP。/32 なしは自動付与。空要素は除外
param allowedIps = map(
  filter(split(readEnvironmentVariable('ALLOWED_IPS', ''), ','), s => !empty(trim(s))),
  s => { value: contains(trim(s), '/') ? trim(s) : '${trim(s)}/32' }
)

param teamsWebhookUrl = readEnvironmentVariable('TEAMS_WEBHOOK_URL', '')

// OPS_EMAILS: カンマ区切り
param opsEmails = map(
  filter(split(readEnvironmentVariable('OPS_EMAILS', ''), ','), s => !empty(trim(s))),
  s => trim(s)
)

param monthlyBudgetAmount = int(readEnvironmentVariable('MONTHLY_BUDGET_AMOUNT', '100000'))
param budgetStartDate = readEnvironmentVariable('BUDGET_START_DATE', '2026-07-01')
param usersGroupObjectId = readEnvironmentVariable('USERS_GROUP_OBJECT_ID', '')
param seedInitialKey = bool(readEnvironmentVariable('SEED_INITIAL_KEY', 'false'))

// ---- モデル deployment（複数モデル/複数 residency を混在）-----------------------
// リソースは kind: AIServices（Foundry）。OpenAI/非OpenAI 両方を同一アカウントに配備し、
// 利用者はエディタの deployment 名で切り替える。data 所在は sku で決まる:
//   sku: 'Standard'         → 推論も japaneast 単独（国内完結）
//   sku: 'DataZoneStandard' → 推論は APAC 圏（日本国外もあり得る = 越境）
// deployment 名に residency（-jp / -apac）を含め、利用者が越境を認識できるようにする。
//
// format は publisher: OpenAI 系='OpenAI'、DeepSeek='DeepSeek'、Grok='xAI'、Mistral='Mistral AI'、Phi='Microsoft'。
//
// !!! デプロイ前に必ず提供状況とモデル名/バージョン/format を確認すること:
//   az cognitiveservices account list-models -n <account> -g <rg> \
//     --query "[].{model:name, version:version, format:format, skus:skus[].name}" -o table
//   （公式: models-sold-directly-by-azure-region-availability）
//
// capacity は TPM 千単位。コストの実効上限を兼ねる（指示書 §5 補助ガード）。
// 高単価モデル（DataZone の GPT-5/DeepSeek 等）は TPM を小さくして worst-case を封じ込める。
param modelDeployments = [
  {
    name: 'gpt41mini-jp' // 既定・国内完結。軽量コーディング/ログ解析
    modelName: 'gpt-4.1-mini'
    modelVersion: '2025-04-14'
    format: 'OpenAI'
    sku: 'Standard' // 国内単独処理
    capacity: 50
  }
  {
    name: 'gpt5codex-apac' // 高性能コーディング（OpenAI GPT-5 codex）。APAC 処理（越境）
    modelName: 'gpt-5.3-codex'
    modelVersion: '2026-02-24'
    format: 'OpenAI'
    sku: 'DataZoneStandard'
    capacity: 20 // 高単価のため絞る
  }
  {
    name: 'deepseek-apac' // 代替の高性能コーディング（非 OpenAI）。APAC 処理（越境）
    modelName: 'DeepSeek-V4-Pro'
    modelVersion: '' // 空 = 既定バージョン（list-models で確認して固定を推奨）
    format: 'DeepSeek'
    sku: 'DataZoneStandard'
    capacity: 20
  }
]
