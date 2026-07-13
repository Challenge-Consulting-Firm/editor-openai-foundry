// Azure AI Foundry アカウント (kind: AIServices) + IP allowlist + 複数モデル deployments
//
// kind を AIServices とすることで、OpenAI モデルと非 OpenAI の Foundry モデル
// （DeepSeek / xAI Grok / Mistral 等）を同一アカウントに混在デプロイできる。
// 全モデルは共通の OpenAI 互換エンドポイント (openai/v1) + 共通 api-key で利用でき、
// エディタ側は deployment 名を選ぶだけで切り替わる（docs/setup-*.md）。
//
// データ所在は deployment ごとの SKU で決まる（docs/design.md §1.1）:
//   - Standard         : 推論も japaneast 単独（国内完結）
//   - DataZoneStandard : 推論はアジア太平洋圏内（国外処理あり得る）
// deployment 名に residency を含めて利用者が越境を認識できるようにすること。
param name string

@description('リージョン。データ所在の前提として国内 (japaneast) を既定とする')
param location string
param tags object
param allowedIps array

@description('モデル deployment 定義。要素: name / modelName / modelVersion / capacity(TPM千単位) / format(publisher, 省略時 OpenAI) / sku(省略時 Standard=regional)')
param modelDeployments array

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  // AIServices = Azure AI Foundry。OpenAI 専用 (kind: OpenAI) と異なり非 OpenAI モデルも扱える
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  properties: {
    // openai.azure.com/openai/v1 の OpenAI 互換エンドポイントを有効化するため必須
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    // ハードリミット発動時のみ Functions が true 化する。IaC 上は常に false を維持。
    // 発動中に再デプロイすると意図せず復旧するため、発動中の再デプロイは禁止（runbook 参照）
    disableLocalAuth: false
    networkAcls: {
      defaultAction: 'Deny'
      ipRules: [
        for ip in allowedIps: {
          value: ip.value
        }
      ]
    }
  }
}

// deployment は同時作成できないため直列化
@batchSize(1)
resource deployments 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = [
  for d in modelDeployments: {
    parent: account
    name: d.name
    sku: {
      // 既定は regional Standard（japaneast 単独処理）。
      // DataZone モデルは main.bicepparam の各 deployment で sku: 'DataZoneStandard' を指定
      name: d.?sku ?? 'Standard'
      capacity: d.capacity
    }
    properties: {
      model: union(
        {
          // publisher。OpenAI 以外は 'DeepSeek' / 'xAI' / 'Mistral AI' / 'Microsoft' 等
          format: d.?format ?? 'OpenAI'
          name: d.modelName
        },
        empty(d.modelVersion) ? {} : { version: d.modelVersion }
      )
      versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    }
  }
]

output accountId string = account.id
output accountName string = account.name
output endpoint string = account.properties.endpoint
// 全 deployment 共通の OpenAI 互換ベース URL（エディタに登録する）
output openAiV1BaseUrl string = 'https://${name}.openai.azure.com/openai/v1/'
