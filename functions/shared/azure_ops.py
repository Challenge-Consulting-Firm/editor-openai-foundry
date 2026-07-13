"""Azure リソース操作の薄い wrapper。

Managed Identity (DefaultAzureCredential) で以下を行う:
- Key Vault: editor-openai-key の slot タグ読取・新バージョン保存
- Cognitive Services: keys regenerate / disableLocalAuth 更新

必要ロール（rbac.bicep で付与）:
- Cognitive Services Contributor（OpenAI リソーススコープ）
- Key Vault Secrets Officer（KV スコープ）
"""

import os

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.mgmt.cognitiveservices import CognitiveServicesManagementClient


class AzureOps:
    def __init__(self, *, subscription_id: str, resource_group: str, account_name: str,
                 key_vault_uri: str, secret_name: str, credential=None):
        self._credential = credential or DefaultAzureCredential()
        self._subscription_id = subscription_id
        self._resource_group = resource_group
        self._account_name = account_name
        self._secret_name = secret_name
        self._secrets = SecretClient(vault_url=key_vault_uri, credential=self._credential)
        self._mgmt = CognitiveServicesManagementClient(self._credential, subscription_id)

    @classmethod
    def from_env(cls) -> "AzureOps":
        return cls(
            subscription_id=os.environ["AZURE_SUBSCRIPTION_ID"],
            resource_group=os.environ["AOAI_RESOURCE_GROUP"],
            account_name=os.environ["AOAI_ACCOUNT_NAME"],
            key_vault_uri=os.environ["KEY_VAULT_URI"],
            secret_name=os.environ.get("KEY_SECRET_NAME", "editor-openai-key"),
        )

    def get_active_slot(self) -> str | None:
        """配布中キーのスロット（key1/key2）。初回投入前や tag 欠落時は None。"""
        try:
            secret = self._secrets.get_secret(self._secret_name)
        except Exception:
            return None
        return (secret.properties.tags or {}).get("slot")

    def regenerate_key(self, key_name: str) -> str:
        """指定スロットのキーを再生成し、新しいキー値を返す。"""
        keys = self._mgmt.accounts.regenerate_key(
            self._resource_group,
            self._account_name,
            {"key_name": key_name},
        )
        return keys.key1 if key_name == "key1" else keys.key2

    def store_key(self, value: str, *, slot: str) -> None:
        """新キーを新バージョンとして保存（slot タグを更新）。"""
        self._secrets.set_secret(self._secret_name, value, tags={"slot": slot})

    def disable_local_auth(self) -> None:
        """ハードリミット発動: api-key 認証を即時全停止する（指示書 §5）。

        復旧は手動のみ（docs/runbook-hard-limit.md）。ここに自動復旧は入れない。
        """
        self._mgmt.accounts.begin_update(
            self._resource_group,
            self._account_name,
            {"properties": {"disableLocalAuth": True}},
        ).result()
