import json

from shared.budget_alert import format_soft_alert


def test_formats_budget_notification_payload():
    body = json.dumps({
        "schemaId": "AIP Budget Notification",
        "data": {
            "BudgetName": "budget-editor-openai",
            "SpendingAmount": "75000",
            "NotificationThresholdAmount": "75",
            "Unit": "JPY",
        },
    })

    message = format_soft_alert(body)

    assert "budget-editor-openai" in message
    assert "75000" in message
    assert "ハードリミット" in message


def test_falls_back_on_unknown_payload():
    for body in [None, b"", b"not-json", b"[1,2,3]"]:
        message = format_soft_alert(body)
        assert "ソフトリミット" in message
