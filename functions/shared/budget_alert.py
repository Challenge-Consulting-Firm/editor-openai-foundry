"""Budget アラート webhook ペイロードの整形（notify_soft 用）。

Budget → Action Group → webhook のペイロードはスキーマ差異があり得るため、
既知フィールドを best-effort で拾い、拾えなければ汎用文言にフォールバックする。
"""

import json


def format_soft_alert(body: bytes | str | None) -> str:
    data = {}
    if body:
        try:
            payload = json.loads(body)
            # Budget 直接 webhook 形式: {"schemaId": "AIP Budget Notification", "data": {...}}
            data = payload.get("data", payload) if isinstance(payload, dict) else {}
        except (ValueError, TypeError):
            data = {}

    budget_name = data.get("BudgetName") or "editor-openai"
    threshold = data.get("NotificationThresholdAmount")
    spend = data.get("SpendingAmount")
    unit = data.get("Unit") or ""

    lines = [f"【コスト通知】エディタ用 OpenAI の予算 ({budget_name}) がソフトリミット閾値に達しました。"]
    if spend:
        lines.append(f"現在の実績: {spend} {unit}".rstrip())
    if threshold:
        lines.append(f"通知閾値: {threshold} {unit}".rstrip())
    lines.append("利用状況をレビューしてください。100% 到達でハードリミット（api-key 全停止）が発動します。")
    return "\n".join(lines)
