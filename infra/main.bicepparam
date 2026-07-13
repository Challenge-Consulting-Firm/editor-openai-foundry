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
// format は publisher: OpenAI 系='OpenAI'、DeepSeek='DeepSeek'、Grok='xAI'、Mistral='Mistral AI'、Phi='Microsoft'。
// capacity は TPM 千単位。高単価モデル（DataZone の GPT-5/DeepSeek 等）は小さくして worst-case を封じ込める。
//
// 【既定 = フェーズ1】japaneast 実提供を確認済みの OpenAI 2 モデル（docs/deploy-staged.md）。
// 非OpenAI（DeepSeek 等）は AIServices アカウント作成後に list-models で確認してから
// フェーズ2 で追加する（下の phase2 例を参照）。
//
// 【.env で上書き可】.env の MODEL_DEPLOYMENTS に JSON 文字列を設定すると、この既定を上書きする。
//   例（1行で記述）:
//   MODEL_DEPLOYMENTS=[{"name":"gpt41mini-jp","modelName":"gpt-4.1-mini","modelVersion":"2025-04-14","format":"OpenAI","sku":"Standard","capacity":50}]
var defaultModelDeployments = [
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
]

// フェーズ2で追加する非OpenAIモデルの例（list-models で name/version/format を確認後、
// 上の defaultModelDeployments に足すか、.env の MODEL_DEPLOYMENTS に含める）:
//   {
//     name: 'deepseek-apac'          // 非 OpenAI。APAC 処理（越境）
//     modelName: 'DeepSeek-V4-Pro'   // ← list-models の実名に合わせる
//     modelVersion: ''               // ← 実バージョンに固定推奨
//     format: 'DeepSeek'
//     sku: 'DataZoneStandard'
//     capacity: 20
//   }

// .env の MODEL_DEPLOYMENTS があればそれ（JSON）を、無ければ上の既定を使う
param modelDeployments = empty(readEnvironmentVariable('MODEL_DEPLOYMENTS', ''))
  ? defaultModelDeployments
  : json(readEnvironmentVariable('MODEL_DEPLOYMENTS', '[]'))
