from unittest.mock import MagicMock, call

import pytest

from shared import rotation
from shared.teams import TeamsNotificationError


def make_ops(active_slot):
    ops = MagicMock()
    ops.get_active_slot.return_value = active_slot
    ops.regenerate_key.return_value = "new-secret-key"
    return ops


class TestNextSlot:
    def test_key1_active_rotates_key2(self):
        assert rotation.next_slot("key1") == "key2"

    def test_key2_active_rotates_key1(self):
        assert rotation.next_slot("key2") == "key1"

    @pytest.mark.parametrize("active", [None, "", "unknown"])
    def test_missing_or_invalid_tag_defaults_to_key2(self, active):
        # slot タグ不明時は「key1 が配布中」とみなし、現用側を潰さない key2 を選ぶ
        assert rotation.next_slot(active) == "key2"


class TestRotate:
    def test_happy_path_regenerates_opposite_slot(self):
        ops = make_ops("key1")
        notifier = MagicMock()

        result = rotation.rotate(ops, notifier)

        assert result.new_slot == "key2"
        ops.regenerate_key.assert_called_once_with("key2")
        ops.store_key.assert_called_once_with("new-secret-key", slot="key2")
        notifier.post.assert_called_once_with(rotation.ROTATION_MESSAGE)

    def test_alternates_back_to_key1(self):
        ops = make_ops("key2")
        result = rotation.rotate(ops, MagicMock())
        assert result.new_slot == "key1"
        ops.regenerate_key.assert_called_once_with("key1")

    def test_store_happens_before_notify(self):
        ops = make_ops("key1")
        notifier = MagicMock()
        order = MagicMock()
        order.attach_mock(ops.store_key, "store")
        order.attach_mock(notifier.post, "post")

        rotation.rotate(ops, notifier)

        assert [c[0] for c in order.mock_calls] == ["store", "post"]

    def test_notify_failure_raises_after_key_stored(self):
        # 「regenerate 成功 + 通知失敗」は最悪パターン: キーは保存済みだが
        # 例外を握りつぶさず関数を失敗させ、運用者アラートに乗せる
        ops = make_ops("key1")
        notifier = MagicMock()
        notifier.post.side_effect = TeamsNotificationError("boom")

        with pytest.raises(TeamsNotificationError):
            rotation.rotate(ops, notifier)

        ops.store_key.assert_called_once()

    def test_regenerate_failure_does_not_store_or_notify(self):
        ops = make_ops("key1")
        ops.regenerate_key.side_effect = RuntimeError("regenerate failed")
        notifier = MagicMock()

        with pytest.raises(RuntimeError):
            rotation.rotate(ops, notifier)

        ops.store_key.assert_not_called()
        notifier.post.assert_not_called()
