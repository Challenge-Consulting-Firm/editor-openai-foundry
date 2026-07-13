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

// ---- モデル deployment ---------------------------------------------------
// SKU は regional Standard（推論を japaneast 単独で処理 = 国内完結）。
// !!! 重要 !!! japaneast の regional Standard で提供されるチャットモデルは限定的で、
//   GPT-5 系は非対応。2026-07 時点の選択肢は gpt-4.1-mini / gpt-4o のみ。
//   最新の提供状況は必ず下記で確認すること:
//   az cognitiveservices account list-models -n <account> -g <rg> \
//     --query "[?contains(skus[].name,'Standard') && kind=='OpenAI'].{model:name,version:version}" -o table
//   （公式: models-sold-directly-by-azure-region-availability の Standard/Regional > Asia Pacific）
// capacity は TPM 千単位（50 = 50K TPM）。コストの実効上限を兼ねるため控えめに開始（指示書 §5 補助ガード）
param modelDeployments = [
  {
    name: 'agent-main' // コーディングエージェント用（japaneast regional Standard の最上位相当）
    modelName: 'gpt-4.1-mini'
    modelVersion: '2025-04-14'
    capacity: 50
  }
  {
    name: 'log-analysis' // ログ解析用
    modelName: 'gpt-4.1-mini'
    modelVersion: '2025-04-14'
    capacity: 50
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
