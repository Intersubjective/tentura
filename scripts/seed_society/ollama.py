"""Local Ollama chat helper with robust JSON extraction.

Targets the native /api/chat endpoint (non-streaming). Used both as the
"director" (plans the plot) and as the lazy text generator (writes beacon
copy, chat lines, evaluation notes).
"""

from __future__ import annotations

import json
import re

import requests


class Ollama:
    def __init__(self, url: str, model: str):
        self.url = url
        self.model = model
        self._http = requests.Session()

    def chat(
        self,
        system: str,
        user: str,
        *,
        num_predict: int = 600,
        temperature: float = 0.8,
    ) -> str:
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "stream": False,
            "think": False,
            "options": {"num_predict": num_predict, "temperature": temperature},
        }
        r = self._http.post(self.url, json=payload, timeout=300)
        r.raise_for_status()
        data = r.json()
        return (data.get("message") or {}).get("content", "").strip()

    def chat_json(
        self,
        system: str,
        user: str,
        *,
        num_predict: int = 1200,
        retries: int = 1,
    ):
        """Ask for JSON; extract + parse. Retries once with a stricter nudge.

        Returns the parsed object, or None if the model never produced valid JSON.
        """
        sys_json = system + (
            "\n\nReturn ONLY valid JSON. No prose, no markdown fences, no comments."
        )
        prompt = user
        for attempt in range(retries + 1):
            raw = self.chat(sys_json, prompt, num_predict=num_predict, temperature=0.7)
            parsed = _extract_json(raw)
            if parsed is not None:
                return parsed
            prompt = (
                user
                + "\n\nYour previous reply was not valid JSON. Reply with ONLY the "
                "JSON value, starting with { or [."
            )
        return None


def _extract_json(text: str):
    if not text:
        return None
    # Strip ```json fences if present.
    fenced = re.search(r"```(?:json)?\s*(.*?)```", text, re.DOTALL)
    if fenced:
        text = fenced.group(1).strip()
    # Try the whole thing first.
    try:
        return json.loads(text)
    except ValueError:
        pass
    # Fall back to the first balanced { } or [ ] span.
    for opener, closer in (("{", "}"), ("[", "]")):
        start = text.find(opener)
        if start == -1:
            continue
        depth = 0
        for i in range(start, len(text)):
            if text[i] == opener:
                depth += 1
            elif text[i] == closer:
                depth -= 1
                if depth == 0:
                    candidate = text[start : i + 1]
                    try:
                        return json.loads(candidate)
                    except ValueError:
                        break
    return None
