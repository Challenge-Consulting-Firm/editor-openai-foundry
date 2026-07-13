"""エディタ用 Azure OpenAI 運用 Functions（Python v2 プログラミングモデル）。

- rotate_key:   週次キーローテーション（timer）
- hard_stop:    Budget 100% Actual で api-key 全停止（Action Group webhook から起動）
- notify_soft:  Budget ソフトリミット通知の Teams 転送（同上）

いずれも失敗時は例外で終了し、App Insights の失敗実行アラート
（infra/modules/budget.bicep の scheduledQueryRules）が運用者へメールする。
"""

import logging

import azure.functions as func

from shared import budget_alert, rotation
from shared.azure_ops import AzureOps
from shared.teams import TeamsNotifier

app = func.FunctionApp()

HARD_STOP_MESSAGE = (
    "【ハードリミット発動】エディタ用 OpenAI の月次予算が 100% に到達したため、"
    "api-key 認証を停止しました（disableLocalAuth: true）。"
    "復旧は手動のみです。runbook-hard-limit.md に従って対応してください。"
)


# UTC 月曜 00:00 = JST 月曜 09:00（利用者が即日キー更新できる時間帯）
@app.timer_trigger(schedule="0 0 0 * * Mon", arg_name="timer", run_on_startup=False)
def rotate_key(timer: func.TimerRequest) -> None:
    result = rotation.rotate(AzureOps.from_env(), TeamsNotifier.from_env())
    logging.info("キーローテーション完了: slot %s -> %s", result.previous_slot, result.new_slot)


@app.route(route="hard_stop", auth_level=func.AuthLevel.FUNCTION, methods=["POST"])
def hard_stop(req: func.HttpRequest) -> func.HttpResponse:
    logging.warning("ハードリミット発動リクエストを受信")
    AzureOps.from_env().disable_local_auth()
    logging.warning("disableLocalAuth=true へ更新完了（api-key 全停止）")
    # 停止は完了済み。通知失敗はここで例外化し、失敗アラート経由で運用者に届ける
    TeamsNotifier.from_env().post(HARD_STOP_MESSAGE)
    return func.HttpResponse("hard stop executed", status_code=200)


@app.route(route="notify_soft", auth_level=func.AuthLevel.FUNCTION, methods=["POST"])
def notify_soft(req: func.HttpRequest) -> func.HttpResponse:
    message = budget_alert.format_soft_alert(req.get_body())
    TeamsNotifier.from_env().post(message)
    return func.HttpResponse("notified", status_code=200)
