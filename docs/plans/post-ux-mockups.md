# Post — UX and ASCII mockups

**Status:** draft rev 1 (2026-09-30), for discussion with the owner.
**Parent plan:** [`post-and-constellation-composer-plan.md`](post-and-constellation-composer-plan.md).
Copy is Russian (primary locale); final strings go through l10n. Visuals are Material 3 via the
design system (`context.tt`, `TenturaText.*`) — mockups show structure, not pixels.

Decided so far (2026-09-30): no `person_bond` for Posts; webs only on selection, two colours
(*forwarded to* / *inside*), no forward chain; 72h active window + 24h fade; no server cap;
Post → Request keeps members in an intermediate state.

---

## Q1 — where Posts live (product/UX)

**Rev 3 direction (2026-09-30).** Two earlier variants failed:
- rev 1, a «Разговоры» block inside «Для вас» — sits on top of decisions and pushes them down;
- rev 2, Posts only in a separate «Разговоры» tab — a new Post is easy to miss, and a Post that was
  sent to me belongs with everything else sent to me.

**Split by job, reusing the existing attention model:**

| | «Для вас» (stream) | «Разговоры» (tab) |
|---|---|---|
| Job | *something addressed to me personally happened* | *come back to a conversation I'm in* |
| What is there | **one grouped row per Post** — the same grouping the stream already does per Request (`request-attention.md` §8 "group key = the object") | every Post I'm in: «Сейчас» (72h) / «Затихли» |
| What bumps it | only **directed** events: Post sent to me (also a re-send by another person), a reply to my message, an @mention («@вася»); **for the author also first responses** — a person's first message *or* first emoji reaction on my Post (one per person, so bounded by the number of people, not by volume) | any message (unread counter only) |
| Pinned? | **never** — a Post needs no decision, so it is not an «unanswered forward»; it takes its chronological place | — |
| Clears | on open, or × (optional-update clear policy); comes back on the next directed event | never needs clearing |
| Indicator | the normal «Для вас» dot (any dismissible attention) | **none** — per-row counters only |

Why this works:
- **Decisions stay on top.** Unanswered Request forwards remain pinned in «Ждут ответа»; Post rows
  are ordinary chronological optional updates below.
- **No flood.** Ordinary chatter never reaches «Для вас» — only what is addressed *to me*. A busy Post
  is one row at most.
- **Nothing is lost.** Clearing a row (× or «Убрать всё») never leaves the conversation; the Post is
  "recoverable via «Разговоры»" (the contract field every event type must declare).
- **No new machinery.** New event types go through `docs/contracts/updates-event-contract.json`
  (scope: object; class: optional update; group key: the Post; clear: open or ×; ordering: never
  promotes; recoverable via: «Разговоры»).

Other rules:
- Tabs: `TenturaPrimaryTabBar` in the Activity top bar (same component as «Люди»):
  **«Для вас» | «Разговоры»**. Default is always «Для вас»; reselecting the Activity nav item
  returns to it. Deep links open the Post itself.
- «Убрать всё» lives on «Для вас» only.
- Leaving a conversation («Выйти из разговора», inside the Post) ≠ clearing its row (×).
- Wide layout: same two tabs, one list.

---

## M1 — Activity, tab «Для вас»

```
┌────────────────────────────────────────────┐
│ Активность                       ✎  ✓✓  ⋮  │   ✎ «Новый пост», ✓✓ «убрать всё»
│  Для вас•    Разговоры                     │
├────────────────────────────────────────────┤
│ ЖДУТ ОТВЕТА                                │   pinned: unanswered Request forwards only
│ ┌────────────────────────────────────────┐ │
│ │ [карточка запроса — пересылка]         │ │
│ └────────────────────────────────────────┘ │
│                                            │
│ СЕГОДНЯ                                    │   chronological stream
│ ┌────────────────────────────────────────┐ │
│ │ 💬 Анна поделилась постом · от Ильи  ✕ │ │   arrival variant
│ │ Посоветуйте стоматолога в центре       │ │
│ │ Илья: «ты же спрашивал недавно»        │ │   forward note (as for Requests)
│ │                                  3 мин │ │
│ └────────────────────────────────────────┘ │
│ ┌────────────────────────────────────────┐ │
│ │ [запрос: Мария предложила помощь …]  ✕ │ │   existing Request update row
│ └────────────────────────────────────────┘ │
│ ┌────────────────────────────────────────┐ │
│ │ 💬 Пост Олега · вам ответили         ✕ │ │   directed-event variant
│ │ Мария: «в 10, у моста подходит?»       │ │
│ │ и ещё 3 сообщения                12 мин│ │
│ └────────────────────────────────────────┘ │
│ ┌────────────────────────────────────────┐ │
│ │ 💬 На ваш пост откликнулись        ✕   │ │   author: first responses
│ │ ▣ Смотрите, какой кот у нас поселился  │ │
│ │ Мария ❤️ · Катя 😂 · Дима: «это же     │ │   reactions and first messages
│ │ Барсик!»                          1 ч  │ │
│ └────────────────────────────────────────┘ │
│ ВЧЕРА                                      │
│ …                                          │
├────────────────────────────────────────────┤
│  Мои дела   Активность•  Поле  Люди   Я    │
└────────────────────────────────────────────┘
```

Post row (`PostAttentionRow`, a variant of the stream's grouped row, lighter than a Request card):
- line 1: 💬 + headline by the latest directed event — «‹Автор› поделился(ась) постом» (+ «· от
  ‹отправителя›» when sender ≠ author) / «вам ответили» / «вас упомянули» / for the author
  «На ваш пост откликнулись Мария 👍, Дима и ещё 1» · ×;
- line 2: arrival → root message excerpt (▣ thumbnail if it has a photo); reply/mention → the message itself;
- line 3: arrival → the forward note; reply/mention → «и ещё N сообщений» (unread since my last
  visit) · time.
- Tap → the Post, scrolled to the triggering message; the row clears.

## M2 — Activity, tab «Разговоры»

```
┌────────────────────────────────────────────┐
│ Активность                          ✎   ⋮  │   no dismiss-all here
│  Для вас•    Разговоры                     │
├────────────────────────────────────────────┤
│ [Все] [Мои] [Мне]                          │
│                                            │
│ 📌 ◐ Ваш пост · 12 человек  Кто едет на …  │   pinned: always on top, never fades out
│ ─────────────────────────────────────────  │
│ СЕЙЧАС                                     │
│ ┌────────────────────────────────────────┐ │
│ │ ◐ Анна · вам от Ильи          Новый    │ │
│ │ Посоветуйте стоматолога в центре       │ │
│ │                                   3 мин│ │
│ ├────────────────────────────────────────┤ │
│ │ ◐ Олег · вам                       2   │ │
│ │ Кто в субботу на велопрогулку? Круг    │ │
│ │ Мария: я за, во сколько?       12 мин  │ │
│ ├────────────────────────────────────────┤ │
│ │ ◐ Ваш пост · 7 человек                 │ │
│ │ ▣ Смотрите, какой кот у нас поселился  │ │
│ │ Дима: 😂                          1 ч  │ │
│ └────────────────────────────────────────┘ │
│                                            │
│ ЗАТИХЛИ                                    │
│  ◐ Катя · вам  🔕   Кто знает хорошего…    │   dimmed; 🔕 = muted
│  ◐ Ваш пост         Отдам даром шкаф …     │
│  ◐ Павел · вам от Оли  Фото с похода 🏔    │
│  …                                         │
├────────────────────────────────────────────┤
│  Мои дела   Активность   Поле  Люди   Я    │
└────────────────────────────────────────────┘
```

Row anatomy (one `PostConversationRow`):
1. author avatar · addressing — «вам» / «вам от ‹forwarder›» (only when sender ≠ author) /
   «Ваш пост · N человек» · trailing: «Новый» or the unread counter;
2. root message excerpt, 1 line (▣ = thumbnail if it has a photo);
3. last message «Имя: текст» · relative time (empty for a new Post).

«Сейчас» is ordered by last activity — it is my own conversation list (every row was addressed
to me or written by me), not a feed. A «Затихли» Post is fully functional: writing in it moves it
back to «Сейчас» for everyone in it.

Empty «Разговоры»: one line + action — «Здесь будут разговоры, которые вы начали или в которые
вас позвали» · [Новый пост].

---

## M3 — creating a Post = writing the first message

A Post has no form. Creating one looks like an empty chat: the same composer as in any room,
plus «Кому».

```
┌────────────────────────────────────────────┐
│ ✕  Новый пост                              │
│ Кому: Мария, Олег  ✎            [●   ] ↗   │   ↗● = «Можно пересылать» (on by default)
├────────────────────────────────────────────┤
│                                            │
│                                            │
│          Напишите, с чего начать           │   empty-room hint
│          разговор. Это и будет пост.       │
│                                            │
│                                            │
├────────────────────────────────────────────┤
│ ▣ ▣                                        │   attachments (same as chat)
│ [+]  Кто в субботу на велопрогулку?…   [➤] │   ➤ = publish + send
└────────────────────────────────────────────┘
```

- «Кому» opens the existing recipient picker (Post profile: no capability band, no reason chips,
  no lineage). The count and names are always visible in the row; ➤ is disabled without
  recipients.
- ➤ publishes: the typed message becomes the root message, then the Post is sent. The screen
  turns into the live room in place (no navigation jump).
- «Нужна помощь? Создать запрос ›» is a link in the ✕-row overflow, not a banner.
- Entry points: ✎ in the Activity top bar, the My Work «+» menu (Пост / Запрос), the map composer.
- If sending breaks midway, the author sees the Post in «Разговоры» as «Не отправлено ·
  Дописать / Удалить».

---

## M4 — Post screen = the room

```
┌────────────────────────────────────────────┐
│ ←  Олег: Кто в субботу на велопр…  🔕   ⋮  │   title = author + root excerpt
├────────────────────────────────────────────┤
│ 📌 Кто в субботу на велопрогулку? Круг по… │   pinned strip → tap scrolls to the root
│    Вам переслала Мария: «ты же хотел»      │   only for a forwarded recipient
├────────────────────────────────────────────┤
│ ─────────────── вчера ───────────────      │
│ ◐ Олег                                     │   ← the root message = the Post
│   Кто в субботу на велопрогулку? Круг по   │
│   набережной, ~30 км, темп спокойный.      │
│   ┌────────────┐                           │
│   │   фото     │                           │
│   └────────────┘                           │
│   ❤️ 4  🚲 2                               │   ordinary reactions
│ ─────────────── сегодня ─────────────      │
│ ◐ Мария  ↩ Олег                            │
│   я за! во сколько старт?          👍 2    │
│                     в 10, у моста  ◐ ✓✓   │
│ ◐ Дима                                     │
│   могу взять запасную камеру               │
├────────────────────────────────────────────┤
│ [+]  Сообщение…                        [➤] │
└────────────────────────────────────────────┘
```

Nothing else is on screen. Everything to manage the Post is in ⋮:

```
│  📌 Закрепить в разговорах                 │
│  🔕 Заглушить                            › │
│  👥 Участники                              │
│  ⑂  Граф пересылок                         │   every member; existing screen
│  ◎  Показать на поле                       │
│  ↗  Переслать                              │   if allowed
│  🔓 Разрешить пересылку                    │   author, while off (one-way)
│  ◎  Превратить в запрос                    │   author
│  ⎋  Выйти из разговора                     │   recipient
│  🗑  Удалить пост                           │   author
```

- The root is an ordinary message: react, reply, edit (author) the usual way. Deleting the root
  means deleting the Post (confirmation).
- No system rows for forwards or joins (decided 2026-10-01): the chat holds only messages. Who
  is in the Post and who brought them is visible only in «Участники» (M5).
- Wide layout: the room fills the detail area; «Участники» opens as a side sheet. No extra pane.

---

## M5 — participants and "add to contacts"

```
┌────────────────────────────────────────────┐
│ Участники · 7                              │
│ Можно пересылать              [↗ Позвать]  │
├────────────────────────────────────────────┤
│ В РАЗГОВОРЕ · 5                            │
│  ◐ Олег        автор                       │
│  ◐ Мария       в контактах                 │
│  ◐ Дима        [+ В контакты]              │
│  ◐ Света       позвала Мария               │
│  ◐ Вы                                      │
│ ЕЩЁ НЕ ОТКРЫЛИ · 2                         │
│  ◐ Катя                                    │
│  ◐ Павел                                   │
├────────────────────────────────────────────┤
│ Как пост дошёл до людей ›                  │   → «Граф пересылок»
└────────────────────────────────────────────┘
```

Tapping a person (here or a message avatar) opens the existing profile sheet, with one
context line:

```
┌────────────────────────────────────────────┐
│ ◐  Дима Кузнецов                           │
│    Вы вместе в посте «Кто в субботу…»      │
│                                            │
│ [ + Добавить в контакты ]    Профиль ›     │
└────────────────────────────────────────────┘
          ↓ after tap
│ ✓ Дима в ваших контактах. Он увидит это    │
│   и сможет добавить вас в ответ.           │
```

Adding is quiet: the other side gets no notification (plan Q18). To ask for an add-back, write
to them in the chat (an @mention notifies). When both have added each other, both get the
existing `mutualConnectionFormed` event.

«Граф пересылок» is the existing forward-graph screen (the same one Requests have), opened
for the Post. It shows who forwarded to whom, starting from the author. This is the only place the
forward chain appears: the map shows only webs (M9), and the chat has no forward rows.

«ЕЩЁ НЕ ОТКРЫЛИ» lists the names and is visible to every member (decided 2026-10-01). It
discloses the same kind of read state as the room's read ticks.

---

## M6 — forwarding off (author's opt-out), recipient's side

```
│ ←  Пост Олега                👥 4       ⋮  │   no ↗
…
│ Участники · 4                              │
│ Пересылать может только Олег               │
```

---

## M7 — converting to a Request (author)

```
┌────────────────────────────────────────────┐
│ Превратить пост в запрос?                  │
│                                            │
│ • Разговор и 6 участников останутся.       │
│   Каждый сможет предложить помощь          │
│   или выйти.                               │
│ • Запрос можно будет пересылать дальше —   │   only if the Post was closed
│   на этом держится запрос.                 │
│ • Обратно в пост превратить нельзя.        │
│                                            │
│ [✓] Люди в моём поле могут найти запрос    │
│                                            │
│           Отмена    [ Далее: детали → ]    │
└────────────────────────────────────────────┘
```

«Далее» → the existing Request edit form on the same object, **prefilled from the root message**
(first line → title, the rest → description, a photo → cover suggestion). In chat:
`─── Олег превратил пост в запрос ───`; the root message stays the first message, and the pinned
strip becomes the Request's normal NOW / pinned-facts area.

---

## M8 — the intermediate state after conversion (Q3)

A former Post member on the Request screen. The YOU row of the Request header carries the state
and its two exits:

```
┌────────────────────────────────────────────┐
│ ←  Велопрогулка в субботу            ↗  ⋮  │
├────────────────────────────────────────────┤
│ СТАТУС  Ищем людей                         │
│ ВЫ      Участник из поста                  │
│         Вы в чате. Чтобы участвовать в     │
│         деле — предложите помощь.          │
│   [ Предложить помощь ]   Выйти из чата    │
├────────────────────────────────────────────┤
│  Инфо   Чат•   Люди                        │
│ …                                          │
```

- «Предложить помощь» → the normal offer sheet → the author acknowledges → helper with stake
  (already admitted, nothing changes in the chat). A declined offer leaves the person in this
  same intermediate state.
- «Выйти из чата» → `room_access = left`; the person remains a forward recipient (an ordinary
  observer of the Request) and it moves out of their conversations.
- The state has no timer.

Author's «Люди» tab gets one extra section:

```
│ ИЗ ПОСТА · 4                               │
│  ◐ Мария     в чате, помощь не предлагала ⋮│   ⋮ → «Убрать из чата»
│  ◐ Дима      в чате, помощь не предлагал  ⋮│
```

---

## M9 — Posts on «Моё поле»

A Post node is a rounded speech-bubble glyph (a Request is a circle with a status marker). It sits
at the barycentre of its members on your map (or where you, the author, put it). **No edges
until selected.**

Unselected:

```
         ◐Маша
                      ◐Олег
     ◐Дима     ▢💬
                   ◐Вы
          ◐Катя
```

Selected — webs to members **placed on my map**, two colours; the rest is «+N»:

```
         ◐Маша
            ╲
     ◐Дима ──▣💬────── ◐Олег
               ┆ ╲
               ┆  ◐Вы
          ◐Катя          ⊕ +3
   ─── внутри    ┄┄┄ переслали, ещё не открыл(а)
```

Preview sheet (tap):

```
┌────────────────────────────────────────────┐
│ 💬 Пост Олега                     2 новых  │
│ Кто в субботу на велопрогулку? Круг…       │
│ 5 в разговоре · 2 ещё не открыли           │
│ ещё 3 — вне вашего поля                    │
│ [ Открыть разговор ]        ↗ Переслать    │
└────────────────────────────────────────────┘
```

Requests behave the same on selection: `───` = in the chat (admitted helpers), `┄┄┄` = forwarded
to. Someone who only discovered the Request (no involvement read) sees `───` only.

Fading: over the last 24h of the 72h window the node's opacity drops; after that it leaves the
field (pinned: stays as a dormant anchor, like pinned closed Requests).

---

## M10 — mute, pin, leave

### Mute («Заглушить»)

```
│ ⋮                                          │
│  📌 Закрепить в разговорах                 │
│  🔕 Заглушить                            › │ ──┐
│  👥 Участники                              │   │  ┌──────────────────────┐
│  ◎ Показать на поле                        │   └─▶│ На 1 час             │
│  ⎋ Выйти из разговора                      │      │ На 3 часа            │
                                                    │ На день              │
                                                    │ На 3 дня             │
                                                    │ Навсегда             │
                                                    └──────────────────────┘
```

Muted state:
- app bar of the Post: `🔕` next to the title; the menu item becomes «Включить звук · заглушено до
  18:40» (or «· навсегда»);
- «Разговоры» row: `🔕` after the addressing, unread counter in a neutral (not accent) colour;
- expiry is silent — at `muted_until` the Post simply starts notifying again.

What mute silences (one rule, same for every duration):

| Event | Not muted | Muted |
|---|---|---|
| ordinary message | counter only | counter only (neutral) |
| first responses to my Post — message or reaction (author) | «Для вас» row + push | nothing (counter only) |
| reply to my message | «Для вас» row + push | nothing (counter only) |
| **@mention of me** | «Для вас» row + push | **«Для вас» row, no push/email** |
| Post re-sent to me by someone else | row + push | nothing |

An @mention stays visible in-app because someone called me by name; everything else is silent.

### Pin in conversations («Закрепить в разговорах»)

- A pinned Post sits above «Сейчас» in «Разговоры», ordered by pin time, and **does not fade out**
  of the list (on the map it fades as usual — conversation pin ≠ map pin).
- Swipe/right-click on a «Разговоры» row → «Закрепить» / «Открепить» (plus the Post ⋮ menu).
- A pin is private and says nothing to other members.

### Leave («Выйти из разговора»)

```
┌────────────────────────────────────────────┐
│ Выйти из разговора?                        │
│ Сообщения перестанут приходить, пост       │
│ исчезнет из разговоров. Вернуться можно    │
│ из «Не интересно».                         │
│                      Отмена   [ Выйти ]    │
└────────────────────────────────────────────┘
      ↓
  ✓ Вы вышли из разговора            [Вернуть]
```

- Leaving is quiet: no system row in the chat, the person just disappears from «Участники».
- The Post goes to the existing «Не интересно» archive (Activity ⋮), with «Вернуть».
- If someone sends me the same Post again after I left, I get the normal arrival row in «Для вас»
  with «Вернуться в разговор» — I am **not** re-added automatically.
- The author cannot leave their own Post (mute or delete instead).

---

## M11 — «Можно пересылать» (Posts only)

A Post-only control; Requests keep today's rules. **On by default** (decided 2026-10-01): anyone
who can read the Post may forward it to anyone mutually visible to them, and those people may take
part and/or forward further. Off (author's choice before sending): only the people the author
invited take part (the author can always invite more). After publish it is **one-way**: off → on
only.

While creating (draft), it is a plain switch the author can toggle freely. It starts on:

```
│ Можно пересылать                   [●   ]  │   default
│ Любой участник сможет переслать дальше.    │
│ После отправки выключить будет нельзя.     │
```
```
│ Можно пересылать                   [   ○]  │   author switched it off
│ Участвуют только те, кого вы позвали.      │
│ Разрешить пересылку можно будет позже.     │
```

After publishing, a closed Post (the author switched it off) shows an action. An open Post shows a locked fact:

```
│ Пересылать может только автор              │
│ [ Разрешить пересылку ]                    │   author only
```
```
┌────────────────────────────────────────────┐
│ Разрешить пересылку?                       │
│ Любой участник сможет переслать пост       │
│ людям из своего круга, и они смогут        │
│ участвовать. Выключить это будет нельзя.   │
│                   Отмена   [ Разрешить ]   │
└────────────────────────────────────────────┘
```
```
│ 🔓 Пересылка разрешена                     │   no toggle any more
```

- Recipients of a closed object see no «Переслать» button; the author always does.
- The share link / QR (invite) follows the same rule: author-only while closed.

---

## K — creating a Post / Request on «Моё поле» (composer)

Principles:
- **It is the same creation as the list flow**, shown on the map: same draft, same recipient
  selection (`ForwardCubit`), same eligibility, same Send. The map only draws the selection and
  edits it. «Списком» at any moment opens the list picker on the *same* selection and back.
- **Nothing is sent without Send**, and before Send the exact list of people is always visible.
- The radius *proposes*; the person *decides*: manual additions survive shrinking the radius,
  manual removals survive growing it.

### K1 — entry

```
┌────────────────────────────────────────────┐
│ Моё поле                        ⟳   ⊞   ⋮  │
│ [фильтры …]                                │
├────────────────────────────────────────────┤
│            ◐Маша                           │
│                        ◐Олег               │
│     ◐Дима        ◉Вы                       │
│                             ◐Катя          │
│          ◐Света                            │
│                                            │
│                                  ╭───────╮ │
│                                  │ ✎  Создать │   extended FAB-style button
│                                  ╰───────╯ │
└────────────────────────────────────────────┘
          tap «Создать»            desktop: right-click on empty space
                ↓                  touch: long-press on empty space (secondary path)
        ┌──────────────────┐
        │ 💬 Пост          │
        │ ◎  Запрос        │
        └──────────────────┘
```

The draft appears at the viewport centre (button) or at the pointer (right-click / long-press).

### K2 — draft placed, starting radius

Entering the composer, the map **also shows everyone you can send to** (not only people with
Requests) — they fade in on their rings; a one-line hint says so once. The starting radius is just
wide enough to cover the **3 nearest people you can send to** (decided 2026-10-01).

```
┌────────────────────────────────────────────┐
│ ✕  Новый пост на поле                Далее │   ✕ = cancel composer
│ Показаны все, кому можно отправить         │   one-time hint
├────────────────────────────────────────────┤
│            ◐Маша                           │
│        ·  ·  ·  ·  ·        ◐Олег          │
│     ·                 ·                    │
│   ·   ◐Дима━━━┓        ·    ◐Катя          │
│   ·           ▢💬━━━◐Света ·               │
│    ·        ┏━┛  ◉Вы     ·     ○Павел      │   ○ = can't send (dimmed)
│      ·   ◐Ира         ·◆                   │   ◆ = radius handle
│         ·  ·  ·  ·  ·                      │
│                                            │
├────────────────────────────────────────────┤
│ ▔▔▔▔                                       │   bottom sheet, collapsed
│ 3 получателя: Дима, Света, Ира             │
│ [+]  Напишите первое сообщение…        [➤] │   the room composer (M3)
└────────────────────────────────────────────┘
   ━━ web to a selected person      · · radius
```

- Drag ▢💬 — the draft moves with its circle; who is inside is recomputed **on drop**
  (no flicker while dragging).
- Drag ◆ — the circle grows/shrinks; webs appear/disappear live; the count in the sheet updates.
- Pan/zoom the map as usual; the radius lives in map space, so zooming does not change who is inside.
- Ego («Вы») is never a recipient and is ignored by the radius.

### K3 — manual edits

```
│            ◐Маша                           │
│        ·  ·  ·  ·  ·        ◐Олег━━━━━━┓   │   tapped outside → added (✚ marker)
│     ·                 ·            ✚   ┃   │
│   ·   ◐Дима━━━┓        ·    ◐Катя      ┃   │
│   ·           ▢💬━━━━━━━━━━━━━━━━━━━━━━┛   │
│    ·        ┏━┛  ◉Вы     ·                 │
│      ·   ◐Ира         ·◆   ◐Света ⊖        │   tapped inside → excluded (⊖, no web)
│         ·  ·  ·  ·  ·                      │
├────────────────────────────────────────────┤
│ 3 получателя: Дима, Ира, Олег              │
```

- Tap a person: toggles. Inside the circle → «не отправлять» (⊖, stays excluded even if the
  circle grows); outside → «добавлено вручную» (✚, stays even if the circle shrinks).
- Tap a dimmed ○ person: a snackbar with the reason (reusing the forward screen copy):
  «Павел на паузе до пятницы», «Уже в разговоре», «Не может получать от вас».
- Undo: tap again. A long list of edits is visible in the sheet (K4) where each chip has ×.

### K4 — sheet expanded (Post)

The sheet is the same «empty room» as M3: the room composer plus «Кому» — the map is the «Кому».

```
├────────────────────────────────────────────┤
│ ▔▔▔▔                                       │
│ Получат · 3                      Списком › │   «Списком» = the list picker, same selection
│ (Дима ×) (Ира ×) (Олег ✚ ×)                │
│ Можно пересылать                   [●   ]  │
│ ─────────────────────────────────────────  │
│ ▣                                          │   attachments
│ [+]  Кто в субботу на велопрогулку? Круг   │   the room composer
│      по набережной, ~30 км           [➤]   │   ➤ = publish + send
└────────────────────────────────────────────┘
```

While the sheet is expanded the map stays visible above it (half-height), so the webs can be
checked while typing. ➤ is disabled with no recipients or an empty message. After ➤ the sheet
closes and the Post is on the map (K6); «Открыть разговор» is offered in the snackbar.

### K5 — Request variant

Same map part. The sheet asks only for what a Request cannot live without; everything else is
one tap away in the full form (same draft, same recipients). Request rules are unchanged — no
forwarding switch; discoverability as today.

```
├────────────────────────────────────────────┤
│ ┌────────────────────────────────────────┐ │
│ │ Что нужно?  (название)                 │ │
│ └────────────────────────────────────────┘ │
│ ┌────────────────────────────────────────┐ │
│ │ Подробнее (необязательно)              │ │
│ └────────────────────────────────────────┘ │
│ Получат · 5                      Списком › │
│ (Дима ×) (Ира ×) (Олег ×) (Катя ×) +1      │
│ [✓] Люди в моём поле могут найти запрос    │
│                                            │
│ Все детали ›          [ Отправить · 5 ]    │   «Все детали» = full create form
└────────────────────────────────────────────┘
```

### K6 — sending and after

```
     ✓ Отправлено 3 людям                        existing send confirmation (snackbar form)

│            ◐Маша                           │
│                             ◐Олег          │
│   ◐Дима┄┄┄┐                   ┆            │
│            ▣💬┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┘            │   the Post stays exactly where it was put
│          ┌┄┘    ◉Вы                        │   (saved as your pin), selected for a moment:
│      ◐Ира           ◐Света                 │   ┄┄ = sent, not opened yet
```

- The draft node becomes the real Post at the same spot (stored as the author's pin), the circle
  and the widened set of people disappear, and the Post is shown selected for a few seconds
  with ┄┄ «переслан, ещё не открыл» webs, then settles to the unselected look (no webs).
- Tapping it later works like M9.

### K7 — cancelling

- ✕ with an empty draft: exits silently.
- ✕ with text/photo: «Удалить черновик?» [Удалить] [Продолжить]. Post drafts are not kept
  (a Post is a moment); Request drafts follow today's rule and stay in «Мои дела» → drafts.
- Esc on desktop = ✕.

### K8 — wide layout (desktop / tablet)

```
┌────────────────────────────────────────────┬─────────────────────────┐
│ Моё поле                          ⟳  ⊞  ⋮  │ ✕ Новый пост            │
├────────────────────────────────────────────┤                         │
│            ◐Маша                           │ Получат · 3   Списком › │
│        ·  ·  ·  ·  ·        ◐Олег          │ (Дима ×)(Света ×)(Ира ×)│
│     ·                 ·                    │ Можно пересылать  [●  ] │
│   ·   ◐Дима━━━┓        ·    ◐Катя          │ ─────────────────────── │
│   ·           ▢💬━━━◐Света ·               │                         │
│    ·        ┏━┛  ◉Вы     ·     ○Павел      │   Напишите первое       │
│      ·   ◐Ира         ·◆                   │   сообщение — это и     │
│         ·  ·  ·  ·  ·                      │   будет пост.           │
│                                            │                         │
│                                            │ ▣                       │
│                                            │ [+] Сообщение…      [➤] │
└────────────────────────────────────────────┴─────────────────────────┘
```

The sheet becomes a side panel; hovering a chip highlights that person's web on the map, and
hovering a person on the map highlights their chip. Right-click on a person = toggle.

### K9 — accessibility

The Text view of «Моё поле» and screen readers get the same composer through «Списком» (the list
picker is the canonical accessible path). The radius control has a slider equivalent in the
sheet («Радиус: ближайшие 3 → 12 человек») for keyboard users.

---

## Open UX questions

None. All questions decided as of 2026-10-01.
