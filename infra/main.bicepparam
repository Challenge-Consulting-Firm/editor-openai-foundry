// 環境パラメータ。デプロイ前にプレースホルダを実値に置き換えること。
// IP の追加・削除は必ずこのファイル経由で行い、台帳コメントを残す（指示書 §4）
using 'main.bicep'

param resourceGroupName = 'rg-editor-openai'
param location = 'japaneast'
param baseName = 'editor-aoai'

// ---- IP allowlist 台帳 --------------------------------------------------
// 形式: { value: '<グローバルIP>/32' }
// 変更時は「申請者 / 追加日 / 用途」をコメントで残すこと
param allowedIps = [
  // 例: 情シス申請 2026-07-01 オフィス回線
  { value: '203.0.113.10/32' } // TODO: オフィス回線のグローバル IP に置き換え
  // 例: 情シス申請 2026-07-01 会社 VPN egress
  { value: '203.0.113.20/32' } // TODO: VPN egress IP に置き換え
]

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

// ---- 通知・コスト -----------------------------------------------------------
// Teams Workflows (Power Automate「Webhook 要求を受信したとき」) の URL。
// 平文コミットを避けたい場合は deploy.sh が環境変数 TEAMS_WEBHOOK_URL から上書き指定する
param teamsWebhookUrl = readEnvironmentVariable('TEAMS_WEBHOOK_URL', '')

param opsEmails = [
  'ops@example.com' // TODO: 運用者メールに置き換え
]

// 月次予算（円）。初期値の目安: 想定利用の 2〜3 倍
param monthlyBudgetAmount = 100000

// 当月 1 日（YYYY-MM-01）
param budgetStartDate = '2026-07-01'

// 利用者 Entra グループ objectId（Key Vault Secrets User 付与）。未定なら空のまま
param usersGroupObjectId = ''

// 初回デプロイ時のみ true（key1 を Key Vault へ初期投入）。運用開始後は必ず false
param seedInitialKey = false
