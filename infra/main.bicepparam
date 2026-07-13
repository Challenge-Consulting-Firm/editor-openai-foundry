// 環境パラメータ。
// 環境ごとに変わる値・秘密は .env（.env.sample をコピー）で管理し、deploy.sh が読み込む。
// このファイルは env を読むだけで、直接編集が要るのはモデル catalog（modelDeployments）のみ。
using 'main.bicep'

// ---- .env 由来（環境依存・秘密）-----------------------------------------------
param resourceGroupName = readEnvironmentVariable('RESOURCE_GROUP', 'rg-editor-openai')
param location = readEnvironmentVariable('LOCATION', 'japaneast')
param baseName = readEnvironmentVariable('BASE_NAME', 'editor-aoai')

// ALLOWED_IPS: カンマ区切りのグローバル IP。空要素は除外。
// Cognitive Services の networkAcls は単一 IP に /32・/31 を付けられない（バレア IP 必須）。
// そこで /32・/31 は外してバレア IP にし、/24 等の実レンジはそのまま通す。
param allowedIps = map(
  filter(split(readEnvironmentVariable('ALLOWED_IPS', ''), ','), s => !empty(trim(s))),
  s => {
    value: (endsWith(trim(s), '/32') || endsWith(trim(s), '/31')) ? split(trim(s), '/')[0] : trim(s)
  }
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
// 【既定 = フェーズ1】japaneast で GA(配備可)を確認済みの DataZone OpenAI 2 モデル。
// ※ 国内完結(regional Standard)チャットは 2026-07 時点 japaneast で配備可能モデルが無い
//   （gpt-4o / gpt-4.1-mini が Deprecating で新規デプロイ不可）。対応モデルが出たら追加検討。
//   保管は全モデル日本国内。推論は APAC 圏（docs/design.md §1.1）。
// 非OpenAI（DeepSeek 等）は AIServices 作成後に list-models で確認してからフェーズ2 で追加。
//
// 【.env で上書き可】.env の MODEL_DEPLOYMENTS に JSON 文字列を設定すると、この既定を上書きする。
var defaultModelDeployments = [
  {
    name: 'gpt5-apac' // 既定・主力（コーディング/ログ解析とも）。汎用 GPT-5.2。APAC 処理
    // gpt-5.3-codex は Chat Completions 非対応（Responses API 専用）で Zed/VS Code から使えないため不採用。
    // gpt-5.2 は chatCompletion=true で GA。gpt-5.4-mini は quota 枯渇のため不採用。
    modelName: 'gpt-5.2'
    modelVersion: '2025-12-11'
    format: 'OpenAI'
    sku: 'DataZoneStandard'
    capacity: 200 // 200K TPM。gpt-5.2 の DataZone quota 空き ~250 に収まる
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
