// Azure OpenAI アカウント + IP allowlist + モデル deployments
// データ越境リスク低減のため国内リージョン (japaneast) 前提で構築する。
// deployment は regional Standard SKU を採用し、推論処理を japaneast 単独に閉じる
// （保管・処理とも日本国内で完結。最も厳格なデータ所在。docs/design.md §1.1）。
// 制約: japaneast の regional Standard で提供されるチャットモデルは限られる
// （GPT-5 系は非対応）。モデルは main.bicepparam で提供状況を確認のうえ指定すること。
param name string

@description('リージョン。データ所在の前提として国内 (japaneast) を既定とする')
param location string
param tags object
param allowedIps array
param modelDeployments array

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
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
      // regional Standard（推論を japaneast 単独で処理）。
      // 個別に上書きしたい場合のみ main.bicepparam の各 deployment に sku を指定
      name: d.?sku ?? 'Standard'
      capacity: d.capacity
    }
    properties: {
      model: union(
        {
          format: 'OpenAI'
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
