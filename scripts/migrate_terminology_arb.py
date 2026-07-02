#!/usr/bin/env python3
"""One-shot ARB value migration: beacon→request, room→chat (values only)."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

EN_OVERRIDES: dict[str, str] = {
    "introPage2Title": "Post a request, friends pass it on",
    "introPage2Text": (
        "Describe what you need — that's a request. Friends forward it to "
        "someone who can help, and you coordinate in the request's chat until "
        "it's done."
    ),
    "introPage3Text": (
        "You joined by a personal invite, like everyone else — the friend who "
        "invited you is already in your network. Add people you trust, and "
        "post a request when you need a hand."
    ),
}

RU_OVERRIDES: dict[str, str] = {
    "introPage2Title": "Опубликуйте запрос — друзья передадут его дальше",
    "introPage2Text": (
        "Опишите, что вам нужно, — это запрос. Друзья перешлют его тому, "
        "кто может помочь, а вы договоритесь обо всём в чате запроса."
    ),
    "introPage3Text": (
        "Вы пришли по личному приглашению, как и все остальные: пригласивший "
        "вас друг уже в вашей сети. Добавляйте людей, которым доверяете, "
        "и публикуйте запрос, когда нужна помощь."
    ),
}


def migrate_en(text: str) -> str:
    if not isinstance(text, str):
        return text
    t = text
    t = re.sub(r"beacon's room", "request's chat", t, flags=re.I)
    t = re.sub(r"beacon rooms", "request chats", t, flags=re.I)
    t = re.sub(r"beacon room", "request chat", t, flags=re.I)
    t = re.sub(r"\bBeacons\b", "Requests", t)
    t = re.sub(r"\bbeacons\b", "requests", t)
    t = re.sub(r"\bBeacon's\b", "Request's", t)
    t = re.sub(r"\bbeacon's\b", "request's", t)
    t = re.sub(r"\bBeacon\b", "Request", t)
    t = re.sub(r"\bbeacon\b", "request", t)
    # Workspace room → chat (after beacon compounds)
    t = re.sub(r"\bRoom\b", "Chat", t)
    t = re.sub(r"\broom\b", "chat", t)
    return t


RU_REPLACEMENTS: list[tuple[str, str]] = [
    ("маяков", "запросов"),
    ("маяками", "запросами"),
    ("маякам", "запросам"),
    ("маяках", "запросах"),
    ("маяки", "запросы"),
    ("маяком", "запросом"),
    ("маяке", "запросе"),
    ("маяку", "запросу"),
    ("маяка", "запроса"),
    ("Маяки", "Запросы"),
    ("Маяк", "Запрос"),
    ("маяк", "запрос"),
    ("комнатах", "чатах"),
    ("комнатам", "чатам"),
    ("комнатами", "чатами"),
    ("комнатой", "чатом"),
    ("комнате", "чате"),
    ("комнату", "чат"),
    ("комнаты", "чаты"),
    ("комната", "чат"),
    ("Комната", "Чат"),
    ("комнат", "чатов"),
]


def migrate_ru(text: str) -> str:
    if not isinstance(text, str):
        return text
    t = text
    for old, new in RU_REPLACEMENTS:
        t = t.replace(old, new)
    return t


def migrate_arb(path: Path, lang: str) -> int:
    data = json.loads(path.read_text(encoding="utf-8"))
    overrides = EN_OVERRIDES if lang == "en" else RU_OVERRIDES
    migrate = migrate_en if lang == "en" else migrate_ru
    changed = 0
    for key, value in list(data.items()):
        if key.startswith("@"):
            continue
        if not isinstance(value, str):
            continue
        if key in overrides:
            new = overrides[key]
        else:
            new = migrate(value)
        if new != value:
            data[key] = new
            changed += 1
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return changed


def main() -> int:
    en = ROOT / "packages/client/l10n/app_en.arb"
    ru = ROOT / "packages/client/l10n/app_ru.arb"
    ce = migrate_arb(en, "en")
    cr = migrate_arb(ru, "ru")
    print(f"migrated {en.name}: {ce} keys, {ru.name}: {cr} keys")
    return 0


if __name__ == "__main__":
    sys.exit(main())
