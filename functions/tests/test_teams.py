from unittest.mock import MagicMock

import pytest
import requests

from shared.teams import TeamsNotificationError, TeamsNotifier


def make_response(status=200):
    res = MagicMock()
    if status >= 400:
        res.raise_for_status.side_effect = requests.HTTPError(f"{status}")
    else:
        res.raise_for_status.return_value = None
    return res


def make_notifier(session):
    return TeamsNotifier("https://example.test/webhook", backoff_seconds=0, session=session)


def test_posts_text_payload():
    session = MagicMock()
    session.post.return_value = make_response(200)

    make_notifier(session).post("hello")

    args, kwargs = session.post.call_args
    assert args[0] == "https://example.test/webhook"
    assert kwargs["json"] == {"text": "hello"}


def test_retries_then_succeeds():
    session = MagicMock()
    session.post.side_effect = [
        requests.ConnectionError("down"),
        make_response(500),
        make_response(200),
    ]

    make_notifier(session).post("hello")

    assert session.post.call_count == 3


def test_raises_after_max_attempts():
    session = MagicMock()
    session.post.side_effect = requests.ConnectionError("down")

    with pytest.raises(TeamsNotificationError):
        make_notifier(session).post("hello")

    assert session.post.call_count == 3


def test_empty_webhook_url_rejected():
    with pytest.raises(ValueError):
        TeamsNotifier("")


def test_message_never_contains_key_material():
    # 通知文言にキー平文を含めない設計（指示書 §9）の回帰ガード:
    # rotate 側は固定文言のみを渡す
    from shared.rotation import ROTATION_MESSAGE

    assert "key1" not in ROTATION_MESSAGE
    assert "key2" not in ROTATION_MESSAGE
