// Log Analytics + App Insights + Azure OpenAI 診断設定
param location string
param tags object
param openAiAccountName string

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-editor-openai'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-editor-openai'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: law.id
  }
}

resource aoai 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: openAiAccountName
}

// RequestResponse: 呼び出し元 IP・deployment 別の利用量監査（指示書 §6）
// AllMetrics: deployment 別トークン量（kql/monthly-usage.kql が参照）
resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: aoai
  properties: {
    workspaceId: law.id
    logs: [
      {
        category: 'RequestResponse'
        enabled: true
      }
      {
        category: 'Audit'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output logAnalyticsId string = law.id
output appInsightsId string = appInsights.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
