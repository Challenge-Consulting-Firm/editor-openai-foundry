// コスト上限（指示書 §5）: Action Group ×3 + 月次 Budget + Function 失敗アラート
param location string
param tags object
param functionAppName string
param opsEmails array
param amount int

@description('YYYY-MM-01 形式（当月 1 日）')
param startDate string

param appInsightsId string

// Function の host key で notify_soft / hard_stop を呼ぶ webhook URL を組み立てる。
// host key は Function App 作成時点で存在するため、コードデプロイ前でも解決できる
#disable-next-line use-recognized-resource-type
var hostKeys = listKeys(resourceId('Microsoft.Web/sites/host', functionAppName, 'default'), '2023-12-01')
var functionBaseUrl = 'https://${functionAppName}.azurewebsites.net/api'

// --- Action Groups -----------------------------------------------------------
// Action Group から Teams へ直接投稿は不可のため、Function 経由で webhook 投稿する

resource agTeams 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-editor-openai-teams'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'aoai-teams'
    enabled: true
    webhookReceivers: [
      {
        name: 'notify-soft-fn'
        serviceUri: '${functionBaseUrl}/notify_soft?code=${hostKeys.functionKeys.default}'
        useCommonAlertSchema: false
      }
    ]
  }
}

resource agOps 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-editor-openai-ops'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'aoai-ops'
    enabled: true
    emailReceivers: [
      for (email, i) in opsEmails: {
        name: 'ops-${i}'
        emailAddress: email
        useCommonAlertSchema: true
      }
    ]
  }
}

resource agHard 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-editor-openai-hardstop'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'aoai-hard'
    enabled: true
    webhookReceivers: [
      {
        name: 'hard-stop-fn'
        serviceUri: '${functionBaseUrl}/hard_stop?code=${hostKeys.functionKeys.default}'
        useCommonAlertSchema: false
      }
    ]
  }
}

// --- 月次 Budget: ソフト 3 段階 + ハード 1（すべて Actual ベース） ---------------

resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: 'budget-editor-openai'
  properties: {
    category: 'Cost'
    amount: amount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: startDate
    }
    notifications: {
      soft1Actual50: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 50
        thresholdType: 'Actual'
        contactEmails: []
        contactGroups: [
          agTeams.id
        ]
      }
      soft2Actual75: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 75
        thresholdType: 'Actual'
        contactEmails: opsEmails
        contactGroups: [
          agTeams.id
        ]
      }
      soft3Actual90: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 90
        thresholdType: 'Actual'
        contactEmails: opsEmails
        contactGroups: [
          agTeams.id
        ]
      }
      hardActual100: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 100
        thresholdType: 'Actual'
        contactEmails: opsEmails
        contactGroups: [
          agHard.id
        ]
      }
    }
  }
}

// --- ローテーション/停止処理の失敗検知（指示書 §3: 通知失敗は必ず検知する） --------

resource functionFailureAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-editor-openai-function-failure'
  location: location
  tags: tags
  properties: {
    displayName: 'エディタ用 OpenAI 運用 Function の実行失敗'
    description: 'rotate_key / hard_stop / notify_soft の失敗（regenerate 成功 + Teams 通知失敗を含む）を検知'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT30M'
    scopes: [
      appInsightsId
    ]
    criteria: {
      allOf: [
        {
          query: 'requests | where success == false'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
    actions: {
      actionGroups: [
        agOps.id
      ]
    }
  }
}
