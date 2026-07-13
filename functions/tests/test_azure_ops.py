from unittest.mock import MagicMock

from shared.azure_ops import AzureOps


def make_ops():
    """AzureOps を実 SDK なしで組み立てる（コンストラクタを迂回）。"""
    ops = AzureOps.__new__(AzureOps)
    ops._resource_group = "rg"
    ops._account_name = "acct"
    ops._secret_name = "editor-openai-key"
    ops._mgmt = MagicMock()
    ops._secrets = MagicMock()
    return ops


def test_regenerate_key_passes_capitalized_plain_string():
    # 回帰ガード: Azure API は keyName を 'Key1'/'Key2'（先頭大文字・プレーン文字列）で要求する。
    # 以前は dict {'key_name': 'key2'} かつ小文字を渡して BadRequest になっていた。
    ops = make_ops()
    api_keys = MagicMock(key1="k1-value", key2="k2-value")
    ops._mgmt.accounts.regenerate_key.return_value = api_keys

    result = ops.regenerate_key("key2")

    ops._mgmt.accounts.regenerate_key.assert_called_once_with("rg", "acct", "Key2")
    assert result == "k2-value"


def test_regenerate_key1_returns_key1_value():
    ops = make_ops()
    ops._mgmt.accounts.regenerate_key.return_value = MagicMock(key1="k1", key2="k2")

    result = ops.regenerate_key("key1")

    ops._mgmt.accounts.regenerate_key.assert_called_once_with("rg", "acct", "Key1")
    assert result == "k1"


def test_store_key_sets_secret_with_slot_tag():
    ops = make_ops()
    ops.store_key("new-secret", slot="key2")
    ops._secrets.set_secret.assert_called_once_with(
        "editor-openai-key", "new-secret", tags={"slot": "key2"}
    )


def test_get_active_slot_reads_tag():
    ops = make_ops()
    secret = MagicMock()
    secret.properties.tags = {"slot": "key1"}
    ops._secrets.get_secret.return_value = secret
    assert ops.get_active_slot() == "key1"


def test_get_active_slot_none_when_missing():
    ops = make_ops()
    ops._secrets.get_secret.side_effect = Exception("not found")
    assert ops.get_active_slot() is None
