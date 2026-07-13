# 設計書: エディタ用 Azure OpenAI (Foundry) — コーディングエージェント & ログ解析基盤

原本: [foundry-editor-access-instruction.md](../foundry-editor-access-instruction.md)（払い出し指示書）。
本書は指示書を実装レベルに具体化したもの。要件の根拠・背景は原本を正とする。

## 1. 目的・用途

本基盤は、社内のコード・ログといった業務データを外部（社外・国外）の LLM サービスへ送らずに
LLM を利用できるようにし、**データ越境（クロスボーダー）リスクを低減する**ことを主目的とする。
汎用のパブリック LLM SaaS ではなく、**国内リージョン（japaneast）に立てた自社管理の Azure OpenAI**
に閉じることで、データの所在・処理範囲をコントロール下に置く。

社内メンバーがエディタ（Zed / VS Code）から API キーで利用する Azure OpenAI エンドポイントを提供する。
用途は 2 本立てとし、**1 つの Azure OpenAI リソース内の deployment 名で分離**する:

| 用途 | deployment 名 | モデル（例） | 想定 |
|---|---|---|---|
| コーディングエージェント | `agent-main` | `gpt-5.4` | Zed Agent / VS Code (Copilot BYOK, Continue) からのコード生成・編集 |
| ログ解析 | `log-analysis` | `gpt-5.4-mini` | エンジニアがログを貼り付けて対話的に解析 |

使い分けはエディタ側のプロファイル + システムプロンプト（[prompts/](../prompts/)）で行う。
deployment を分けることで、共通キーのままでも KQL レポートで用途別の利用量・コストを追跡できる。

- 認証: **api-key のみ**（エディタに Entra ID トークンの自動更新機構が無いため）
- 既存 OPSNOTE 用リソース（prod / eval）とは**別リソースグループに完全分離**
- key 認証の弱点は 3 点で補償: ①週次キーローテーション（R1）、②IP allowlist（R2）、③コスト上限（R3）

### 1.1 データ所在・越境リスクの方針（前提）

本基盤は **国内リージョン japaneast に構築する前提**とし、SKU は **DataZoneStandard** を採用する
（指示書の「residency 方針の一貫性」に対応）。データの扱いは以下のとおり:

| 区分 | 範囲 | 根拠 |
|---|---|---|
| **保管（データ at rest）** | 指定した Azure geography = **日本国内**に留まる | DataZone / 非 Global 共通の挙動 |
| **推論処理（inference）** | Microsoft が定義する**データゾーン内**で処理される（Global SKU のように全世界へ動的ルーティングされない） | DataZoneStandard の仕様 |

- **越境リスク低減の効果**: Global Standard は「可用性最優先で世界中のデータセンターへ動的ルーティング」するのに対し、
  DataZoneStandard は処理をデータゾーン境界内に限定するため、**国外へ業務データが出るリスクを大きく下げる**
- **重要な注意（過大評価しないこと）**: DataZoneStandard の「データゾーン」は日本単独とは限らず、
  Microsoft 定義の地理境界（アジア太平洋を含み得る）である。**推論処理を japaneast 単独に厳密に閉じたい**場合は、
  regional の `Standard`（Azure Geography）SKU を選ぶ必要がある。要件が「国内処理のみ」なら本 SKU の再検討が必要
  （[deployment types 公式ドキュメント](https://learn.microsoft.com/azure/ai-foundry/openai/how-to/deployment-types) で最新のデータゾーン境界を確認すること）
- Azure OpenAI は既定で**入力プロンプトをモデル学習に使用しない**構成（プロンプトが OpenAI 社や第三者の学習に回らない）
- 同一サブスクリプションに Global 系 SKU を deny する Azure Policy がある前提でも、DataZoneStandard なら影響を受けない（指示書の補足）
- 別サブスクリプションに立てる場合も SKU は DataZoneStandard に揃え、residency 方針の一貫性を保つ

> SKU を切り替える場合の唯一の編集ポイントは [infra/main.bicepparam](../infra/main.bicepparam) の `modelDeployments`
> と [infra/modules/openai.bicep](../infra/modules/openai.bicep) の `sku.name`。`location` も同ファイル群のパラメータで管理する。

## 2. 全体構成

```
                        ┌─────────────────────── rg-editor-openai ────────────────────────┐
  Zed / VS Code         │                                                                  │
  (オフィス/VPN IP)      │  ┌──────────────────────────┐      ┌───────────────────────┐    │
  ──── api-key ────────▶│  │ Azure OpenAI (japaneast)  │─diag▶│ Log Analytics          │    │
       /openai/v1/      │  │  networkAcls: Deny+許可IP │      │  RequestResponse       │    │
                        │  │  deployments:             │      │  + AllMetrics          │    │
                        │  │   - agent-main            │      └───────────────────────┘    │
                        │  │   - log-analysis          │              ▲ App Insights       │
                        │  │  (DataZoneStandard)       │              │                    │
                        │  └──────────▲────────────────┘      ┌──────┴────────────────┐    │
                        │             │ keys regenerate /     │ Function App (Python)  │    │
                        │             │ disableLocalAuth      │  - rotate_key (timer)  │    │
  利用者 ◀─ Secrets User─┼─┐          └───────────────────────│  - hard_stop  (http)   │    │
  (az keyvault ... show)│ │                                   │  - notify_soft (http)  │    │
                        │ ▼                                   └──▲──────────────▲──────┘    │
                        │ ┌──────────────────┐    Managed Identity│              │          │
                        │ │ Key Vault        │◀───────────────────┘   Action Group (webhook)│
                        │ │  editor-openai-  │                            ▲                 │
                        │ │  key (slot tag)  │                            │                 │
                        │ │  teams-webhook-  │              ┌─────────────┴──────────┐      │
                        │ │  url             │              │ Budget (月次)           │      │
                        │ └──────────────────┘              │  50/75/90% → soft      │      │
                        │                                   │  100% Actual → hard    │      │
                        └───────────────────────────────────┴────────────────────────┴──────┘
                                                                     │
                                              Teams (Power Automate Workflows webhook)
```

### リソース一覧

| リソース | 名前（既定） | 備考 |
|---|---|---|
| Resource Group | `rg-editor-openai` | 既存リソースと分離 |
| Cognitive Services (kind: OpenAI) | `editor-aoai-<suffix>` | japaneast、custom subdomain、`disableLocalAuth: false` 維持 |
| モデル deployment ×2 | `agent-main` / `log-analysis` | **DataZoneStandard** SKU、TPM は各 50K から開始 |
| Key Vault | `kv-editor-aoai-<suffix>` | RBAC 認可。`editor-openai-key`（slot タグ付き）と `teams-webhook-url` |
| Function App (Python 3.11, Linux 従量) | `func-editor-aoai-<suffix>` | System-assigned Managed Identity |
| Log Analytics + App Insights | `log-` / `appi-editor-openai` | 診断ログ・Function 監視 |
| Budget + Action Group ×3 | `budget-editor-openai` | ag-teams（soft 通知）/ ag-ops（メール）/ ag-hardstop |

`<suffix>` は `uniqueString()` による自動生成。グローバル一意が必要な名前にのみ付与。

## 3. R1: 週次キーローテーション

`functions/` の `rotate_key`（timer trigger、NCRONTAB `0 0 0 * * Mon` = UTC 月曜 00:00 = **JST 月曜 09:00**）:

1. Key Vault `editor-openai-key` の `slot` タグから現用スロットを読む（`key1` / `key2`）
2. **反対側**のキーを `az cognitiveservices account keys regenerate` 相当の SDK 呼び出しで再生成
3. 新キーを `editor-openai-key` の新バージョンとして保存（`slot` タグを更新）
4. Teams webhook へ完了通知（キー平文は流さない）

- 旧キーは regenerate しない → **次回ローテーションまで 1 週間有効**（無停止ローテーション）
- 実行 identity: Function App の Managed Identity
  - `Cognitive Services Contributor`（OpenAI リソーススコープ）
  - `Key Vault Secrets Officer`（KV スコープ）
- **regenerate 成功 + 通知失敗が最悪パターン**のため、通知は 3 回リトライの上、失敗したら関数を失敗させる
  → App Insights の失敗実行を検知する scheduled query alert（15 分間隔）→ ag-ops へメール
- 初回のみ: `seedInitialKey=true` でデプロイすると key1 を KV へ初期投入（`slot=key1`）。**2 回目以降のデプロイでは必ず false**（ローテーション済みキーを上書きしてしまうため）

## 4. R2: IP allowlist

- `networkAcls.defaultAction: 'Deny'` + `ipRules`（オフィス回線 / VPN egress のグローバル IP）
- IP は [infra/main.bicepparam](../infra/main.bicepparam) の `allowedIps` で管理。**台帳（誰の申請・いつ追加）はコメントで必ず残す**
- 自宅回線など動的 IP の利用者は直接接続不可 → オフィス回線 or 会社 VPN 経由が利用条件（[usage-policy.md](usage-policy.md) に明記）
- 403 の一次切り分け: `curl ifconfig.me` で自 IP が allowlist にあるか確認（反映は数分）

## 5. R3: コスト上限（ソフト 3 段階 + ハード 1）

前提: Azure OpenAI にネイティブの支出ハードストップは無く、コストデータ反映に 8〜24 時間の遅延がある。
ハードリミットは**最大 1 日程度のオーバーランがあり得る近似停止**として設計（指示書 §9 で合意済み）。

月次 Budget（金額はパラメータ `monthlyBudgetAmount`、初期値は想定利用の 2〜3 倍）に対し **Actual** ベースで:

| 段階 | 閾値 | 経路 | アクション |
|---|---|---|---|
| Soft-1 | 50% | Budget → ag-teams → `notify_soft` | Teams 通知 |
| Soft-2 | 75% | 同上 + Budget の contactEmails | Teams + 運用者メール |
| Soft-3 | 90% | 同上 + Budget の contactEmails | Teams + メール（ハード発動予告） |
| **Hard** | **100%** | Budget → ag-hardstop → `hard_stop` | **`disableLocalAuth: true` へ更新**（api-key 即時全停止）+ Teams 投稿 + メール |

- Action Group から Teams への直接投稿は不可のため、webhook receiver で Function（`notify_soft` / `hard_stop`）を呼び、Function が Teams Workflows webhook へ投稿する
- **復旧は手動のみ**: [runbook-hard-limit.md](runbook-hard-limit.md)。自動復旧は入れない
- 代替停止手段（networkAcls 空化・両キー regenerate・deployment 削除）は指示書の比較どおり不採用
- 補助ガード: deployment の TPM を小さく保つ（コストの実効上限）。利用者別クォータが必要になったら APIM `azure-openai-token-limit` を前段に置く（本フェーズ外）

## 6. 監査・ログ

- 診断設定: `RequestResponse` + `AllMetrics` → Log Analytics
- api-key 呼び出しは caller identity が残らない。**追跡可能なのは呼び出し元 IP・deployment・トークン量まで**（[usage-policy.md](usage-policy.md) に明記）
- 月次レポート: [kql/monthly-usage.kql](../kql/monthly-usage.kql)（deployment 別・日別のリクエスト数 / トークン量、IP 別内訳）

## 7. IaC 構成

| ファイル | 内容 |
|---|---|
| `infra/main.bicep` | subscription スコープ。RG 作成 + 各モジュール接続 |
| `infra/main.bicepparam` | IP 台帳・モデル・TPM・予算・通知先。**環境ごとの唯一の編集ポイント** |
| `infra/modules/openai.bicep` | アカウント + networkAcls + deployments |
| `infra/modules/keyvault.bicep` | KV + webhook secret + （初回のみ）キー初期投入 + 利用者グループへ Secrets User 付与 |
| `infra/modules/monitoring.bicep` | Log Analytics + App Insights + 診断設定 |
| `infra/modules/functions.bicep` | Storage + 従量プラン + Function App（KV 参照のアプリ設定） |
| `infra/modules/rbac.bicep` | Function MI への Cognitive Services Contributor / KV Secrets Officer |
| `infra/modules/budget.bicep` | Action Group ×3 + Budget + Function 失敗アラート |

注意: ハードリミット発動後に IaC を再デプロイすると `disableLocalAuth` が `false` に戻る（= 意図せず復旧する）。
発動中の再デプロイは禁止。復旧手順は runbook に従う。

## 8. 受け入れ基準（指示書 §8 の実施方法）

| # | 基準 | 確認方法 |
|---|---|---|
| 1 | allowlist 外 IP → 403 | allowlist 外の回線から `scripts/smoke-test.sh` の curl |
| 2 | allowlist 内 + 現行キーで成功 | `scripts/smoke-test.sh`（両 deployment）+ Zed / VS Code 各 1 実測 |
| 3 | ローテーション後: 新キー成功・KV 新バージョン・Teams 通知・旧キー有効 | Portal から `rotate_key` を手動実行して確認 |
| 4 | 2 回連続ローテーション後に初回キーが 401 | 手動実行 ×2 で確認 |
| 5 | Budget ソフト通知が届く | **Portal の Action Group「Test」機能**で確認（Test notifications は既存 receiver を拾わない点に注意） |
| 6 | ハードリミット手動起動 → 401 → 手動復旧で回復 | `hard_stop` を curl で起動 → smoke-test 401 確認 → runbook 手順で復旧 |
| 7 | 通知失敗が運用者アラートになる | `teams-webhook-url` secret を一時的に壊して `rotate_key` 実行 → メール着信確認 |

## 9. 本設計で確定した実装判断

1. Teams 通知は **Power Automate Workflows の「Webhook 要求を受信したとき」フロー**を前提（旧 O365 コネクタは廃止済み）。ペイロードは `{"text": ...}`。フロー側の期待形式が異なる場合は `functions/shared/teams.py` の 1 箇所を直す
2. Budget → Function の連携は Action Group の **webhook receiver + Function の host key**（bicep の `listKeys` で解決）
3. エンドポイントは OpenAI v1 互換パス `https://<resource>.openai.azure.com/openai/v1/`（api-version 不要）で案内統一
4. タイマーは UTC 前提の NCRONTAB で JST 月曜 09:00 を表現（Linux 従量プランではタイムゾーン設定に依存しない）
