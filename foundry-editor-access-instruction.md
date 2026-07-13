# 指示書: エディタ用 Azure OpenAI (Foundry) リソース払い出し

対象: Zed / VS Code 等のコードエディタから API キーで利用する専用 Azure OpenAI リソースの新規構築。
既存の他用途 Azure OpenAI リソースとは完全分離し、相乗りしない。

## 1. 目的・スコープ

- 社内メンバーがエディタ（Zed の `openai_compatible` provider、VS Code Copilot BYOK / Continue 等）から利用する Azure OpenAI エンドポイントを提供する
- 認証はエディタの制約上 **api-key**（Entra ID token はエディタに自動更新機構が無く不可）
- key 認証の弱点（identity 非追跡・流出リスク）を、以下 3 点で補償する
  1. 専用 API キー + 週次自動ローテーション + Teams 通知
  2. グローバル IP アドレスによる allowlist（ネットワーク層防御）
  3. コスト上限（ソフト 3 段階 + ハード 1 つ）

## 2. リソース構成

| リソース | 用途 |
|---|---|
| Cognitive Services アカウント（kind: OpenAI、region: japaneast） | エディタ用エンドポイント。既存リソースとは別 RG に新規作成 |
| モデル deployment | **DataZoneStandard** SKU。deployment 名 = モデル ID（例 `gpt-5.4-mini`）。capacity（TPM）は控えめに開始 |
| Key Vault | ローテーション後のキー保管。利用者には RBAC（`Key Vault Secrets User`）で read 権限付与 |
| Azure Functions（timer trigger）or Automation Runbook | 週次キーローテーション実行 |
| Teams Workflows webhook | ローテーション完了通知の投稿先（旧 O365 Incoming Webhook connector は廃止済み。Power Automate の「Webhook 要求を受信したとき」フローを使う） |
| Cost Management Budget + Action Group | ソフト/ハードリミット |
| Log Analytics + 診断設定 | RequestResponse ログ（呼び出し元 IP・deployment 別の利用量監査） |

補足:
- 同一サブスクリプションに Global 系 SKU を deny する Azure Policy がある前提でも、DataZoneStandard なら影響なし。別サブスクリプションでも SKU は DataZoneStandard に揃える（residency 方針の一貫性）
- `disableLocalAuth: false` を維持（true にすると api-key が全滅する）。ハードリミット発動の停止手段としてのみ true 化を使う（後述）

## 3. 要件 R1: 専用 API キー + 週次自動ローテーション + Teams 通知

### 方式

Cognitive Services の key1 / key2 を **交互に regenerate** する（無停止ローテーション）:

1. 現在配布中の slot（例 key1）の**反対側**（key2）を regenerate
2. 新キーを Key Vault secret（例 `editor-openai-key`）へ新バージョンとして保存。現用 slot 名は secret の tag に記録
3. Teams へ通知を投稿
4. 利用者は 1 週間以内にエディタ設定を更新（旧キーは次回ローテまで有効 = 1 週間の猶予）
5. 翌週の実行で旧 slot を regenerate → 旧キー無効化、以後繰り返し

### Teams 投稿の内容（重要: キー本文を投稿しない）

**推奨**: 通知のみ投稿し、キー本体は Key Vault から各自取得させる。

- 投稿内容: 「エディタ用 API キーをローテーションした。旧キーは YYYY-MM-DD に失効。取得: `az keyvault secret show --vault-name <KV> --name editor-openai-key --query value -o tsv | pbcopy`（clipboard 直行、画面に出さない）」
- Teams メッセージは保持ポリシー・eDiscovery・転送で残留するため、キー平文の投稿は不可。要件の「Teams 投稿」は完了通知として満たす
- どうしてもキー本文の配布が必要な場合も Teams 平文は避け、期限付き共有（Key Vault + RBAC）を使う

### 実装スケルトン（Functions / Runbook 内。キーを stdout・ログに出さないこと）

```bash
RES=<resource-name>; RG=<rg>; KV=<keyvault>
ACTIVE=$(az keyvault secret show --vault-name $KV --name editor-openai-key --query "tags.slot" -o tsv)
NEXT=$([ "$ACTIVE" = "key1" ] && echo key2 || echo key1)

NEW_KEY=$(az cognitiveservices account keys regenerate \
  -n $RES -g $RG --key-name $NEXT --query $NEXT -o tsv)
az keyvault secret set --vault-name $KV --name editor-openai-key \
  --value "$NEW_KEY" --tags slot=$NEXT -o none
unset NEW_KEY

curl -sf -X POST "$TEAMS_WEBHOOK_URL" -H 'Content-Type: application/json' \
  -d '{"text":"エディタ用 OpenAI API キーをローテーションしました。Key Vault から新キーを取得してください。旧キーは次回ローテーション（1週間後）で失効します。"}'
```

- 実行 identity は Managed Identity。必要ロール: `Cognitive Services Contributor`（keys regenerate、対象リソーススコープ）+ `Key Vault Secrets Officer`
- 失敗時（regenerate 失敗・Teams 投稿失敗）は運用者へアラート（Action Group メール等）。**regenerate 成功 + 通知失敗**が最悪パターン（利用者が気づかず旧キー失効）なので、通知失敗は必ず検知する
- cron 例: 毎週月曜 09:00 JST（利用者が即日対応できる時間帯）

## 4. 要件 R2: IP allowlist（グローバル IP 制限）

リソースの `networkAcls` で defaultAction Deny + 許可 IP のみ通す:

```jsonc
// bicep 抜粋
properties: {
  publicNetworkAccess: 'Enabled'
  networkAcls: {
    defaultAction: 'Deny'
    ipRules: [
      { value: '<オフィス回線のグローバルIP>/32' }
      { value: '<VPN egress IP>/32' }
    ]
  }
}
```

運用上の注意:
- **自宅回線など動的 IP の利用者は直接接続不可**。オフィス回線 or 会社 VPN 経由を利用条件とする（利用者向け案内に明記）
- IP の追加・削除は IaC（bicep + パラメータファイル）で管理し、台帳（誰の申請でいつ追加したか）を残す
- allowlist 変更の反映は数分。403 になった場合の一次切り分けは「接続元 IP が allowlist に載っているか」（`curl ifconfig.me` で自 IP 確認）

## 5. 要件 R3: コスト上限（ソフト 3 段階 + ハード 1）

前提知識: **Azure OpenAI にネイティブの支出ハードストップは無い**。Cost Management Budget は「通知」であり超過しても止まらない。かつコストデータの反映に 8〜24 時間の遅延がある。ハードリミットは「遅延込みで数時間〜1日オーバーラン し得る近似的な停止」として設計する。

### ソフトリミット（3 段階）

月次 Budget（金額 M は運用者が決定。初期値の目安: 想定利用の 2〜3 倍）に対し **Actual cost** ベースで 3 閾値:

| 段階 | 閾値 | アクション |
|---|---|---|
| Soft-1 | 50% | Teams 通知（情報共有） |
| Soft-2 | 75% | Teams 通知 + 運用者メール（利用状況をレビュー） |
| Soft-3 | 90% | Teams 通知 + 運用者メール（ハード発動が近い旨を予告、抑制を依頼） |

- 通知経路: Budget → Action Group → (a) メール、(b) Teams は Logic App / Functions 経由で webhook 投稿（Action Group から Teams 直接投稿は不可）
- Forecasted（予測）アラートを併用してもよいが、段階数にはカウントしない

### ハードリミット（1 つ）

- 閾値: **100%**（Actual）
- 動作: Action Group → Azure Functions が対象リソースを **`disableLocalAuth: true`** に更新（api-key 認証を即時全停止。Entra ID 経路のみ残るがエディタ利用者は使えなくなる = 事実上の全停止）
- 併せて Teams へ「ハードリミット発動。エディタ用 OpenAI を停止した」を投稿
- **復旧は手動のみ**: 運用者が原因確認のうえ `disableLocalAuth: false` へ戻す（自動復旧は入れない）。手順を runbook 化する
- 代替停止手段の比較（実装時に選択可、既定は disableLocalAuth）:
  - `networkAcls` を空 allowlist 化 → 効果同等だが IaC の IP 台帳と状態がずれる
  - 両キー regenerate → 停止になるがローテーション状態管理と干渉する
  - deployment 削除 → 再作成コスト・quota 再確保リスクがあり不可

### 補助ガード（推奨・要件外）

- deployment の **capacity（TPM）を小さく**保つ。TPM はスループット上限としてコストの実効上限に効く（例: 50K TPM なら理論最大でも月コストは概算可能）。まずここで絞るのが最も確実
- 将来、利用者別クォータや真のトークン単位ハードキャップが必要になったら APIM の `azure-openai-token-limit` ポリシーを前段に置く（本フェーズではスコープ外）

## 6. 監査・ログ

- 診断設定で `RequestResponse` を Log Analytics へ転送
- api-key 呼び出しは caller identity がログに残らない。**追跡できるのは呼び出し元 IP・deployment・トークン量まで**であることを利用規約に明記（多人数で問題が出たら利用者別キー分離 or APIM subscription key 化を再検討）
- 月次で利用量レポート（KQL: deployment 別・日別トークン集計）を確認

## 7. 利用者向け設定（案内文に含める）

- エンドポイント: `https://<resource>.openai.azure.com/openai/v1/`（OpenAI 互換 v1。api-version 不要）
- キー取得: `az keyvault secret show --vault-name <KV> --name editor-openai-key --query value -o tsv | pbcopy`（**画面・履歴に出さない**）
- Zed: Settings → LLM Providers → Add OpenAI-compatible provider。api_url に上記 v1 URL、モデル名は deployment 名（= モデル ID）を登録。キーは UI（keychain 保管）から入力し settings.json に書かない
- VS Code: Copilot「Manage Models」の Azure、または Continue 等の拡張で同 URL + キーを設定
- 禁止事項: キーの共有・社外持ち出し、settings.json / dotfiles へのキー平文記載、リポジトリへのコミット
- キーは毎週月曜にローテーションされる。Teams 通知を受けたら 1 週間以内に更新（旧キーは次回ローテで失効）

## 8. 受け入れ基準

1. allowlist 外 IP からの呼び出しが 403 になること（実測）
2. allowlist 内 IP + 現行キーで chat completions が成功すること（Zed / VS Code 各 1 通り実測）
3. ローテーション実行後: 新キーで成功・Key Vault に新バージョン・Teams に通知が届き、**旧キーも次回ローテまで有効**であること
4. 2 回連続ローテーション後、初回のキーが 401 になること（失効確認）
5. Budget 閾値のテスト発火（Action Group の Test notifications は既存 receiver を拾わないため、**Portal の Test 機能**で確認）で Soft 通知が Teams / メールに届くこと
6. ハードリミット用 Functions を手動起動し、`disableLocalAuth: true` へ変わり api-key 呼び出しが 401 になること・手動復旧手順で戻ること
7. ローテーション処理の通知失敗が運用者アラートになること（webhook URL を一時的に壊して実測）

## 9. リスク・留意事項（合意済みとして進めてよい前提）

- ハードリミットはコストデータ遅延により **最大 1 日程度のオーバーラン**があり得る。厳密な即時停止が必要なら APIM 前置を別途検討
- 週次ローテは利用者の手動更新を伴う。更新忘れ → 突然 401 の問い合わせが定常的に発生し得る（猶予 1 週間で緩和）
- Teams にキー平文を流さない設計とした。要件の「Teams 投稿」は完了通知として解釈。平文投稿が必須要件なら再協議
