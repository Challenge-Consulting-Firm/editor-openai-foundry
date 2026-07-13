// Function App の Managed Identity へのロール付与（指示書 §3）
param principalId string
param openAiAccountName string
param keyVaultName string

// keys regenerate / disableLocalAuth 更新（対象リソーススコープ）
var cognitiveServicesContributor = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68'
)

// editor-openai-key の set / teams-webhook-url の get
var keyVaultSecretsOfficer = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
)

resource aoai 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: openAiAccountName
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource aoaiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aoai.id, principalId, cognitiveServicesContributor)
  scope: aoai
  properties: {
    principalId: principalId
    roleDefinitionId: cognitiveServicesContributor
    principalType: 'ServicePrincipal'
  }
}

resource kvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, principalId, keyVaultSecretsOfficer)
  scope: kv
  properties: {
    principalId: principalId
    roleDefinitionId: keyVaultSecretsOfficer
    principalType: 'ServicePrincipal'
  }
}
