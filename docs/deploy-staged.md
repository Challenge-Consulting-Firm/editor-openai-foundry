# 段階デプロイ手順（推奨）

非 OpenAI モデル（DeepSeek 等）の提供可否・正確なモデル名/バージョン/format は、
**AIServices アカウントを作ってからでないと `list-models` で確認できない**（ニワトリ卵）。
そこで「まず確認済み OpenAI モデルでリソースを作り、その上で非OpenAIモデルを確認して足す」段階デプロイを推奨する。

`kind: OpenAI` の既存アカウント（例 OPSNOTE 用）では OpenAI モデルしか一覧に出ない点に注意。

---

## フェーズ1: OpenAI モデルでリソースを構築

`main.bicepparam` の既定 `defaultModelDeployments` は、japaneast で GA(配備可) を確認済みの OpenAI 2 モデル。
※ 国内完結(regional Standard)チャットは対応モデルが Deprecating のため現状不可 → 両方 DataZone(APAC):

| deployment | モデル | SKU | 処理範囲 |
|---|---|---|---|
| `gpt5codex-apac` | gpt-5.3-codex (2026-02-24) | DataZoneStandard | 🌏 APAC |

```bash
cp .env.sample .env
$EDITOR .env                          # IP・webhook・メール・予算を設定（MODEL_DEPLOYMENTS は空のまま）
./scripts/deploy.sh --first-run       # 初回のみ --first-run
cd functions && func azure functionapp publish <functionAppName>
./scripts/smoke-test.sh <keyVaultName> <endpoint>   # gpt5codex-apac が 200
```

## フェーズ2: 非OpenAIモデル（DeepSeek 等）を確認して追加

1. できた **AIServices アカウント**に対して提供モデルを確認（`<account>` はデプロイ出力の名前）:

   ```bash
   az cognitiveservices account list-models -n <account> -g rg-editor-openai \
     --query "[?format!='OpenAI'].{model:name, version:version, format:format, skus:join(',',skus[].name)}" -o table
   ```

   - `DeepSeek-V4-Pro` 等が `DataZoneStandard` 付きで出れば追加可能
   - **出力の name / version / format をそのまま使う**（推測しない）

2. モデルを追加する。どちらかの方法で:

   **(a) bicepparam に追記**（catalog を git 管理したい場合）
   `infra/main.bicepparam` の `defaultModelDeployments` に、コメントの phase2 例を実値で足す。

   **(b) .env の MODEL_DEPLOYMENTS で指定**（環境ごとに変えたい場合）
   `.env` の `MODEL_DEPLOYMENTS` に**3モデル分の 1 行 JSON**を設定（`.env.sample` の例参照）。
   ※ MODEL_DEPLOYMENTS は catalog 全体を上書きするので、既存 2 モデルも含めること。

3. 再デプロイ（`--first-run` は付けない）:

   ```bash
   ./scripts/deploy.sh
   ./scripts/smoke-test.sh <keyVaultName> <endpoint>   # deepseek-apac も 200 になる
   ```

## 注意

- **フェーズ2の再デプロイで `--first-run` / `SEED_INITIAL_KEY=true` を付けない**
  （ローテーション済みキーを初期キーで上書きしてしまう）
- ハードリミット発動中は再デプロイ禁止（[runbook-hard-limit.md](runbook-hard-limit.md)）
- 追加モデルが高単価なら `capacity`(TPM) を小さく設定してコストを封じ込める（[design.md §1.1](design.md)）
