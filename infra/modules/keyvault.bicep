// Key Vault: ローテーション後キーの保管 + Teams webhook URL の格納
param name string
param location string
param tags object

@secure()
param teamsWebhookUrl string

param openAiAccountName string

@description('初回デプロイ時のみ true。key1 を editor-openai-key として初期投入する')
param seedInitialKey bool

@description('利用者 Entra グループ objectId。空文字なら RBAC 付与をスキップ')
param usersGroupObjectId string

// Key Vault Secrets User（読み取りのみ）
var secretsUserRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '4633458b-17de-408a-b874-0445c86b69e6'
)

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 30
  }
}

resource webhookSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'teams-webhook-url'
  properties: {
    value: teamsWebhookUrl
  }
}

resource aoai 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: openAiAccountName
}

// 初回ブートストラップ専用。2 回目以降のデプロイで有効化するとローテーション済みキーを
// key1 で上書きしてしまうため、運用開始後は必ず seedInitialKey=false にすること
resource initialKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (seedInitialKey) {
  parent: kv
  name: 'editor-openai-key'
  tags: {
    slot: 'key1'
  }
  properties: {
    value: aoai.listKeys().key1
  }
}

resource usersSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(usersGroupObjectId)) {
  name: guid(kv.id, usersGroupObjectId, secretsUserRoleId)
  scope: kv
  properties: {
    principalId: usersGroupObjectId
    roleDefinitionId: secretsUserRoleId
    principalType: 'Group'
  }
}

output keyVaultName string = kv.name
output keyVaultUri string = kv.properties.vaultUri
output webhookSecretUri string = webhookSecret.properties.secretUri
