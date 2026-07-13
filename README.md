# エディタ用 Azure OpenAI (Foundry) 基盤

社内メンバーがエディタ（Zed / VS Code）から API キーで利用する Azure OpenAI エンドポイント。
用途は **コーディングエージェント**（deployment: `agent-main`）と **ログ解析**（`log-analysis`）の 2 本立て。

**目的**: 業務データ（社内コード・ログ）を社外・国外の LLM SaaS に送らずに済ませ、**データ越境リスクを低減する**こと。
**国内リージョン（japaneast）に立てた自社管理リソース**に閉じ、SKU は DataZoneStandard でデータ処理範囲をデータゾーン内に限定する。
※ 保管は日本国内、推論処理は Microsoft 定義のデータゾーン内。厳密な国内単独処理が要件なら SKU 再検討が必要
（詳細は [docs/design.md §1.1](docs/design.md)）。

- 原本指示書: [foundry-editor-access-instruction.md](foundry-editor-access-instruction.md)
- 設計書: [docs/design.md](docs/design.md)

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
