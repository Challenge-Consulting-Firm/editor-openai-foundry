// Azure OpenAI アカウント + IP allowlist + モデル deployments
param name string
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
      name: 'DataZoneStandard'
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
