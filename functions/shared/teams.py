"""Teams Workflows (Power Automate) webhook への通知。

前提: 「Webhook 要求を受信したとき」フローが {"text": "..."} 形式の JSON を
受け取り、チャネルへ投稿する構成（旧 O365 Incoming Webhook connector は廃止済み）。
フロー側の期待形式が異なる場合は _payload() のみ変更する。

注意: ローテ通知（rotation_message）は方針変更により新キー本文を含む。
Teams チャネルは利用者限定であることが前提（docs/design.md §3）。
"""

import logging
import time

import requests

logger = logging.getLogger(__name__)


class TeamsNotificationError(Exception):
    """リトライしても Teams への投稿に失敗した。"""


class TeamsNotifier:
    def __init__(self, webhook_url: str, *, max_attempts: int = 3, backoff_seconds: float = 5.0,
                 session: requests.Session | None = None):
        if not webhook_url:
            raise ValueError("webhook_url が空です（TEAMS_WEBHOOK_URL / Key Vault 参照を確認）")
        self._url = webhook_url
        self._max_attempts = max_attempts
        self._backoff = backoff_seconds
        self._session = session or requests.Session()

    @classmethod
    def from_env(cls) -> "TeamsNotifier":
        import os

        return cls(os.environ.get("TEAMS_WEBHOOK_URL", ""))

    @staticmethod
    def _payload(message: str) -> dict:
        return {"text": message}

    def post(self, message: str) -> None:
        last_error: Exception | None = None
        for attempt in range(1, self._max_attempts + 1):
            try:
                res = self._session.post(self._url, json=self._payload(message), timeout=15)
                res.raise_for_status()
                return
            except requests.RequestException as exc:
                last_error = exc
                logger.warning("Teams 投稿失敗 (%s/%s): %s", attempt, self._max_attempts, exc)
                if attempt < self._max_attempts:
                    time.sleep(self._backoff * attempt)
        raise TeamsNotificationError(
            f"Teams への通知に {self._max_attempts} 回失敗しました"
        ) from last_error
