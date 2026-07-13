// エディタ用 Azure OpenAI (Foundry) 基盤 — メインテンプレート
// デプロイ: scripts/deploy.sh 参照（az deployment sub create）
targetScope = 'subscription'

@description('リソースグループ名。既存の他用途リソースとは別 RG に分離する')
param resourceGroupName string = 'rg-editor-openai'

@description('リージョン。データ所在の前提として国内 (japaneast)。regional Standard の deployment はここで単独処理される')
param location string = 'japaneast'

@description('リソース名の基礎文字列')
param baseName string = 'editor-aoai'

@description('共通タグ')
param tags object = {
  workload: 'editor-openai'
  managedBy: 'bicep'
}

@description('IP allowlist。台帳（申請者・追加日）は main.bicepparam のコメントに必ず残す')
param allowedIps array

@description('モデル deployment 定義。要素: name / modelName / modelVersion / capacity(TPM千単位) / format(publisher, 省略時 OpenAI) / sku(省略時 Standard=regional/国内完結, DataZoneStandard=APAC)。deployment 名に residency を含めること')
param modelDeployments array = [
  {
    // 既定・主力（コーディング/ログ解析とも）。GPT-5 codex。処理は APAC 圏。
    // ※ 国内完結(regional Standard)チャットは japaneast で対応モデルが Deprecating のため現状不可
    name: 'gpt5-apac'
    modelName: 'gpt-5.2'
    modelVersion: '2025-12-11'
    format: 'OpenAI'
    sku: 'DataZoneStandard'
    capacity: 200
  }
]

@description('Teams Workflows (Power Automate) の webhook URL。Key Vault に格納される')
@secure()
param teamsWebhookUrl string

@description('運用者メールアドレス（Budget ソフト通知・Function 失敗アラート宛先）')
param opsEmails array

@description('月次予算額（通貨はサブスクリプションの課金通貨）。初期値の目安: 想定利用の 2〜3 倍')
param monthlyBudgetAmount int

@description('Budget の開始日。当月 1 日を YYYY-MM-01 形式で指定')
param budgetStartDate string

@description('利用者 Entra グループの objectId（Key Vault Secrets User を付与）。空なら付与しない')
param usersGroupObjectId string = ''

@description('初回デプロイ時のみ true: key1 を Key Vault へ初期投入する。ローテーション運用開始後は必ず false（新しいキーを上書きしてしまう）')
param seedInitialKey bool = false

var suffix = uniqueString(subscription().subscriptionId, resourceGroupName)
var aoaiName = '${baseName}-${suffix}'
var kvName = take('kv-${baseName}-${suffix}', 24)
var funcName = 'func-${baseName}-${suffix}'
var storageName = take('st${replace(baseName, '-', '')}${suffix}', 24)

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module openai 'modules/openai.bicep' = {
  scope: rg
  name: 'openai'
  params: {
    name: aoaiName
    location: location
    tags: tags
    allowedIps: allowedIps
    modelDeployments: modelDeployments
  }
}

module monitoring 'modules/monitoring.bicep' = {
  scope: rg
  name: 'monitoring'
  params: {
    location: location
    tags: tags
    openAiAccountName: openai.outputs.accountName
  }
}

module keyvault 'modules/keyvault.bicep' = {
  scope: rg
  name: 'keyvault'
  params: {
    name: kvName
    location: location
    tags: tags
    teamsWebhookUrl: teamsWebhookUrl
    openAiAccountName: openai.outputs.accountName
    seedInitialKey: seedInitialKey
    usersGroupObjectId: usersGroupObjectId
  }
}

module functions 'modules/functions.bicep' = {
  scope: rg
  name: 'functions'
  params: {
    functionAppName: funcName
    storageAccountName: storageName
    location: location
    tags: tags
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    openAiAccountName: openai.outputs.accountName
    keyVaultUri: keyvault.outputs.keyVaultUri
    webhookSecretUri: keyvault.outputs.webhookSecretUri
  }
}

module rbac 'modules/rbac.bicep' = {
  scope: rg
  name: 'rbac'
  params: {
    principalId: functions.outputs.principalId
    openAiAccountName: openai.outputs.accountName
    keyVaultName: keyvault.outputs.keyVaultName
  }
}

module budget 'modules/budget.bicep' = {
  scope: rg
  name: 'budget'
  params: {
    location: location
    tags: tags
    functionAppName: functions.outputs.functionAppName
    opsEmails: opsEmails
    amount: monthlyBudgetAmount
    startDate: budgetStartDate
    appInsightsId: monitoring.outputs.appInsightsId
  }
}

output endpoint string = openai.outputs.endpoint
output openAiV1BaseUrl string = openai.outputs.openAiV1BaseUrl
output keyVaultName string = keyvault.outputs.keyVaultName
output functionAppName string = functions.outputs.functionAppName
output resourceGroupName string = rg.name
