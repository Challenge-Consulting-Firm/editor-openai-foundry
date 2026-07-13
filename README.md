# エディタ用 Azure OpenAI (Foundry) 基盤

社内メンバーがエディタ（Zed / VS Code）から API キーで利用する Azure AI Foundry エンドポイント。
用途は **コーディングエージェント** と **ログ解析**。利用者は複数モデルを **deployment 名で切り替えて**使う。

**目的**: 業務データ（社内コード・ログ）を社外・国外の LLM SaaS に送らずに済ませ、**データ越境リスクを低減する**こと。
**国内リージョン（japaneast）に立てた自社管理リソース（`kind: AIServices`）**に閉じ、OpenAI / 非 OpenAI（DeepSeek 等）の
**複数モデルを混在配備**する。データ処理範囲は deployment ごとの SKU で決まる（保管は全モデル日本国内固定）:

| deployment | モデル | 処理範囲 | フェーズ |
|---|---|---|---|
| `gpt5-apac` | gpt-5.2 (OpenAI) | 🌏 APAC（越境） | 1（既定・主力。コーディング/ログ解析とも） |
| `deepseek-apac` | DeepSeek-V4-Pro (非OpenAI) | 🌏 APAC（越境） | 2（AIServices 作成後に確認して追加） |

> gpt-5.2 を採用した理由: **codex 系（gpt-5.3-codex）は Chat Completions API 非対応**（Responses API 専用）で
> Zed/VS Code から使えないため。詳細は下記「実測で分かった制約」。

> ⚠️ **国内完結（regional Standard）チャットは 2026-07 時点の japaneast で配備できない**（対応モデルが Deprecating）。
> 詳細は下記「[実測で分かった制約](#実測で分かった制約japaneast--2026-07)」。現状フェーズ1は DataZone（APAC 処理）で構成する。
> 保管は全モデル日本国内のままだが、推論は APAC 圏になる。

利用者は違い（越境・コスト）を認識のうえ選択する前提。deployment 名の `-apac` で処理範囲が分かる。
全モデルは共通の `openai/v1` エンドポイント + 共通キーで使え、エディタ設定は 1 プロバイダで済む。

非OpenAIモデルは AIServices アカウント作成後でないと `list-models` で確認できないため、
**まず OpenAI モデルで構築 → DeepSeek 等を確認して追加**する段階デプロイを推奨（[docs/deploy-staged.md](docs/deploy-staged.md)）。

- 原本指示書: [foundry-editor-access-instruction.md](foundry-editor-access-instruction.md)
- 設計書: [docs/design.md](docs/design.md)

## SKU（環境）とデータ処理範囲

「どこでデータが処理されるか」が SKU で決まる。越境リスクと使えるモデルはトレードオフの関係にある。

| SKU（環境） | 保管 (at rest) | 推論処理 | 越境リスク | 本基盤での位置づけ |
|---|---|---|---|---|
| **regional Standard** | 日本国内 | **japaneast 単独** | 最小（国内完結） | ⚠️ 採用したいが**現状チャット配備不可**（後述） |
| DataZone Standard | 日本国内 | アジア太平洋圏内 | 中（**米国は含まない**） | ✅ 採用（`*-apac`。フェーズ1の配備先） |
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
| gpt-4o (2024-11-20) | ◯ ⚠️Deprecating | − | ◯ |
| gpt-4.1-mini (2025-04-14) | ◯ ⚠️Deprecating | − | ◯ |
| gpt-4.1 (2025-04-14) | − | − | ◯ |
| gpt-5.2 | − | ◯ | ◯ |
| gpt-5.3-codex | − | ◯ | ◯ |
| gpt-5.4-mini | − | ◯ | ◯ |
| gpt-5.4 / gpt-5.5 / gpt-5.6-* | − | − | ◯ |

要点（提供表ベース。ただし配備可否は下記「実測で分かった制約」を必ず参照）:
- regional Standard（国内完結）でチャットに使えるのは `gpt-4o` / `gpt-4.1-mini` のみ。しかも**両方 Deprecating で新規デプロイ不可**
- **GPT-5 系が必要な場合の最小越境は DataZone Standard**（`gpt-5.2` / `gpt-5.3-codex` / `gpt-5.4-mini` 等、処理はアジア太平洋圏内）
- 最新版・最上位モデル（gpt-5.6 等）は Global Standard のみ

```bash
# japaneast で実際に使えるモデルと対応 SKU を確認
az cognitiveservices account list-models -n <account> -g <rg> \
  --query "[?kind=='OpenAI'].{model:name, version:version, skus:skus[].name}" -o table
```

SKU / モデルの変更点は [infra/main.bicepparam](infra/main.bicepparam) の `defaultModelDeployments`
（各要素に `sku` / `format` を指定可。省略時は Standard / OpenAI）、または `.env` の `MODEL_DEPLOYMENTS`。
背景は [docs/design.md §1.1](docs/design.md)。

## 実測で分かった制約（japaneast / 2026-07）

`list-models`（提供有無）だけでは配備できない。**lifecycle（Deprecating）と quota（空き TPM）**の両方を満たす必要がある。
実際に what-if / デプロイ検証して判明した制約:

### 1. 国内完結（regional Standard）チャットは現状デプロイ不可

- regional Standard 対応のチャットは `gpt-4o (2024-11-20)` / `gpt-4.1-mini (2025-04-14)` のみ
- **両方とも lifecycle が `Deprecating`（2026-10 提供終了）で、新規デプロイがブロックされる**
  （preflight: *"model ... is in deprecating state and cannot be used for new deployments"*）
- → **推論を japaneast 単独に閉じる構成は、対応する非 Deprecating モデルが出るまで取れない**
- 保管は日本国内のままなので、当面は DataZone（APAC 処理）で運用する

### 2. DataZone は GA だが quota は別枠・枯渇し得る

- DataZone の TPM quota は regional Standard とは**別枠**で、モデル × SKU ごとにサブスクリプション単位で管理される
- 同一サブスクリプションの既存デプロイが quota を消費していると、モデルが GA でも空きが足りず配備できない
- 配備前に空き TPM（`limit - currentValue`）が必要 capacity 以上あることを確認する（下記チェックリスト (b)）

### 3. codex 系は Chat Completions 非対応（Responses API 専用）

- **`gpt-5.3-codex` は `chatCompletion: false` / `responses: true`**。実測で Chat Completions は 400
  （*"The requested operation is unsupported."*）、Responses API は 200 で正常応答
- **Zed の `openai_compatible` / VS Code Continue・Copilot BYOK は Chat Completions API を使う** → codex は使えない
  （Codex CLI 等 Responses API クライアントなら可）
- → エディタ用途では **chatCompletion=true のモデル**を選ぶこと。gpt-5.2 / gpt-5.4-mini が該当
- モデルの対応 API は list-models の `capabilities` で確認できる:

  ```bash
  az cognitiveservices account list-models -n <account> -g <rg> \
    --query "[?format=='OpenAI'].{model:name,ver:version,chat:capabilities.chatCompletion,resp:capabilities.responses}" -o table
  ```

### 4. デプロイ前チェックリスト

```bash
# (a) lifecycle 確認（Deprecating を避ける。GenerallyAvailable を選ぶ）
az cognitiveservices account list-models -n <account> -g <rg> \
  --query "[?format=='OpenAI'].{model:name,ver:version,life:lifecycleStatus,skus:join(',',skus[].name)}" -o table

# (b) quota（空き TPM）確認。free = limit - currentValue が capacity 以上あること
az cognitiveservices usage list -l japaneast \
  --query "[?contains(name.value,'DataZoneStandard')].{q:name.value,used:currentValue,limit:limit}" -o table

# (c) API 対応（chat/responses）確認 — 上の「3.」参照

# (d) テンプレート検証（read-only。実リソースは作られない）
./scripts/deploy.sh   # 内部で what-if → 確認プロンプト
```

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
  - ログ解析 → `mistral-medium-3-5`、`DeepSeek-V4-Flash`、`gpt-5.2`(OpenAI) など
- **コーディング特化の Kimi-K2.7-Code や最小・低コストの Phi-4 は Global のみ**（越境大）
- ⚠️ **エディタ（Zed/VS Code）は Chat Completions API 前提**。`gpt-5.3-codex` のような Responses API 専用モデルは
  そのままでは使えない（Codex CLI 等のクライアントなら可）。採用前に `capabilities.chatCompletion` を確認すること

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
| `.env.sample` | デプロイ環境変数のサンプル。`cp .env.sample .env` して実値を設定（`.env` は非コミット） |
| `infra/` | bicep 一式。`.env` から値を読む。モデル catalog は `main.bicepparam` の `defaultModelDeployments`（`.env` の `MODEL_DEPLOYMENTS` で上書き可） |
| `functions/` | 運用 Functions（週次キーローテーション / ハードリミット停止 / ソフト通知） |
| `kql/` | 月次利用量レポートのクエリ |
| `prompts/` | 用途別システムプロンプト（エディタのプロファイルに設定） |
| `scripts/` | デプロイ・疎通確認 |
| `docs/` | 設計書・runbook・利用者向けセットアップ・利用規約 |

## デプロイ手順

非OpenAIモデル（DeepSeek 等）は AIServices 作成後でないと提供確認できないため、
**段階デプロイを推奨**（フェーズ1: OpenAI 2モデル → フェーズ2: DeepSeek 等を確認して追加）。
詳細は **[docs/deploy-staged.md](docs/deploy-staged.md)**。以下はフェーズ1の流れ:

```bash
# 0. 前提: az login 済み、Power Automate の webhook フロー作成済み

# 1. .env を用意して実値を設定（IP allowlist・Teams webhook・運用者メール・予算 等）
cp .env.sample .env
$EDITOR .env

# 2. （任意）モデルを変えるなら main.bicepparam の defaultModelDeployments を編集、
#     または .env の MODEL_DEPLOYMENTS に JSON で指定（.env.sample の例参照）

# 3. デプロイ（.env を読み込み → what-if 確認 → yes で適用）
./scripts/deploy.sh --first-run     # 初回のみ --first-run（key1 を Key Vault へ初期投入）

# 4. Functions のコードデプロイ
cd functions && func azure functionapp publish <functionAppName>   # deploy.sh の出力参照

# 5. 疎通確認
./scripts/smoke-test.sh <keyVaultName> <endpoint>

# 6. 受け入れ基準の実測（docs/design.md §8 の 7 項目）
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
