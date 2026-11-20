"""Content checks for the published budding documentation."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MATRIX = ROOT / "docs/beacon-visibility-matrix.md"
ADR = ROOT / "docs/adr/0008-beacon-visibility-and-invite-sharing.md"
PLANS = ROOT / "docs/plans"
OBSERVER_TABLE = "beacon_bud_observer"

LEGACY_TERMS = r"\bbeacon_bud_observer\b|\bbud observers?\b"
RETIRED = (
    r"\b(?:superseded|removed|retired|dropped|obsolete|no longer applies|"
    r"no longer (?:exists|used)|historical only|"
    r"no (?:bud |membership |observer )snapshot)\b|"
    r"устарел\w*|отмен[её]н\w*|замен[её]н\w*|удал[её]н\w*"
)
RULE_REFERENCE = (
    r"\bm0320\b|\bADR\s*0*8\b|\bvisibility matrix\b|"
    r"beacon-visibility-matrix\.md|0008-beacon-visibility-and-invite-sharing\.md|"
    r"\]\(#[^)]+\)|\b(?:new|current) (?:access|audience|visibility) rule\b"
)
POST_MEMBERSHIP = (
    r"\bpost(?:'s)? (?:membership|members?|participants?)\b|"
    r"\b(?:membership|members?|participants?|admission) (?:of|in|to) "
    r"(?:the |a |its |parent )*post\b"
)
NO_POST_ACCESS = (
    r"\b(?:no (?:additional |extra )?(?:access|audience|rights|visibility|grant\w*|"
    r"content)|cannot (?:see|read|access|open)|(?:does|do) not "
    r"(?:confer|grant|give|add|extend|inherit|provide|include)|"
    r"grants? (?:nothing|none)|confers? (?:nothing|none)|"
    r"(?:excluded|insufficient|irrelevant|independent))\b|❌"
)
NO_POST_AUDIENCE = (
    r"\b(?:no|without|excludes?) (?:any )?(?:extra |additional )?"
    r"Post[- ]derived (?:audience|access|grants?)\b|"
    r"\b(?:no|without) (?:extra |additional )?(?:audience|access|grants?)"
    r".{0,45}\b(?:from|via|through) (?:the |its )?(?:parent )?Post\b"
)
NORMAL_AUDIENCE = (
    r"\b(?:normal|ordinary|standard|regular|usual|same|regularly)\b.{0,100}"
    r"\b(?:audience|access rules|visibility rules)\b|"
    r"\b(?:audience|access rules|visibility rules)\b.{0,100}"
    r"\b(?:normal|ordinary|standard|regular|usual|same)\b"
)
PARENT_REQUEST = (
    r"\b(?:request[-– ]parent|parent request)\b|"
    r"\bparent\s*\(?\s*(?:(?:is|must be) (?:itself )?(?:a |the )?|"
    r"of (?:kind|type) )?request\b"
)
IMMEDIATE_REQUEST_PARENT = (
    rf"\b(?:immediate|direct)[- ](?:{PARENT_REQUEST})|"
    r"\b(?:immediate|direct)[- ]parent,? (?:only )?(?:if|when|provided) "
    r"(?:it|that parent) is (?:a |the )?request\b|"
    r"\brequest\b (?:as |is )?(?:the |its |a )?(?:immediate|direct)[- ]parent\b|"
    r"\bparent\b \((?:immediate|direct),? (?:a )?request\)|"
    r"\bparent request\b \((?:immediate|direct)\)"
)
PARENT_MEMBER = (
    r"\b(?:effective (?:admitted )?members? (?:of |in )?|"
    r"admitted members? (?:of |in )?|effectively admitted (?:to|in) )"
    r"(?:the |a |an )?(?:(?:immediate|direct) )?"
    rf"(?:{PARENT_REQUEST})|"
    r"\bmembers? \((?:access )?level (?:≤\s*1|<=\s*1|0 or 1)\) "
    r"(?:of|in) (?:the |a |an )?(?:(?:immediate|direct) )?"
    rf"(?:{PARENT_REQUEST})|"
    r"\b(?:(?:immediate|direct) )?(?:parent request|request[- ]parent)"
    r"(?:'s)? (?:effective|admitted) members?\b"
)
CHILD_MEMBER = (
    r"\bchild(?: request)?(?:'s)? (?:effective |admitted )?members?\b|"
    r"\b(?:effective |admitted )?members? (?:of|in) (?:a |the )?child(?: request)?\b"
)
READ_GRANT = (
    r"\b(?:read(?:s|ing)?|view(?:s|ing)?|see(?:s)?|"
    r"access(?:es)?|is an observer of|are observers of)\b"
)
READ_DENIAL = (
    r"\b(?:cannot|can.t|does not|do not|never|may not|must not) "
    r"(?:be (?:read|seen|viewed)|read|see|view|access|grant|give)\b|"
    r"\b(?:no (?:read )?access|no longer)\b"
)

COMMON_OLD_CLAIMS = (
    r"\bsnapshot (?:of (?:the )?|for (?:the )?)?(?:effective )?"
    r"(?:post members|observers?|contextChild)\b|"
    r"\bobservers?(?:\s*=| are|s)? (?:a |the )?snapshot\b|"
    r"\b(?:Post[- ]derived|Post[- ]parent) observers?\b|"
    r"\bPost(?:'s)?\b.{0,55}\b(?:members?|membership|participants?)\b.{0,65}"
    r"\b(?:are observers?|(?:can|may|still) (?:read|see|view|observe)|"
    r"have (?:read )?access|automatically (?:see|read|observe))\b.{0,65}"
    r"\b(?:bud\w*|child|new request|content)\b|"
    r"\b(?:members?|participants?)\b.{0,40}\b(?:of|in) (?:a |the )?post\b.{0,65}"
    r"\b(?:read|see|view|observe)\b.{0,45}\b(?:bud\w*|child|new request)\b"
)

ARCHITECTURE_CLAIMS = {
    "summary rule 3": (
        r"^3\.(?= .*\b(?:observer|snapshot|Post membership))",
        r"\b(?:snapshot|observer)\w*\b",
    ),
    "§2.1 observer storage": (
        r"^### 2\.1\b",
        r"\bobservers?\b|\bsnapshot\b|\bE\(post\)|"
        r"\bLeaving the Post later does not remove\b|beacon_bud_observer",
    ),
    "Post-parent child reads": (
        r"^### 3\.2\b",
        r"\bcontextChild\b.{0,90}\b(?:kind\s*=\s*1|Post parent)\b|"
        r"\bobserver level = today.s contextChild\b",
    ),
    "hierarchy hints": (
        r"^### 3\.4\b",
        r"\bsnapshot\b.{0,40}\b(?:recipients|observers|direct audience)\b|"
        r"\b(?:recipients|membership|outside the)\b.{0,180}\bsnapshot\b|"
        r"\bpost members\b.{0,55}\b(?:receive|get)\b",
    ),
    "publication snapshot": (
        r"^## 4\. ",
        r"\b(?:writes|stores|creates|inserts)\b.{0,70}\b(?:snapshot|observers?)\b|"
        r"\b(?:observer|membership|audience) snapshot\b|"
        r"\btitle snapshot: non-observers\b|beacon_bud_observer",
    ),
    "invariant I4": (r"^- \*\*I4\b", r"\b(?:snapshot|observers?)\b"),
}

IMPLEMENTATION_CLAIMS = (
    r"schema: observers|\bisBudObserver\b|\bobservers snapshot\b|"
    r"realtime snapshot|child parent; observers|\bblocked observer\b.{0,40}\b(?:cannot|gets)\b"
)
DESIGN_CLAIMS = (
    r"наблюдатели дочернего Запроса|наблюдатели:\s*содержание да|снимок участников поста|"
    r"участник\w* (?:этого )?поста.{0,95}(?:вид(?:ят|ит)|чита(?:ют|ет)|"
    r"наблюдател\w*|доступ\w*).{0,65}(?:запрос\w*|содержани\w*)"
)


def read(path):
    return path.read_text(encoding="utf-8")


def visible(markdown):
    return re.sub(r"\s+", " ", re.sub(r"[*`]", "", markdown)).strip()


def mentions(pattern, value):
    return re.search(pattern, visible(value), flags=re.IGNORECASE) is not None


def denies_post_access(value):
    return mentions(NO_POST_AUDIENCE, value) or (
        mentions(POST_MEMBERSHIP, value) and mentions(NO_POST_ACCESS, value)
    )


def current_bud_audience(value):
    return mentions(r"\b(?:bud\w*|child requests?)\b", value) and mentions(
        NORMAL_AUDIENCE, value
    )


def context_rows(document, code, cells):
    for line in document.splitlines():
        if line.lstrip().startswith("|"):
            row = [visible(cell) for cell in line.strip().strip("|").split("|")]
            if len(row) == cells and any(code in cell for cell in row):
                yield row


def adr_grants_context(amendments, reason, member, target):
    other_reason = "contextAncestor" if reason == "contextChild" else "contextChild"
    for amendment in amendments:
        for _, text, _ in passages(amendment):
            clauses = re.split(
                r";|(?<=[.!?])\s+|,\s+(?:and|while|whereas)\s+",
                visible(text),
            )
            for clause in clauses:
                if (
                    not mentions(rf"\b{reason}\b", clause)
                    or mentions(rf"\b{other_reason}\b", clause)
                    or mentions(READ_DENIAL, clause)
                ):
                    continue
                # Check who reads what in the clause naming the reason. Allow
                # either "members read the child" or "the child is readable by members".
                active = rf"(?:{member}).*?{READ_GRANT}.*?(?:{target})"
                passive = (
                    rf"(?:{target}).*?\b(?:readable|read|visible|viewed|seen|"
                    rf"accessible) (?:by|to) (?:the )?(?:{member})"
                )
                if mentions(active, clause) or mentions(passive, clause):
                    return True
    return False


def passages(document):
    """Yield Markdown reader units with their ancestor headings and line number."""
    headings = []
    lines = []
    start = 1
    fence = None

    for number, line in enumerate(document.splitlines(), 1):
        stripped = line.strip()
        marker = re.match(r"`{3,}|~{3,}", stripped)
        heading = re.match(r"^(#{1,6})\s+", line) if not fence else None
        table_row = stripped.startswith("|") and not fence
        new_item = re.match(r"(?:[-+*]|[0-9]+\.|[a-z]\.)\s", stripped)

        if lines and not fence and (not stripped or heading or table_row or new_item):
            yield start, "\n".join(lines), tuple(text for _, text in headings)
            lines = []
        if heading:
            depth = len(heading[1])
            headings = [(level, text) for level, text in headings if level < depth]
            headings.append((depth, line))
            yield number, line, tuple(text for _, text in headings)
        elif table_row:
            yield number, line, tuple(text for _, text in headings)
        elif stripped or fence:
            if not lines:
                start = number
            lines.append(line)
            if marker:
                if fence is None:
                    fence = marker[0][0]
                elif marker[0][0] == fence:
                    fence = None

    if lines:
        yield start, "\n".join(lines), tuple(text for _, text in headings)


def retired_in(passage, headings):
    return any(mentions(RETIRED, text) for text in (passage, *headings))


def obsolete_claims(path, pattern):
    for line, passage, headings in passages(read(path)):
        if mentions(pattern, passage) and not retired_in(passage, headings):
            yield f"{path.name}:{line}: {visible(passage)}"


def documents_replacement_rule(document):
    for _, text, _ in passages(document):
        if current_bud_audience(text) and denies_post_access(text):
            return True
        if mentions(
            r"\bобыч\w* (?:аудитори\w*|правил\w* доступ\w*).{0,30}запрос\w*", text
        ) and mentions(r"участи\w* в посте|участни\w* поста|членство в посте", text):
            if mentions(r"\bне (?:да[её]т|открывает|предоставляет)|\bбез доступа\b", text):
                return True
        if mentions(RULE_REFERENCE, text) and (
            mentions(r"\b(?:post membership|post[- ]parent|observer\w*|audience)\b", text)
            or mentions(r"аудитори\w*|наблюдател\w*|участни\w* поста", text)
        ) and (retired_in(text, ()) or denies_post_access(text)):
            return True
    return False


class PostBudVisibilityTest(unittest.TestCase):
    def test_matrix_grants_context_through_request_parents_only(self):
        document = read(MATRIX)
        problems = []
        row_types = {
            "content-read row": [
                row for row in context_rows(document, "contextChild", 2)
                if mentions(r"\b(?:read|view|content)\w*\b", row[0]) and "✅" in row[1]
            ],
            "reason 6 / 64": [
                row for row in context_rows(document, "contextChild", 3)
                if row[:2] == ["6", "64"]
            ],
            "unadmitted child role row": [
                row for row in context_rows(document, "contextChild", 6)
                if "✅" in row[4]
            ],
        }
        for label, rows in row_types.items():
            if not rows or not all(
                mentions(IMMEDIATE_REQUEST_PARENT, " ".join(row)) for row in rows
            ):
                problems.append(f"{label} must grant contextChild via the immediate Request parent.")
        if not any(
            mentions(r"\b(?:child|descendant)\b", row[0])
            and mentions(r"\bparent\b", row[0])
            and mentions(r"\bancestors?\b", row[0])
            and "✅" in row[1]
            for row in context_rows(document, "contextAncestor", 2)
        ):
            problems.append("Keep parent and ancestor reads for child members.")
        self.assertFalse(problems, "\n".join(problems))

    def test_matrix_gives_buds_the_normal_request_audience(self):
        document = read(MATRIX)
        units = [passage for _, passage, _ in passages(document)]
        problems = list(obsolete_claims(MATRIX, rf"{LEGACY_TERMS}|{COMMON_OLD_CLAIMS}"))
        if OBSERVER_TABLE in document:
            problems.append(f"Omit the retired {OBSERVER_TABLE} table.")
        if not any(
            len(cells := line.strip().strip("|").split("|")) == 2
            and mentions(POST_MEMBERSHIP, cells[0])
            and mentions(r"\b(?:bud\w*|child request)\b", cells[0])
            and mentions(
                r"\b(?:alone|only|otherwise uninvolved|no (?:other |independent )?"
                r"(?:access|involvement)|(?:not|neither) (?:invited|ticked))\b",
                cells[0],
            )
            and "❌" in cells[1]
            for line in document.splitlines() if line.lstrip().startswith("|")
        ):
            problems.append("Show ❌ when a Post member has no other access to the bud.")
        audience_roles = (
            r"\bauthors?\b", r"\b(?:invit\w*|tick\w*)\b",
            r"\bforward\w*\b", r"\badmit\w*\b", r"\b(?:help\w*|offer\w*)\b",
        )
        # Allow the audience rule to wrap across adjacent paragraphs or list items.
        rules = [" ".join(units[index:index + 7]) for index in range(len(units))]
        if not any(
            current_bud_audience(rule)
            and all(mentions(role, rule) for role in audience_roles)
            and any(
                denies_post_access(sentence)
                and (
                    mentions(NO_POST_AUDIENCE, sentence)
                    or mentions(r"\b(?:audience|membership|post[- ]derived|grant\w*|"
                                r"confer\w*|alone|access path)\b", sentence)
                )
                for sentence in re.split(r"(?<=[.!?])\s+", visible(rule))
            )
            for rule in rules
        ):
            problems.append(
                "State the normal Request audience with its usual roles and expressly "
                "exclude Post membership as a source of audience access."
            )
        self.assertFalse(problems, "\n".join(problems))

    def test_adr_retires_post_parent_context_and_keeps_request_context(self):
        document = read(ADR)
        amendments = re.split(r"(?m)^## (?=Amendment\b)", document)[2:]
        problems = []
        if not any(
            denies_post_access(amendment)
            and mentions(r"\bcontextChild\b", amendment)
            and any(
                mentions(r"\bcontextChild\b", text)
                and mentions(r"\bpost\b", text) and mentions(RETIRED, text)
                for _, text, _ in passages(amendment)
            )
            and any(
                mentions(r"\bm0320\b", text)
                and mentions(r"\bbeacon_bud_observer\b", text)
                and mentions(RETIRED, text)
                for _, text, _ in passages(amendment)
            )
            for amendment in amendments
        ):
            problems.append(
                "In Amendment B or a later amendment, retire Post-parent contextChild, "
                "deny Post-derived access and name the beacon_bud_observer table dropped in m0320."
            )
        if not adr_grants_context(
            amendments, "contextChild", PARENT_MEMBER, r"\bchild(?: request)?\b"
        ):
            problems.append(
                "Bind contextChild to effective parent Request members reading child content."
            )
        if not adr_grants_context(
            amendments,
            "contextAncestor",
            CHILD_MEMBER,
            r"\bparent\b.*?\bancestors?\b|\bancestors?\b.*?\bparent\b",
        ):
            problems.append(
                "Bind contextAncestor to child Request members reading the parent and other ancestors."
            )
        problems.extend(obsolete_claims(ADR, LEGACY_TERMS))
        self.assertFalse(problems, "\n".join(problems))

    def test_architecture_replaces_the_post_observer_rule(self):
        path = PLANS / "post-request-budding-architecture.md"
        document = read(path)
        problems = list(obsolete_claims(
            path, rf"{LEGACY_TERMS}|{COMMON_OLD_CLAIMS}|snapshot\s*\+\s*direct audience",
        ))
        if not current_bud_audience(document) or not denies_post_access(document):
            problems.append("Explain the normal Request audience and deny Post-derived access.")
        for line, text, headings in passages(document):
            for label, (location, claim) in ARCHITECTURE_CLAIMS.items():
                if not any(re.search(location, part, re.IGNORECASE) for part in (text, *headings)):
                    continue
                if not mentions(claim, text):
                    continue
                if label == "Post-parent child reads" and not mentions(
                    LEGACY_TERMS, text
                ) and (
                    mentions(PARENT_REQUEST, text)
                    or mentions(r"\b(?:disable\w*|never|does not apply|no contextChild)\b", text)
                ):
                    continue
                if current_bud_audience(text) and denies_post_access(text) and not mentions(
                    LEGACY_TERMS, text
                ):
                    continue
                if not retired_in(text, headings) or not any(
                    mentions(RULE_REFERENCE, part) or current_bud_audience(part)
                    for part in (text, *headings)
                ):
                    problems.append(
                        f"{path.name}:{line}: {label} still describes the observer snapshot. "
                        "Rewrite it or mark it superseded and identify the current rule."
                    )
        self.assertFalse(problems, "\n".join(problems))

    def test_implementation_plan_marks_observer_access_as_historical(self):
        path = PLANS / "post-request-budding-implementation-plan.md"
        problems = list(obsolete_claims(
            path, rf"{LEGACY_TERMS}|{COMMON_OLD_CLAIMS}|{IMPLEMENTATION_CLAIMS}",
        ))
        if not documents_replacement_rule(read(path)):
            problems.append("State the replacement audience rule or direct readers to it.")
        self.assertFalse(problems, "\n".join(problems))

    def test_design_marks_observer_access_as_historical(self):
        path = PLANS / "post-request-budding-design.md"
        problems = list(obsolete_claims(
            path, rf"{LEGACY_TERMS}|{COMMON_OLD_CLAIMS}|{DESIGN_CLAIMS}",
        ))
        if not documents_replacement_rule(read(path)):
            problems.append("State the replacement audience rule or direct readers to it.")
        self.assertFalse(problems, "\n".join(problems))


if __name__ == "__main__":
    unittest.main()
