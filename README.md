# エディタ用 Azure OpenAI (Foundry) 基盤

社内メンバーがエディタ（Zed / VS Code）から API キーで利用する Azure AI Foundry エンドポイント。
用途は **コーディングエージェント** と **ログ解析**。利用者は複数モデルを **deployment 名で切り替えて**使う。

**目的**: 業務データ（社内コード・ログ）を社外・国外の LLM SaaS に送らずに済ませ、**データ越境リスクを低減する**こと。
**国内リージョン（japaneast）に立てた自社管理リソース（`kind: AIServices`）**に閉じ、OpenAI / 非 OpenAI（DeepSeek 等）の
**複数モデルを混在配備**する。データ処理範囲は deployment ごとの SKU で決まる（保管は全モデル日本国内固定）:

| deployment（既定） | モデル | 処理範囲 | 用途 |
|---|---|---|---|
| `gpt41mini-jp` | gpt-4.1-mini (OpenAI) | 🇯🇵 国内完結 | 既定・軽量コーディング/ログ解析 |
| `gpt5codex-apac` | gpt-5.3-codex (OpenAI) | 🌏 APAC（越境） | 高性能コーディング |
| `deepseek-apac` | DeepSeek-V4-Pro (非OpenAI) | 🌏 APAC（越境） | 代替の高性能コーディング |

利用者は違い（越境・コスト）を認識のうえ選択する前提。deployment 名の `-jp`/`-apac` で処理範囲が分かる。
全モデルは共通の `openai/v1` エンドポイント + 共通キーで使え、エディタ設定は 1 プロバイダで済む。

- 原本指示書: [foundry-editor-access-instruction.md](foundry-editor-access-instruction.md)
- 設計書: [docs/design.md](docs/design.md)

## SKU（環境）とデータ処理範囲

「どこでデータが処理されるか」が SKU で決まる。越境リスクと使えるモデルはトレードオフの関係にある。

| SKU（環境） | 保管 (at rest) | 推論処理 | 越境リスク | 本基盤での位置づけ |
|---|---|---|---|---|
| **regional Standard** | 日本国内 | **japaneast 単独** | 最小（国内完結） | ✅ 採用（`*-jp` 既定） |
| DataZone Standard | 日本国内 | アジア太平洋圏内 | 中（**米国は含まない**） | ✅ 採用（`*-apac` 高性能/DeepSeek） |
| Global Standard | 日本国内 | 全世界 | 大（**米国を含む**） | 非採用 |

### 「保管」と「処理」の違い（なぜ環境で越境リスクが変わるか）

データの持ち方は 2 層に分かれる。**3 つの SKU で「保管」は同じ（日本国内）**で、違うのは**「処理」の場所だけ**。

| 層 | 意味 | 3 SKU での違い |
|---|---|---|
| **保管 (at rest)** | ディスクに保存されるデータ（学習ファイル・バッチ入出力・保存された会話など）の物理保管先 | **違わない** — 3 つとも指定 geography = **日本国内** |
| **処理 (inference)** | 送ったプロンプトを実際に計算し応答を返す**データセンターの場所** | **これだけが違う**（下図） |

```
                 保管(at rest)        処理(inference)
regional  │   🇯🇵 日本国内     →   🇯🇵 japaneast 単独（国外に出ない）
DataZone  │   🇯🇵 日本国内     →   🌏 アジア太平洋圏内（日本以外のAPAC各国もあり得る）
Global    │   🇯🇵 日本国内     →   🌐 全世界（処理国を特定できない）
```

- チャット/コーディング用途ではプロンプト本文は基本ディスク保管されない（ステートレス処理）。
  そのため越境の実体は **「処理のために一瞬どのデータセンターを通るか」**。保管先が同じ日本でも、
  この処理経路が国外を通るかどうかで `regional < DataZone < Global` の順にリスクが上がる
- Azure OpenAI は既定でプロンプトをモデル学習に使わない。別枠の不正利用モニタリング（最大 30 日保存）は
  承認を得てデータ非保持に無効化可能で、この保存も geography 内（日本）に留まる

## 使えるモデル × 環境マトリクス（japaneast / 2026-07 時点）

チャット／コーディング用途で関係するモデルのみ抜粋。◯=提供あり、−=提供なし。
**最新の提供状況は必ず下記コマンドで確認すること**（新モデルが追加され得る）。

| モデル | regional Standard（国内完結） | DataZone Standard（APAC） | Global Standard（全世界） |
|---|:---:|:---:|:---:|
| gpt-4o (2024-11-20) | ◯ | − | ◯ |
| **gpt-4.1-mini** (2025-04-14) | **◯ ← 既定** | − | ◯ |
| gpt-4.1 (2025-04-14) | − | − | ◯ |
| gpt-5.2 | − | ◯ | ◯ |
| gpt-5.3-codex | − | ◯ | ◯ |
| gpt-5.4-mini | − | ◯ | ◯ |
| gpt-5.4 / gpt-5.5 / gpt-5.6-* | − | − | ◯ |

要点:
- **国内完結（regional Standard）で使えるチャットモデルは実質 `gpt-4o` と `gpt-4.1-mini` のみ**。GPT-5 系は不可
- **GPT-5 系が必要な場合の最小越境は DataZone Standard**（`gpt-5.4-mini` / `gpt-5.3-codex` 等、処理はアジア太平洋圏内）
- 最新版・最上位モデル（gpt-5.6 等）は Global Standard のみ

```bash
# japaneast で実際に使えるモデルと対応 SKU を確認
az cognitiveservices account list-models -n <account> -g <rg> \
  --query "[?kind=='OpenAI'].{model:name, version:version, skus:skus[].name}" -o table
```

SKU / モデルの変更点は [infra/main.bicepparam](infra/main.bicepparam) の `modelDeployments` のみ
（各要素に任意の `sku` を指定可。省略時は regional Standard）。背景は [docs/design.md §1.1](docs/design.md)。

## 参考: 他ベンダーモデルの評価（japaneast / 2026-07 時点）

OpenAI 以外にも Azure から直接提供されるモデル（DeepSeek・xAI Grok・Mistral・Moonshot Kimi 等）がある。
コーディング / ログ解析用途で候補になり得るものを、**環境（越境リスク）× 提供可否**で評価する。◯=提供あり、−=なし。

| モデル | ベンダー | 位置づけ（用途の目安） | regional（国内完結） | DataZone（APAC） | Global（全世界） |
|---|---|---|:---:|:---:|:---:|
| DeepSeek-V4-Pro | DeepSeek | 推論・コーディング志向、コスト効率が高いとされる | − | ◯ | ◯ |
| DeepSeek-V4-Flash | DeepSeek | 上記の軽量・低コスト版 | − | ◯ | ◯ |
| DeepSeek-V3.1 / V3.2 | DeepSeek | 前世代。ログ解析など汎用 | − | − | ◯ |
| grok-4.3 | xAI | 大規模推論、長文脈 | − | ◯ | ◯ |
| grok-4-1-fast (reasoning) | xAI | 低レイテンシ・推論バランス型 | − | ◯ | ◯ |
| Mistral-Large-3 | Mistral (EU) | 汎用・多言語、欧州ベンダー | − | ◯ | ◯ |
| mistral-medium-3-5 | Mistral (EU) | 中量・コスト効率 | − | ◯ | ◯ |
| Kimi-K2.7-Code | Moonshot | **コーディング特化** | − | − | ◯ |
| Llama-4-Maverick | Meta | オープンウェイト系汎用 | − | − | ◯ |
| Phi-4 / Phi-4-reasoning | Microsoft | 小型・低コスト、軽い解析向き | − | − | ◯ |

### 評価の要点

- **国内完結（regional Standard）に非 OpenAI のチャットモデルは 1 つも無い**。
  データを日本国外に一切出さない前提を貫くなら、選択肢は実質 OpenAI の `gpt-4.1-mini` / `gpt-4o` に限られる
- **DataZone（APAC 内処理）まで許容すると幅が広がる**:
  - コーディング → `DeepSeek-V4-Pro`、`grok-4.3`、`gpt-5.3-codex`(OpenAI) が有力候補
  - ログ解析 → `mistral-medium-3-5`、`DeepSeek-V4-Flash`、`gpt-5.4-mini`(OpenAI) がコスト効率良
- **コーディング特化の Kimi-K2.7-Code や最小・低コストの Phi-4 は Global のみ**（越境大）

### リソース種別（本基盤は対応済み）

非 OpenAI モデルは「Foundry Models sold by Azure」で、**Azure AI Foundry リソース（`kind: AIServices`）**が必要。
**本基盤は `kind: AIServices` を採用済み**のため、OpenAI モデルと非 OpenAI モデル（DeepSeek 等）を同一リソースに
混在配備できる。全モデルは共通の `openai/v1` エンドポイント + 共通 api-key で使え、エディタ側は 1 プロバイダで済む
（deployment 名で切替）。residency の SKU 概念（regional / DataZone / Global）は全モデル共通。

> 上表は提供可否（事実）に基づく。モデルの能力評価はベンダーの位置づけに基づく参考であり、
> 実採用時は対象タスクでの実測（同一プロンプトで A/B 比較）を推奨する。提供状況は
> [Foundry Models 提供リージョン表](https://learn.microsoft.com/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability) で最新を確認すること。

## 構成

| パス | 内容 |
|---|---|
| `infra/` | bicep 一式。`main.bicepparam` が環境ごとの編集ポイント（IP 台帳・モデル・予算） |
| `functions/` | 運用 Functions（週次キーローテーション / ハードリミット停止 / ソフト通知） |
| `kql/` | 月次利用量レポートのクエリ |
| `prompts/` | 用途別システムプロンプト（エディタのプロファイルに設定） |
| `scripts/` | デプロイ・疎通確認 |
| `docs/` | 設計書・runbook・利用者向けセットアップ・利用規約 |

## デプロイ手順

```bash
# 0. 前提: az login / az account set 済み、Power Automate の webhook フロー作成済み
# 1. infra/main.bicepparam の TODO（IP 台帳・運用者メール・予算・開始日）を実値に置換

# 2. デプロイ（what-if 確認 → yes で適用）
export TEAMS_WEBHOOK_URL='https://...'
./scripts/deploy.sh --first-run     # 初回のみ --first-run（key1 を Key Vault へ初期投入）

# 3. Functions のコードデプロイ
cd functions && func azure functionapp publish <functionAppName>   # deploy.sh の出力参照

# 4. 疎通確認
./scripts/smoke-test.sh <keyVaultName> <endpoint>

# 5. 受け入れ基準の実測（docs/design.md §8 の 7 項目）
```

2 回目以降のデプロイは `--first-run` を**付けない**（ローテーション済みキーを上書きするため）。
ハードリミット発動中は再デプロイ禁止（[docs/runbook-hard-limit.md](docs/runbook-hard-limit.md)）。

## 利用者向け

- [docs/setup-zed.md](docs/setup-zed.md) / [docs/setup-vscode.md](docs/setup-vscode.md)
- [docs/usage-policy.md](docs/usage-policy.md) — 接続条件（オフィス回線/VPN）、キーの取り扱い、ログ記録範囲
- キーは毎週月曜 09:00 JST に自動ローテーション。Teams 通知後 1 週間以内に更新

## 運用者向け

- [docs/runbook-key-rotation.md](docs/runbook-key-rotation.md) — ローテーション失敗時・手動実行
- [docs/runbook-hard-limit.md](docs/runbook-hard-limit.md) — コスト 100% 到達で全停止した際の復旧（手動のみ）
- 月次レポート: [kql/monthly-usage.kql](kql/monthly-usage.kql)

## 開発

```bash
# bicep 検証
az bicep build --file infra/main.bicep

# Functions 単体テスト（Python 3.11+）
cd functions
python3 -m venv .venv && .venv/bin/pip install pytest requests
.venv/bin/python -m pytest tests
```
