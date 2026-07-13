"""キーローテーションの中核ロジック（指示書 §3）。

Azure SDK / HTTP に依存しない純粋ロジックとして分離し、azure_ops / teams を
インターフェースとして受け取る。pytest はこのモジュールを直接検証する。
"""

from dataclasses import dataclass

# 新キー本文を Teams に含める（週次自動ローテーションのため秘匿性は低いと判断。
# Azure にアクセスできない利用者にも配布できるようにするための方針）。
# {key} に新しい api-key が差し込まれる。
ROTATION_MESSAGE_TEMPLATE = (
    "エディタ用 OpenAI API キーをローテーションしました。\n"
    "新しいキー:\n{key}\n"
    "エディタのキー設定をこの値に貼り替えてください。"
    "旧キーは次回ローテーション（1週間後）で失効します。"
)


def rotation_message(new_key: str) -> str:
    """ローテ完了通知の本文（新キーを含む）。"""
    return ROTATION_MESSAGE_TEMPLATE.format(key=new_key)


@dataclass
class RotationResult:
    previous_slot: str | None
    new_slot: str


def next_slot(active: str | None) -> str:
    """現用スロットの反対側を返す（key1/key2 交互の無停止ローテーション）。

    slot タグが欠落・不正な場合は「key1 が配布中」とみなして key2 を返す。
    現用側を regenerate して即時失効させる事故を避けるための安全側の倒し方。
    """
    return "key1" if active == "key2" else "key2"


def rotate(ops, notifier) -> RotationResult:
    """ローテーション本体。

    1. Key Vault の slot タグから現用スロットを読む
    2. 反対側のキーを regenerate（旧キーは次回ローテまで有効）
    3. 新キーを Key Vault へ新バージョンとして保存（slot タグ更新）
    4. Teams へ完了通知

    通知失敗時は例外を送出して関数実行を失敗させる。
    「regenerate 成功 + 通知失敗」は利用者が旧キー失効に気づけない最悪パターンの
    ため、握りつぶさず必ずアラート（App Insights 失敗検知）に乗せる。
    """
    active = ops.get_active_slot()
    new = next_slot(active)
    new_key = ops.regenerate_key(new)
    ops.store_key(new_key, slot=new)
    notifier.post(rotation_message(new_key))
    return RotationResult(previous_slot=active, new_slot=new)
