# Commitment truth rework — план реализации

**Статус:** план к исполнению (не начат).
**Дата:** 2026-08-05, ревизия 3 (два раунда adversarial review — см. §15).
**Аналитическая часть:** см. §1 (обоснование) — решения владельца продукта уже внесены и **не подлежат пересмотру исполнителем**.
**Исполнитель:** агент-разработчик. Читать целиком до начала работы; выполнять фазы строго по порядку.
**Связанные тикеты:** [#108](https://github.com/Intersubjective/tentura/issues/108) — закрывается фазой **P9** (§11).

---

## 0. Правила исполнения (обязательно прочитать первым)

### 0.1 Что нельзя делать

- **Нельзя** менять порядок значений в существующих `enum`, которые сериализуются по `index`
  (`HelpOfferCoordinationExceptionCode`, `EvaluationExceptionCode` в
  `packages/server/lib/domain/exception_codes.dart` — их `codeNumber = codeSpace + index`).
  Новые значения **только в конец списка**.
- **Нельзя** менять смысл существующих числовых значений в БД
  (`beacon.status`, `beacon_help_offer.status`, `beacon_help_offer_coordination.response_type`,
  `beacon_help_offer_admission_event.action`, `beacon_evaluation_participant.role` 0/1/2).
- **Нельзя** редактировать сгенерированные файлы: `*.g.dart`, `*.freezed.dart`, `*.gr.dart`,
  `*.config.dart`, `packages/client/lib/ui/l10n/**`, `**/_g/**`. Только запуск codegen.
- **Нельзя** удалять существующие миграции или править уже написанные `m0001…m0138`.
  Любая правка схемы — **новая** миграция.
- **Нельзя** вводить домен-сущность/таблицу/маршрут с именем `Request` (терминологический инвариант,
  см. `AGENTS.md`). Внутреннее имя остаётся `beacon`; пользовательское — Request/Chat через l10n.
- **Нельзя** писать сырые визуальные константы в клиентском UI (`Color`, `TextStyle(...)`,
  `EdgeInsets.all(8)` и т. п.) — только токены (`context.tt`) и `TenturaText.*`.
- **Нельзя** расширять объём: всё, чего нет в этом плане, не делается. Если по ходу обнаружится
  необходимое изменение вне плана — записать в §14 «Открытые вопросы» и продолжить.
- **Нельзя** строить UX на кодах ошибок сервера: клиент их **не разбирает**
  (`grep -rn "evaluationCode\|coordinationCode" packages/client/lib` → пусто). Новые коды
  (`commitmentAlreadyAcknowledged`, `commitmentNotAcknowledged`,
  `admissionRequiresAcknowledgement`) нужны для корректности сервера, логов и тестов.
  Пользовательские объяснения строятся **до** вызова — на предвычисленных флагах
  (`canCancel`, `canDelete`, `stakeState`, `canCloseNow`); ошибка сервера показывается
  как generic-сообщение с возможностью повтора.

### 0.2 Обязательные процедуры

- После изменения Drift-таблиц / Injectable / Freezed на сервере:
  `cd packages/server && dart run build_runner build -d`
- После изменения `.graphql`, Freezed, Injectable на клиенте:
  `cd packages/client && dart run build_runner build -d`
- После изменения `packages/client/l10n/*.arb`:
  `cd packages/client && flutter gen-l10n` (до `build_runner`).
- Новая V2-операция клиента **обязана** быть добавлена в `_tenturaDirectOperationNames`
  в `packages/client/lib/data/service/remote_api_client/build_client.dart`.
- Клиентская копия схемы `packages/client/lib/data/gql/schema.graphql` поддерживается **вручную**:
  любое новое поле/мутация V2 добавляется туда текстом, иначе ferry-codegen не увидит поле.
- Изменение колонок таблиц, читаемых через Hasura, требует правки
  `hasura/metadata.json` (списки `columns` в `select_permissions`) и повторного применения:
  `./scripts/hasura_apply_metadata.sh`.

### 0.3 Verify после каждой фазы

```bash
cd packages/tentura_lints && dart test
cd packages/server && dart test                       # см. §11.2 про -x pg
./scripts/check-custom-lints.sh packages/server
./scripts/check-custom-lints.sh packages/client
cd packages/client && flutter test
bash scripts/check-user-facing-terminology.sh
```

Базлайн кастом-линтов: клиент **112**, сервер 0 (`scripts/custom-lint-baseline.txt` — сверяться
с файлом, а не с этим планом). **Увеличивать базлайн запрещено**; если новый UI-код добавляет диагностики — исправлять код, а не базлайн.

### 0.4 Журнал

Вести `docs/plans/commitment-truth-rework-journal.md`: по одной секции на фазу —
что сделано, какие файлы, какие тесты, что не сошлось. Обновлять **после каждой фазы**, до коммита.

### 0.5 Коммиты

Один коммит на фазу, формат: `feat(commitment): P<N> — <краткое описание>` (или `fix`/`docs`/`chore`).
Ветку создать до первого коммита: `feat/commitment-truth-rework`.

---

## 1. Зачем это делается (контекст, не подлежит пересмотру)

Сейчас одна мутабельная строка `beacon_help_offer_coordination` (PK `offer_beacon_id, offer_user_id`)
одновременно кодирует три независимые вещи:

| Ось | Что означает | Какое свойство нужно |
|-----|--------------|----------------------|
| **A. Доступ** | пускать ли человека в Chat (`beacon_participant.room_access`) | обратимая |
| **B. Текущий stake** | кто сейчас в работе | обратимая |
| **C. Историческая правда** | «автор признал вклад этого человека» | **append-only, не стирается** |

Так как строка `upsert`-ится и `delete`-ится, ось C выводится из оси B и стирается вместе с ней.
Подтверждённые в коде последствия (все — дефекты, а не задумка):

1. `HelpOfferCase.withdraw` (`packages/server/lib/domain/use_case/help_offer_case.dart:238`)
   вызывает `deleteForCommit` → строка исчезает → человек пропадает из состава ревью, а автору
   снова открываются Cancel и Delete.
2. `BeaconCase.deleteById` (`packages/server/lib/domain/use_case/beacon_case.dart:871`) проверяет
   `everHadAcknowledgedCommitter` по **текущим** строкам, то есть «когда-либо» фактически равно
   «сейчас». Это прямо противоречит `CONTEXT.md` §«Deleted».
3. `CoordinationCase.setCoordinationResponse` разрешает автору понизить `useful` → `notSuitable`
   в любой момент, пока запрос в open-family → автор сам стирает собственное признание и получает
   Cancel/Delete.
4. `UserBlockCase._withdrawOffersByOfferer`
   (`packages/server/lib/domain/use_case/user_block_case.dart:162`) вызывает `deleteForCommit`
   **в обе стороны** → блокировка работает ластиком истории.
5. `CoordinationCase.removeFromRoom` снимает только доступ и не трогает stake: человек выгнан
   из чата, но остаётся committer'ом (блокирует Cancel, остаётся обязательным ревьюером).
6. `CoordinationCase.declineHelpOffer` запрещён только пока участник `admitted`; после
   `removeFromRoom` он снова доступен → связка remove → decline полностью стирает committer'а.
7. Состав ревью снапшотится в `EvaluationCase.beaconClose` по **активным** офферам ∩ acknowledged
   (`evaluation_participant_graph_builder.dart:45`) → «кто дожил до Close», а не «кто участвовал».
8. `allowsBeaconWithdraw = status.allowsCoordination = isOpenFamily || reviewOpen`
   (`lib/domain/entity/beacon_status.dart:41`) → withdraw разрешён во время Wrapping up, но
   participant-строки уже созданы: ушедший блокирует `closeNow`, при этом его inbox-строка
   тумбстонится. До Close withdraw стирает всё, после Close — не стирает ничего.
9. `EvaluationCase.reopenFromReview` сбрасывает scaffolding и переводит submitted-ревью в drafts;
   повторный Close пересобирает состав по текущим активным офферам. Комбинация (3)+(6)+(9) даёт
   автору легальный маршрут полного стирания отзывов.
10. `_derivePublic` в `packages/server/lib/domain/coordination/derive_beacon_display_status.dart`
    при статусе `enoughHelp` возвращает `suggestedAction: offerHelp` — STATUS говорит «помощи
    достаточно», ACT говорит «предложи помощь».
11. `MyWorkCardViewModel.authorResponseType` **не рендерится на карточке My Work**
    (`grep authorResponseType packages/client/lib/features/my_work/ui/` пусто), хотя само поле
    используется в `packages/client/lib/ui/widget/beacon_hud_metadata_composer.dart:83`
    (`viewerOfferAuthorResponse`) — удалять его нельзя. Мёртвые здесь именно
    `MyWorkStatusLineData.slot1ResponseType` / `slot1CoordinationStatus` и l10n-ключ
    `myWorkStatusHelpOfferWithResponse`.
12. `HelpOfferCase._autoAdmitIfTrusted` при офферe от прямого адресата автора сам пишет
    `responseType = useful` и пускает в комнату — признание вклада без осознанного акта автора.

### 1.1 Принятые продуктовые решения (развилки закрыты)

| # | Решение |
|---|---------|
| D1 | Модель Accept/Decline остаётся; доку приводим к ней (автор принимает/отклоняет **предложение**, не человека). |
| D2 | «Enough help»: **вариант A+B** — для невовлечённого зрителя primary-действие становится **Forward**, а предложить помощь можно как **backup-оффер** (вторичное действие, отдельный тип оффера). |
| D3 | Отсутствие ответа автора — не проблема прав, а проблема видимости: показываем состояние ответа на карточке My Work. |
| D4 | **Auto-admit удаляется** полностью. |
| D5 | Remove from chat — **вариант O2**: remove трогает **только доступ**; UI обязан явно писать «участие сохранено» и предлагать **отдельное** второе действие «Завершить участие» (новая мутация). |
| D6 | Append-only журнал участия; права выводятся из фактов; факты не стираются никем (ни хелпером, ни автором, ни блокировкой). |
| D7 | Withdraw = выход с записью. Грейс-период 24 ч после признания — тихий выход без следа committer'а. |
| D8 | Review window открывается, если committer был **когда-либо**, а не «есть сейчас». |
| D9 | Reopen из Wrapping up — не более 1 раза на запрос. |
| D10 | Withdraw во время Wrapping up запрещён (участие уже завершено закрытием; пропустить отзыв можно через skip). |
| D11 | Гейт Delete — **только** «когда-либо было признание». Отдельного гейта «была работа в комнате» **нет**: вместо него вводится инвариант «в комнату пускают только вместе с признанием» (§2.4). |
| D12 | Клиент получает состояние участия из **проекции** `beacon_help_offer.stake_state`, а не выводит его из `response_type` (§2.5). |
| D13 | «Завершить участие» **обратимо авторским Accept**: `setCoordinationResponse(useful)` / `acceptHelpOffer` по тому же активному офферу снова даёт current stake. Новый оффер от хелпера не требуется. Оба события остаются в журнале; `everAcknowledged` и так уже true. |

---

## 2. Целевая модель (после всех фаз)

### 2.1 Новый источник правды

Таблица `public.beacon_commitment_event` — append-only, одна строка на факт.

Виды событий (`kind`, smallint):

| kind | Имя (Dart `CommitmentEventKind`) | Кто пишет | Смысл |
|------|----------------------------------|-----------|-------|
| 0 | `offered` | хелпер | подал предложение помощи |
| 1 | `acknowledged` | автор | ответ `useful` или `needCoordination` (в т. ч. через Accept) |
| 2 | `acknowledgementSoftened` | автор (**legacy/бэкфилл**) | автор поставил не-признающий ответ **после** признания (историю не стирает). После P3.9 такой ответ запрещён, поэтому для новых данных вид почти недостижим; остаётся ради исторических строк и как «предохранитель». UI для него нужен, серверные пути записи — только те, что перечислены в P2.2 |
| 3 | `withdrawnByHelper` | хелпер | withdraw |
| 4 | `releasedByAuthor` | автор | «Завершить участие» (новая мутация `releaseCommitment`) |
| 5 | `removedFromChat` | автор | отозван доступ в комнату (**stake не трогает**) |
| 6 | `readmittedToChat` | автор | доступ возвращён |
| 7 | `blockedCleanup` | система | блокировка одной из сторон |
| 8 | `unansweredAtClose` | система | на момент Close оффер был активен и без ответа автора |

### 2.2 Производные предикаты (чистые функции)

Вход — список событий одного `(beacon_id, user_id)`, отсортированный по `seq ASC`.

```
everAcknowledged(events, grace):
  для каждого i, где events[i].kind == acknowledged:
    n := i + 1                              // СЛЕДУЮЩЕЕ событие, без пропусков
    если n < len(events)
       И events[n].kind == withdrawnByHelper
       И events[n].createdAt - events[i].createdAt <= grace:
        продолжаем              // тихий выход в грейс — это признание не засчитывается
    иначе:
        вернуть true
  вернуть false
```

> Грейс закрывается **любым** промежуточным событием, а не только временем. Цепочка
> `acknowledged → acknowledgementSoftened → withdrawnByHelper (через 1 ч)` даёт
> `everAcknowledged == true`: между признанием и выходом что-то происходило, значит выход
> уже не «тихий». Это закрывает обходной путь «автор снял признание → хелпер тут же вышел →
> следов нет».

```
currentStakeState(events):
  state := none
  для e в events по возрастанию seq:
    offered                  -> state := offered
    acknowledged             -> state := acknowledged
    acknowledgementSoftened  -> state := softened
    withdrawnByHelper        -> state := exited
    releasedByAuthor         -> state := released
    blockedCleanup           -> state := exited
    removedFromChat          -> без изменений      (D5: доступ ≠ участие)
    readmittedToChat         -> без изменений
    unansweredAtClose        -> без изменений
  вернуть state

hasCurrentStake(events, hasActiveOfferRow) :=
  currentStakeState(events) == acknowledged && hasActiveOfferRow
```

Агрегаты по запросу:

- `beaconEverHadCommitter(beaconId)` = существует не-автор с `everAcknowledged == true`.
- `beaconCurrentCommitterIds(beaconId)` = множество не-авторов с `hasCurrentStake == true`.

Константа грейса: `kCommitmentGracePeriod = Duration(hours: 24)`.

### 2.3 Целевая матрица правил

| Действие | Было | Стало |
|----------|------|-------|
| **Cancel** | запрещён, если есть активный оффер с acknowledged | запрещён, если `beaconEverHadCommitter == true` |
| **Delete** (опубликованный) | запрещён, если сейчас есть coordination-строка с ack | запрещён, если `beaconEverHadCommitter == true` |
| **Допуск в комнату** (`inviteToRoom`) | разрешён с любым `responseType` | разрешён только вместе с признающим ответом (§2.4) |
| **Close: нужен ли review window** | `activeCommitterCount >= 1` | `beaconEverHadCommitter == true` |
| **Состав ревью** | активные офферы ∩ ack | все `everAcknowledged` (роль `committer`, если есть current stake, иначе `formerCommitter`) + автор + форвардеры на путях к ним |
| **Блокирующие `Close now`** | author + committer | author + committer (роль 1). `formerCommitter` (роль 3) **не блокирует** |
| **Понижение ответа автором** | разрешено всегда | запрещено, если `everAcknowledged`; вместо этого `releaseCommitment` |
| **`declineHelpOffer`** | запрещён только при `admitted` | запрещён, если `everAcknowledged` |
| **`removeFromRoom`** | снимает доступ, stake остаётся (неявно) | снимает доступ, stake остаётся (**явно**, с копирайтом и вторым действием) |
| **Withdraw** | удаляет coordination-строку | пишет событие; coordination-строка **не удаляется** |
| **Withdraw при `reviewOpen`** | разрешён | запрещён (`beaconWithdrawForbidden`) |
| **Блокировка** | удаляет coordination-строку | пишет `blockedCleanup`; строка остаётся |
| **Reopen** | без лимита | не более `kMaxReviewReopens = 1` |
| **ACT при `enoughHelp` (public tier)** | `offerHelp` | `forward` (backup-оффер — вторичное действие) |

### 2.4 Инвариант допуска: «в комнате — значит признан» (вместо гейта «материальная работа»)

Ранняя редакция плана вводила отдельный гейт Delete по «материальной работе в комнате»
(сообщения / опубликованные items от не-автора). **Решение владельца: такого гейта не будет
(D11).** Причина: не-автор физически не может работать в комнате без допуска
(`BeaconRoomCase` пускает только автора, стюарда и `roomAccess == admitted`), а допуск обязан
означать признание. Поэтому дыра закрывается не новым гейтом, а инвариантом на входе:

> **Инвариант A:** `roomAccess == admitted` для не-автора и не-стюарда ⇒ у пары есть событие
> `acknowledged` ⇒ `everAcknowledged == true` ⇒ Delete закрыт.

Что для этого делается (реализуется в P3.10):

1. `CoordinationCase.setCoordinationResponse` с `inviteToRoom == true` разрешён **только** при
   `responseType ∈ {useful(0), needCoordination(3)}`; иначе — ошибка
   `admissionRequiresAcknowledgement` (новый код в конце enum).
2. Auto-admit (единственный путь допуска без явного ответа автора) удаляется в P5.
3. `acceptHelpOffer` уже пишет `useful` + допуск атомарно — трогать не нужно.

**Исключение (осознанное, не чинится в этом плане):** стюарды (`beacon_steward`) имеют доступ
в комнату без help-оффера и без признания. Стюард — не committer, его сообщения не создают stake
и **не** блокируют Delete. Если это когда-нибудь окажется проблемой — отдельный тикет; в §14
исполнителю ничего писать не нужно.

### 2.5 Проекция состояния участия для клиента (D12)

Источник истины — события. Но клиент читает `beacon_help_offer` (Hasura, My Work) и
`helpOffersWithCoordination` (V2, People tab), где `response_type` **остаётся** `useful` даже
после выхода/снятия участия. Чтобы UI не врал, вводится **денормализованная проекция**:

`beacon_help_offer.stake_state smallint NOT NULL DEFAULT 0` со значениями, зеркальными
`CommitmentStakeState`:

| Значение | Смысл |
|----------|-------|
| 0 | `none` — событий нет |
| 1 | `offered` — предложил, ответа нет |
| 2 | `acknowledged` — признан, участие активно |
| 3 | `softened` — автор поставил не-признающий ответ после признания |
| 4 | `exited` — вышел сам (withdraw) или блокировка |
| 5 | `released` — автор завершил участие |

Правила:
- проекция **пересчитывается из событий** и переписывается при каждой записи события
  (единственная точка — `CommitmentRepository.record`, см. P1.4);
- проекция **никогда** не является входом для гейтов и предикатов — только для отображения;
- расхождение проекции с событиями считается багом проекции, а не истории.

---

## 3. Фаза P1 — фундамент данных

**Цель:** появилась таблица событий, новые колонки, бэкфилл истории. Поведение продукта не меняется.

### P1.1 Миграция `m0139`

Создать `packages/server/lib/data/database/migration/m0139.dart` по образцу `m0113.dart`
(та же структура: `part of '_migrations.dart';`, `final m0139 = Migration('0139', [ ... ]);`).

Операторы, ровно в этом порядке:

1. Создание таблицы:

```sql
CREATE TABLE public.beacon_commitment_event (
  id text PRIMARY KEY,
  seq bigserial NOT NULL,
  beacon_id text NOT NULL,
  user_id text NOT NULL,
  actor_user_id text NOT NULL REFERENCES public."user"(id),
  kind smallint NOT NULL,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT beacon_commitment_event_offer_fk
    FOREIGN KEY (beacon_id, user_id)
    REFERENCES public.beacon_help_offer (beacon_id, user_id)
    ON DELETE CASCADE,
  CONSTRAINT beacon_commitment_event_kind_check
    CHECK (kind BETWEEN 0 AND 8),
  CONSTRAINT beacon_commitment_event_reason_check
    CHECK (reason IS NULL OR length(trim(reason)) BETWEEN 1 AND 500)
);
```

2. `COMMENT ON TABLE public.beacon_commitment_event IS 'Append-only participation facts for a help
   offer. kind: 0=offered,1=acknowledged,2=acknowledgement_softened,3=withdrawn_by_helper,
   4=released_by_author,5=removed_from_chat,6=readmitted_to_chat,7=blocked_cleanup,
   8=unanswered_at_close. Rows are never updated or deleted.';`
3. `CREATE UNIQUE INDEX beacon_commitment_event_pair_idx ON public.beacon_commitment_event
   (beacon_id, user_id, seq DESC);`
4. `CREATE INDEX beacon_commitment_event_beacon_idx ON public.beacon_commitment_event (beacon_id);`
5. `ALTER TABLE public.beacon_help_offer ADD COLUMN offer_kind smallint NOT NULL DEFAULT 0;`
6. `ALTER TABLE public.beacon_help_offer ADD CONSTRAINT beacon_help_offer_offer_kind_check
   CHECK (offer_kind IN (0, 1));`
7. `COMMENT ON COLUMN public.beacon_help_offer.offer_kind IS '0=normal, 1=backup (offered while the
   request already signalled enough help)';`
7a. `ALTER TABLE public.beacon_help_offer ADD COLUMN stake_state smallint NOT NULL DEFAULT 0;`
7b. `ALTER TABLE public.beacon_help_offer ADD CONSTRAINT beacon_help_offer_stake_state_check
    CHECK (stake_state BETWEEN 0 AND 5);`
7c. `COMMENT ON COLUMN public.beacon_help_offer.stake_state IS 'Display-only projection of
    beacon_commitment_event: 0=none,1=offered,2=acknowledged,3=softened,4=exited,5=released.
    Never an input for gates (see docs/plans/commitment-truth-rework-plan.md §2.5).';`
8. `ALTER TABLE public.beacon ADD COLUMN review_reopen_count smallint NOT NULL DEFAULT 0;`
8a. **Бэкфилл `offered`** — выполняется **первым из бэкфиллов** (до шагов 9–11), чтобы `seq`
   у `offered` был меньше, чем у признаний и выходов, то есть порядок событий совпадал
   с естественным:

```sql
INSERT INTO public.beacon_commitment_event (id, beacon_id, user_id, actor_user_id, kind, reason, created_at)
SELECT
  'CE' || replace(gen_random_uuid()::text, '-', ''),
  ho.beacon_id, ho.user_id, ho.user_id, 0, NULL, ho.created_at
FROM public.beacon_help_offer ho;
```

9. **Бэкфилл `acknowledged`** — из текущих coordination-строк:

```sql
INSERT INTO public.beacon_commitment_event (id, beacon_id, user_id, actor_user_id, kind, reason, created_at)
SELECT
  'CE' || replace(gen_random_uuid()::text, '-', ''),
  c.offer_beacon_id,
  c.offer_user_id,
  c.author_user_id,
  1,
  NULL,
  c.created_at
FROM public.beacon_help_offer_coordination c
JOIN public.beacon_help_offer ho
  ON ho.beacon_id = c.offer_beacon_id AND ho.user_id = c.offer_user_id
WHERE c.response_type IN (0, 3);
```

10. **Бэкфилл `acknowledged` из admission-лога** (случаи, где coordination-строка была удалена
    withdraw'ом или блокировкой, но факт accept/auto_admit сохранился):

```sql
INSERT INTO public.beacon_commitment_event (id, beacon_id, user_id, actor_user_id, kind, reason, created_at)
SELECT
  'CE' || replace(gen_random_uuid()::text, '-', ''),
  a.beacon_id,
  a.offer_user_id,
  a.actor_user_id,
  1,
  NULL,
  a.created_at
FROM public.beacon_help_offer_admission_event a
WHERE a.action IN (0, 1)
  AND NOT EXISTS (
    SELECT 1 FROM public.beacon_commitment_event e
    WHERE e.beacon_id = a.beacon_id AND e.user_id = a.offer_user_id AND e.kind = 1
  );
```

11. **Бэкфилл `withdrawnByHelper`** — для уже withdrawn-офферов, чтобы `currentStakeState` был
    корректен (created_at берём из `updated_at` оффера — точнее данных нет):

```sql
INSERT INTO public.beacon_commitment_event (id, beacon_id, user_id, actor_user_id, kind, reason, created_at)
SELECT
  'CE' || replace(gen_random_uuid()::text, '-', ''),
  ho.beacon_id,
  ho.user_id,
  ho.user_id,
  3,
  ho.withdraw_reason,
  ho.updated_at
FROM public.beacon_help_offer ho
WHERE ho.status = 1;
```

11a. **Бэкфилл проекции** `stake_state` (выполняется последним, после шагов 8a–11):

```sql
UPDATE public.beacon_help_offer ho
SET stake_state = CASE
  WHEN ho.status = 1 THEN 4                                  -- withdrawn → exited
  WHEN EXISTS (SELECT 1 FROM public.beacon_commitment_event e
               WHERE e.beacon_id = ho.beacon_id AND e.user_id = ho.user_id AND e.kind = 1)
       AND COALESCE((SELECT c.response_type FROM public.beacon_help_offer_coordination c
                     WHERE c.offer_beacon_id = ho.beacon_id AND c.offer_user_id = ho.user_id), -1)
           IN (0, 3) THEN 2                                  -- acknowledged
  WHEN EXISTS (SELECT 1 FROM public.beacon_commitment_event e
               WHERE e.beacon_id = ho.beacon_id AND e.user_id = ho.user_id AND e.kind = 1)
       THEN 3                                                -- ack был, ответ понижен → softened
  ELSE 1                                                     -- offered
END;
```

> **Важно про грейс при бэкфилле.** У исторических строк `acknowledged.created_at` берётся из
> `coordination.created_at`, а `withdrawn.created_at` — из `help_offer.updated_at`. Если разница
> ≤ 24 ч **и** между ними нет других событий, исторический человек будет считаться «тихо
> вышедшим». Это принимается как допустимая неточность; дополнительных корректировок **не делать**.

> **Продуктовая заметка (шаг 10, `action IN (0, 1)`).** `0 = auto_admit`, `1 = accept`. Значит
> исторические авто-допуски (механика, удаляемая в P5) становятся **вечными** committer'ами:
> у их запросов навсегда закрыты Cancel и Delete, а сами люди попадут в состав ревью. Это
> **осознанное** решение по D6/D8: авто-допуск давал реальный доступ к работе, и стирать этот
> факт задним числом нельзя. Не «чинить», не исключать из бэкфилла.

12. Регистрация: добавить `m0139,` в конец списка в
    `packages/server/lib/data/database/migration/_migrations.dart`.

13. Hasura: в `hasura/metadata.json` для таблицы `beacon_help_offer` добавить в
    `select_permissions.columns` два имени — `"offer_kind"` и `"stake_state"` — и применить
    `./scripts/hasura_apply_metadata.sh`. (Раньше это стояло в P6.8; перенесено сюда, потому что
    от `stake_state` зависит P7, а от `offer_kind` — P3.5.)

### P1.2 Drift-таблица

Создать `packages/server/lib/data/database/table/beacon_commitment_events.dart` по образцу
`beacon_help_offer_admission_events.dart`:

```dart
class BeaconCommitmentEvents extends Table {
  late final id = text()();
  late final seq = int64().customConstraint('UNIQUE NOT NULL')();
  late final beaconId = text()();
  @ReferenceName('commitmentUser')
  late final userId = text().references(Users, #id)();
  @ReferenceName('commitmentActorUser')
  late final actorUserId = text().references(Users, #id)();
  /// 0=offered … 8=unanswered_at_close (см. docs/plans/commitment-truth-rework-plan.md §2.1)
  late final kind = integer()();
  late final reason = text().nullable()();
  late final createdAt = customType(PgTypes.timestampWithTimezone)
      .clientDefault(() => PgDateTime(DateTime.timestamp()))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {beaconId, userId, seq},
  ];

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'beacon_commitment_event';
}
```

В `packages/server/lib/data/database/table/beacon_help_offers.dart` добавить:

```dart
  /// 0=normal, 1=backup (см. план §2.1).
  late final Column<int> offerKind = integer().withDefault(const Constant(0))();

  /// Display-only projection of commitment events (см. план §2.5).
  late final Column<int> stakeState = integer().withDefault(const Constant(0))();
```

Там же — `HelpOfferEntity` (`packages/server/lib/domain/entity/help_offer_entity.dart`):
добавить поля `int offerKind` (default 0) и `int stakeState` (default 0), заполнять их
в `HelpOfferRepository._toEntity`. **Оба поля вводятся уже в P1**, потому что от `offerKind`
зависит P3.5, а от `stakeState` — P4 и P7.

В `packages/server/lib/data/database/table/beacons.dart` добавить:

```dart
  late final Column<int> reviewReopenCount =
      integer().withDefault(const Constant(0))();
```

Зарегистрировать `BeaconCommitmentEvents` в списке `tables:` аннотации `@DriftDatabase`
в `packages/server/lib/data/database/tentura_db.dart` (после `BeaconHelpOfferAdmissionEvents`).

Запустить `cd packages/server && dart run build_runner build -d`.

### P1.3 Домен: сущность, enum, чистые предикаты

Создать `packages/server/lib/domain/commitment/commitment_event_kind.dart`:

```dart
enum CommitmentEventKind {
  offered(0),
  acknowledged(1),
  acknowledgementSoftened(2),
  withdrawnByHelper(3),
  releasedByAuthor(4),
  removedFromChat(5),
  readmittedToChat(6),
  blockedCleanup(7),
  unansweredAtClose(8);

  const CommitmentEventKind(this.smallintValue);
  final int smallintValue;

  static CommitmentEventKind? tryFromInt(int? v) => switch (v) { ... };
}
```

Создать `packages/server/lib/domain/commitment/commitment_event.dart` — immutable-класс
`CommitmentEvent { id, seq, beaconId, userId, actorUserId, kind, reason, createdAt }`,
статический `newId => generateId('CE')` (см. `packages/server/lib/utils/id.dart`).

Создать `packages/server/lib/consts/commitment_consts.dart`:

```dart
const kCommitmentGracePeriod = Duration(hours: 24);
const kMaxReviewReopens = 1;
```

Создать `packages/server/lib/domain/commitment/commitment_state.dart` — **чистые функции**, без
зависимостей от репозиториев:

```dart
enum CommitmentStakeState { none, offered, acknowledged, softened, exited, released }

bool everAcknowledged(List<CommitmentEvent> events, {Duration grace = kCommitmentGracePeriod});
CommitmentStakeState currentStakeState(List<CommitmentEvent> events);
bool hasCurrentStake(List<CommitmentEvent> events, {required bool hasActiveOffer});
```

Алгоритмы — ровно как в §2.2. Функции обязаны сами сортировать вход по `seq` (не полагаться на
порядок аргумента).

### P1.4 Порт и репозиторий

Создать `packages/server/lib/domain/port/commitment_repository_port.dart`:

```dart
abstract class CommitmentRepositoryPort {
  /// Пишет событие И пересчитывает проекцию `beacon_help_offer.stake_state`
  /// в одной транзакции (см. §2.5). Другого места, где проекция меняется, нет.
  Future<void> record({
    required String beaconId,
    required String userId,
    required String actorUserId,
    required CommitmentEventKind kind,
    String? reason,
  });

  /// Все события запроса, сгруппированные по userId, отсортированные по seq ASC.
  Future<Map<String, List<CommitmentEvent>>> eventsByUser(String beaconId);

  Future<List<CommitmentEvent>> eventsForPair({
    required String beaconId,
    required String userId,
  });
}
```

Создать `packages/server/lib/data/repository/commitment_repository.dart` —
`@Injectable(as: CommitmentRepositoryPort, env: [Environment.dev, Environment.prod], order: 1)`,
внутри — drift-менеджеры, `record` пишет через `_database.withMutatingUser(actorUserId, ...)`.

`record` выполняет **ровно три шага в одной транзакции**:
1. `INSERT` строки события — через `db.customInsert` с явным списком колонок
   `(id, beacon_id, user_id, actor_user_id, kind, reason)` **без `seq`** (его выдаёт `bigserial`),
   ровно по образцу `insertHelpOfferAdmissionEvent`
   (`packages/server/lib/data/repository/help_offer_admission_repository.dart:15`).
   Drift-companion со всеми колонками здесь **не использовать** — он попытается писать `seq`;
2. чтение всех событий пары (`eventsForPair`);
3. `UPDATE beacon_help_offer SET stake_state = <currentStakeState(events).index>` для этой пары
   (индекс = порядковый номер в `CommitmentStakeState`, совпадает с таблицей §2.5).

### P1.5 Доменный сервис-агрегат

Создать `packages/server/lib/domain/use_case/commitment_query_case.dart`
(`@Singleton(order: 2)`, наследует `UseCaseBase`), зависимости: **только**
`CommitmentRepositoryPort` и `HelpOfferRepositoryPort`. `BeaconRepositoryPort` не нужен:
автор не может иметь help-оффер (`authorCannotCommit` в `HelpOfferCase.offerHelp`), поэтому
отдельная фильтрация автора из множеств не требуется.

API — ровно четыре метода, больше ничего:

```dart
Future<Set<String>> everAcknowledgedUserIds(String beaconId);   // без автора
Future<Set<String>> currentCommitterUserIds(String beaconId);   // без автора
Future<bool> everHadCommitter(String beaconId);
Future<bool> everAcknowledgedPair({required String beaconId, required String userId});
```

Никакого `hasMaterialRoomWork` **не создавать** (D11, §2.4): гейт «работа в комнате» из плана
исключён, вместо него — инвариант допуска (P3.10). Новых методов в
`BeaconRoomRepositoryPort` / `CoordinationItemRepositoryPort` эта фаза не добавляет.

### P1.6 Тесты фазы P1

Создать `packages/server/test/domain/commitment/commitment_state_test.dart` — чистые unit-тесты,
без БД, минимум эти кейсы:

1. пустой список → `everAcknowledged == false`, `currentStakeState == none`;
2. offered → `offered`, `everAcknowledged == false`;
3. offered, acknowledged → `acknowledged`, `everAcknowledged == true`;
4. offered, acknowledged, withdrawn через 1 ч → `exited`, `everAcknowledged == false` (грейс);
5. offered, acknowledged, withdrawn через 25 ч → `exited`, `everAcknowledged == true`;
6. offered, acknowledged, softened → `softened`, `everAcknowledged == true`;
7. offered, acknowledged, removedFromChat → `acknowledged` (D5!), `everAcknowledged == true`;
8. offered, acknowledged, releasedByAuthor → `released`, `everAcknowledged == true`;
9. offered, acknowledged, blockedCleanup → `exited`, `everAcknowledged == true`;
10. acknowledged, withdrawn (в грейс), acknowledged повторно, withdrawn через 30 ч →
    `everAcknowledged == true`;
11. вход подан в перемешанном порядке `seq` → результат совпадает с отсортированным;
12. **грейс закрывается промежуточным событием:** acknowledged → acknowledgementSoftened →
    withdrawnByHelper через 1 ч → `everAcknowledged == true`;
13. то же с `removedFromChat` посередине → `everAcknowledged == true`;
14. проекция: для каждого сценария 1–13 `currentStakeState(...).index` совпадает со значением,
    которое репозиторий записал бы в `stake_state` (тест на согласованность §2.5 —
    чистый, без БД: сравнение с ожидаемым числом из таблицы §2.5).

**Acceptance P1:** миграция применяется на чистой и на существующей БД; `dart test` зелёный;
`build_runner` без ошибок; поведение продукта не изменилось (никакие use-case ещё не переключены).

---

## 4. Фаза P2 — запись фактов во всех точках

**Цель:** каждое изменение участия пишет событие. Гейты пока **не переключены** (это P3).

> ⚠️ **P2 и P3 мержатся и релизятся вместе, одним PR/релизом.** После P2 coordination-строка
> перестаёт удаляться при withdraw/блокировке, а старый (ещё не переключённый) гейт Delete
> читает именно текущие строки → на промежуточном состоянии Delete станет **строже**, чем
> сегодня: запрос, где хелпер вышел, удалить будет нельзя, хотя правило «ever» ещё не введено.
> Гейт Cancel на промежуточном состоянии не меняется (он смотрит на активные офферы, а
> withdraw по-прежнему переводит оффер в `status = 1`). Отдельный merge P2 в `main` запрещён.

> **Общее правило записи (действует во всех точках ниже):** событие `acknowledged` пишется
> **только на переход** в признающее состояние. Перед записью проверить текущую проекцию/события:
> если `currentStakeState == acknowledged`, повторное `acknowledged` **не писать**. То же для
> `acknowledgementSoftened` (не писать, если состояние уже `softened`) и для
> `removedFromChat` / `readmittedToChat` (не писать, если доступ и так в этом состоянии).
> Журнал должен отражать переходы, а не повторные нажатия.

Изменения (все — в `packages/server/lib/domain/use_case/`):

### P2.1 `help_offer_case.dart`

- Инжектировать `CommitmentRepositoryPort`.
- В `offerHelp`, в ветке создания нового оффера (внутри `_attention!.runAction`, после
  `_helpOfferRepository.upsert`): записать `CommitmentEventKind.offered`
  (`actorUserId = userId`, `reason = null`).
  В ветке `hasActive` (повторный upsert поверх активного оффера) — **не писать** ничего.
- В `withdraw`: **удалить** вызов `_coordinationRepository.deleteForCommit(...)` целиком.
  Вместо него записать `CommitmentEventKind.withdrawnByHelper` с `reason = withdrawReason`.
  Всё остальное поведение (`_helpOfferRepository.withdraw`, watching/tombstone-ветки) не менять.

### P2.2 `coordination_case.dart`

- Инжектировать `CommitmentRepositoryPort`.
- `acceptHelpOffer`: после `_coordinationRepository.acceptHelpOffer` записать
  `acknowledged` (`actorUserId = actorUserId`).
- `declineHelpOffer`: после успешного decline записать `acknowledgementSoftened`, **только если**
  до этого у пары уже было `acknowledged` (проверять `everAcknowledged` через
  `CommitmentQueryCase`); иначе не писать ничего.
- `removeFromRoom`: записать `removedFromChat` с `reason = trimmedReason`.
- `setCoordinationResponse`: после `upsertResponse`
  - если новый `responseType ∈ {useful(0), needCoordination(3)}` → записать `acknowledged`;
  - иначе, если у пары уже было `acknowledged` → записать `acknowledgementSoftened`;
  - иначе не писать ничего.
  Дополнительно: если аргумент `removeFromRoom == true` → записать также `removedFromChat`
  (`reason = null`); если `inviteToRoom == true` и участник ранее имел `removedFromChat` →
  записать `readmittedToChat`.

### P2.3 `user_block_case.dart`

- В `_withdrawOffersByOfferer`: **удалить** вызов `_coordination.deleteForCommit(...)`.
  Вместо него записать `CommitmentEventKind.blockedCleanup` с `reason = kBlockWithdrawReason`.
  Остальная логика (withdraw оффера, watching/tombstone) без изменений.

### P2.4 Удаление мёртвого API

После P2.1–P2.3 у `deleteForCommit` не остаётся вызовов. Удалить метод из
`CoordinationRepositoryPort` и из `CoordinationRepository`, а также все моки/стабы в тестах.
Проверить `grep -rn "deleteForCommit" packages/server` → должно быть пусто.

### P2.5 Тесты фазы P2

Расширить/создать:
- `packages/server/test/domain/use_case/help_offer_case_test.dart` — withdraw пишет событие
  и **не удаляет** coordination-строку;
- `packages/server/test/domain/use_case/coordination_case_revert_test.dart` (или новый
  `coordination_case_commitment_events_test.dart`) — accept/decline/remove/setResponse пишут
  ожидаемые виды событий;
- `packages/server/test/domain/use_case/user_block_case_test.dart` — блок пишет `blockedCleanup`
  и сохраняет coordination-строку.

**Acceptance P2:** после любого из этих действий строка `beacon_help_offer_coordination` больше
никогда не исчезает; в `beacon_commitment_event` появляются корректные записи; существующие тесты
зелёные (кроме тех, что явно проверяли удаление строки — их обновить под новое поведение,
изменение зафиксировать в журнале).

---

## 5. Фаза P3 — переключение гейтов на факты

### P3.1 Cancel (`beacon_case.dart`, `beaconCancel`)

Заменить блок вычисления `hasCommitters` (текущие `coords` + `activeOffers`) на:

```dart
if (await _commitmentQueryCase.everHadCommitter(beaconId)) {
  throw EvaluationException(
    evaluationCode: EvaluationExceptionCode.beaconNotClosable,
    description: 'Cannot cancel a request that ever had a committer',
  );
}
```

### P3.2 Delete (`beacon_case.dart`, `deleteById`)

Заменить `everHadAcknowledgedCommitter` (по `coords`) на:

```dart
if (await _commitmentQueryCase.everHadCommitter(beacon.id)) {
  throw EvaluationException(
    evaluationCode: EvaluationExceptionCode.beaconNotClosable,
    description: 'Cannot delete a request that ever had a committer',
  );
}
```

Ветку `BeaconStatus.draft` (хард-делит черновика) **не трогать** — она выполняется до этой
проверки и остаётся безусловной. Никакой проверки «работы в комнате» здесь **нет** (D11).

### P3.3 Роль `formerCommitter` — полная спецификация

Добавление значения в enum ломает **три** exhaustive-switch и молча ломает **один** if-chain.
Все четыре места обязательны, иначе код не соберётся или роль окажется пустой.

1. `packages/server/lib/domain/evaluation/evaluation_participant_role.dart`:
   `formerCommitter(3)` **в конец** enum, ветка `3 => formerCommitter` в `fromDb`.
   Миграция БД не нужна (CHECK на `role` отсутствует — проверено в `m0019`).
2. `packages/server/lib/domain/evaluation/evaluation_reason_tags.dart`:
   - `allowedForRoleAndSign` (`switch/case` по роли, ~строка 48): ветка `formerCommitter`
     возвращает **те же наборы**, что `committer` (`committerNegative` / `committerPositive`);
   - `allowedUnionForRole` (switch-**выражение**, ~строка 68 — без ветки не скомпилируется):
     `formerCommitter => [...committerPositive, ...committerNegative]`.
3. `packages/server/lib/domain/evaluation/evaluation_summary_rules.dart` (~строка 97,
   switch-выражение): `EvaluationParticipantRole.formerCommitter => 'Former committer'`.
4. `packages/server/lib/domain/evaluation/evaluation_visibility_rules.dart`,
   `buildEvaluationVisibility` — это **цепочка `if`**, компилятор молчит, а роль без ветки
   не получает ни одного исходящего ребра (то есть не может никого оценить, и продуктовое
   решение D8 остаётся пустым). Правки:
   - ветка `if (e.role == committer)` → `if (e.role == committer || e.role == formerCommitter)`;
   - внутри неё условие «другие committer'ы» → `p.role == committer || p.role == formerCommitter`;
   - ветка автора уже покрывает всех участников — трогать не нужно;
   - ветка forwarder не меняется.
   Иначе говоря: **former committer видит и оценивает ровно то же, что committer.**
5. `_canCloseNow` (P3.6) роль 3 **не** учитывает — так и должно быть: ушедший не блокирует
   досрочное закрытие.

Тесты (в `packages/server/test/domain/use_case/evaluation/` — найти существующие тесты
visibility/тегов и расширить): former committer получает рёбра к автору и к остальным
committer'ам/former'ам; допустимые reason-теги совпадают с committer; `evaluationRoleSummaryLine`
возвращает 'Former committer'.

### P3.4 Состав ревью (`evaluation_participant_graph_builder.dart`)

DI: `EvaluationParticipantGraphBuilder` (`@Injectable(order: 2)`) сейчас получает
help-offer / coordination / forward / user порты. Добавить в конструктор
**`CommitmentRepositoryPort`** (order 1) и использовать чистые функции из
`domain/commitment/commitment_state.dart` напрямую. `CommitmentQueryCase` сюда **не** инжектить —
это case→case зависимость с тем же `order: 2`.

Переписать `build`:

1. `everAck` := userIds, у которых `everAcknowledged(events) == true`
2. `current` := userIds с `hasCurrentStake(events, hasActiveOffer: ...) == true`
3. Для каждого `u ∈ everAck` — участник с ролью
   `current.contains(u) ? committer : formerCommitter`.
4. `contributionSummary` / `causalHint` для `formerCommitter` формируются с суффиксом
   ` — participation ended` (английский, как остальные строки этого файла: они серверные и
   не локализуются).
5. Форвардеры вычисляются как сейчас, но по объединённому множеству `everAck` (а не только по
   активным офферам).
6. `message` и `createdAt` для summary берутся из `HelpOfferEntity`, полученной через
   `fetchAllByBeaconId` (не `fetchByBeaconId`) — иначе у ушедших не будет данных.

Правила видимости (`EvaluationVisibilityPair`) строятся по тому же расширенному составу.

### P3.5 Close (`evaluation_case.dart`, `beaconClose`)

- `requiresReviewWindow := await _commitmentQueryCase.everHadCommitter(beaconId)`
  (вместо подсчёта committer-ролей в графе).
- Проверку `expectedRequiresReviewWindow` оставить как есть.
- Перед транзицией статуса: для каждого активного оффера с `offerKind == 0` (обычного, **не**
  backup) и **без** ответа автора записать `CommitmentEventKind.unansweredAtClose`
  (`actorUserId = автор`, `reason = null`). Оффер при этом **не** withdraw-ится и не отклоняется.
  Backup-офферы (`offerKind == 1`) пропускаются: продуктово они не ждут ответа (см. P6.2 и P8.3 —
  везде, где считаются «неотвеченные», условие одинаковое: `status == 0 && offerKind == 0 &&
  ответа нет`). Колонка `offer_kind` существует с P1, поэтому фильтр доступен уже здесь.

### P3.6 `Close now` (`evaluation_case.dart`, `_canCloseNow`)

Блокирующими остаются роли `author(0)` и `committer(1)`. Явно **исключить** `formerCommitter(3)`
и `forwarder(2)`:

```dart
if (p.role != EvaluationParticipantRole.author.dbValue &&
    p.role != EvaluationParticipantRole.committer.dbValue) {
  continue;
}
```
(условие уже такое — убедиться, что после добавления роли 3 оно не изменилось, и добавить тест.)

### P3.7 Лимит Reopen (`evaluation_case.dart`, `reopenFromReview`)

- Добавить в `BeaconRepositoryPort` метод
  `Future<int> reviewReopenCount(String beaconId)` и
  `Future<void> incrementReviewReopenCount(String beaconId)` (колонка из P1.1 п. 8).
- В `reopenFromReview`, после проверок статуса и окна:

```dart
if (await _beaconRepository.reviewReopenCount(beaconId) >= kMaxReviewReopens) {
  throw EvaluationException(
    evaluationCode: EvaluationExceptionCode.beaconNotClosable,
    description: 'Reopen limit reached',
  );
}
```
и инкремент внутри той же транзакции после успешной транзиции статуса.

### P3.8 Запрет withdraw в Wrapping up

- `packages/server/lib/domain/entity/beacon_entity.dart`:
  `bool get allowsBeaconWithdraw => status.isOpenFamily;` (было `status.allowsCoordination`).
  **`allowsCoordination` не менять** — от него зависят coordination items.
- Клиентский зеркальный гейт: `packages/client/lib/domain/entity/beacon.dart`
  `allowsWithdrawWhileHelpOffered => status.isOpenFamily;`
- Обновить `docs/before-response-terminal-tombstone.md` §«Withdraw (`beaconWithdraw`)» — ветка
  «beacon не в open family» становится недостижимой для пользовательского withdraw и остаётся
  только для блокировок; текст скорректировать, ветку кода **оставить**.

### P3.9 Запрет понижения после признания

В `coordination_case.dart`:

- Добавить в `HelpOfferCoordinationExceptionCode` **в конец** значение
  `commitmentAlreadyAcknowledged`.
- В `setCoordinationResponse`: если новый `responseType ∉ {0, 3}` и
  `everAcknowledged(beaconId, offerUserId) == true` → бросить
  `HelpOfferCoordinationException(coordinationCode: commitmentAlreadyAcknowledged)`.
- В `declineHelpOffer`: заменить проверку `participant?.roomAccess == RoomAccessBits.admitted`
  → `alreadyAdmitted` на проверку `everAcknowledged` → `commitmentAlreadyAcknowledged`.
  (Значение `alreadyAdmitted` из enum **не удалять**.)

**Что при этом остаётся разрешённым (D13, не считать багом):** признающий ответ
(`useful` / `needCoordination`) после `releasedByAuthor` или после `withdrawnByHelper`
с последующим новым оффером — разрешён и снова даёт current stake. То есть «Завершить участие»
обратимо тем же автором, без требования нового предложения от хелпера. Запрещено только
**понижение** после признания. Тест на это — в P3.12.

### P3.10 Инвариант допуска: в комнату — только вместе с признанием (§2.4, D11)

В `coordination_case.dart`, `setCoordinationResponse`:

- добавить в `HelpOfferCoordinationExceptionCode` **в конец** значение
  `admissionRequiresAcknowledgement`;
- перед выполнением: если `inviteToRoom == true` и `responseType ∉ {useful(0),
  needCoordination(3)}` → бросить `HelpOfferCoordinationException(coordinationCode:
  admissionRequiresAcknowledgement)`;
- порядок проверок: сначала существующие (автор, статус, валидность `responseType`, активность
  оффера), затем эта, затем P3.9 (запрет понижения), затем запись.

Клиент: в месте, где собирается вызов `setCoordinationResponse`
(`packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart` и пикер ответа),
запретить комбинацию «не-признающий ответ + пригласить в чат» на уровне UI (чекбокс/переключатель
приглашения выключен и недоступен для таких ответов), чтобы ошибка сервера была недостижима
обычным путём.

### P3.11 Клиентская правда об участии и контракт Close (**блокирующая часть релиза**)

Без этого пункта ядро смержится в заведомо красный Close. Причина — сервер после P3.5 считает
`requiresReviewWindow` по `everHadCommitter`, а клиент считает по активным офферам:

```dart
// packages/client/lib/features/beacon_view/ui/util/beacon_closure_readiness.dart:244
bool helpOfferIsCommitter(TimelineHelpOffer offer) =>
    !offer.isWithdrawn &&
    (offer.coordinationResponse == CoordinationResponseType.useful ||
        offer.coordinationResponse == CoordinationResponseType.needCoordination);
bool expectedRequiresReviewWindowForState(BeaconViewState state) =>
    state.helpOffers.any(helpOfferIsCommitter);
```

Сценарий отказа: accept → withdraw через 30 ч → сервер `true`, клиент `false` →
`EvaluationExceptionCode.closeBranchConflict` на каждой попытке закрыть. То же после блокировки
и после `releaseCommitment`. Второй источник той же ошибки —
`my_work_cards.dart:336` и `:661`: `expectedRequiresReviewWindow: b.helpOfferCount > 0`.

**Этот пункт выполняется в том же PR, что P1–P3.** Порядок внутри пункта:

1. **Серверное поле `stakeState` на строке оффера** (то, что в ранней редакции стояло в P4.1b —
   переносится сюда целиком):
   - `HelpOfferWithCoordinationRow` → поля `int stakeState`, `int offerKind` (+ `copyWith`);
   - `CoordinationRepository.helpOffersWithCoordination` читает обе колонки;
   - `custom_types.dart` → `gqlTypeHelpOfferWithCoordinationRow`: `stakeState`, `offerKind`
     (`graphQLInt.nonNullable()`); `gql_v2_dto_maps.dart` → ключи в map.
2. **Клиентская модель:** `packages/client/lib/domain/entity/commitment_stake_state.dart`
   с enum `CommitmentStakeState { none, offered, acknowledged, softened, exited, released }`
   и `fromInt` (неизвестное число → `none`); значения ровно как в §2.5.
   Протащить `stakeState` в `TimelineHelpOffer` (найти его определение и маппер из GQL-модели)
   и в клиентский `schema.graphql` + `.graphql`-запрос People-таба.
3. **Правда об участии:**
   ```dart
   bool helpOfferIsCommitter(TimelineHelpOffer offer) =>
       offer.stakeState == CommitmentStakeState.acknowledged;
   ```
   Это одна строка, но она чинит `beaconStateHasCommitters`, `expectedRequiresReviewWindowForState`,
   `computeClosureReadiness`, HUD (`beacon_hud_author_action.dart:99`) и статус-меню разом.
   `coordinationResponse` остаётся только там, где показывается **сам ответ автора**.
4. **Серверный счётчик как источник для My Work:** в `my_work_cards.dart:336` и `:661` заменить
   `b.helpOfferCount > 0` на значение из `beaconDisplayStatuses.everAcknowledgedCommitterCount`
   (поле вводится в P8.1 — **значит P8.1 тоже входит в этот PR**, см. §13). До получения DTO
   карточка не показывает действие закрытия (кнопка disabled), а не шлёт заведомо неверный флаг.
5. **Контракт версии:** старые клиенты продолжат слать неверный `expected` → см. §12.3
   (подъём `kDefaultMinClientVersion` обязателен в этом релизе).

Тесты:
- unit `beacon_closure_readiness`: оффер `useful` + `stakeState == released` → **не** committer;
  `stakeState == exited` → не committer; `acknowledged` → committer;
- unit: `expectedRequiresReviewWindowForState` после withdraw через 30 ч даёт `true`
  (совпадает с сервером), потому что `stakeState` у ушедшего — `exited`, но
  `everAcknowledgedCommitterCount > 0` приходит с сервера;
  **важно:** для beacon-view экрана источником `expected` становится тот же серверный счётчик,
  а не локальный обход `helpOffers` — переписать `expectedRequiresReviewWindowForState`
  на поле DTO, оставив локальный обход только как фолбэк, когда DTO ещё не загружен
  (в этом случае кнопка закрытия disabled);
- серверный тест: `beaconClose` с `expectedRequiresReviewWindow`, посчитанным по новому правилу,
  не бросает `closeBranchConflict` в сценарии accept → withdraw (30 ч).

### P3.12 Тесты фазы P3

Новый файл `packages/server/test/domain/use_case/commitment_gates_test.dart` со сценариями:

| # | Сценарий | Ожидание |
|---|----------|----------|
| 1 | оффер без ответа → Cancel | разрешён |
| 2 | оффер + accept → Cancel | запрещён |
| 3 | оффер + accept + withdraw через 30 ч → Cancel | **запрещён** |
| 4 | оффер + accept + withdraw через 1 ч → Cancel | разрешён (грейс) |
| 5 | оффер + accept + withdraw через 30 ч → Delete | запрещён |
| 6 | оффер + accept + block → Delete | запрещён |
| 7 | оффер + accept → decline | ошибка `commitmentAlreadyAcknowledged` |
| 8 | оффер + accept → setCoordinationResponse(notSuitable) | ошибка `commitmentAlreadyAcknowledged` |
| 9 | `setCoordinationResponse(responseType: notSuitable, inviteToRoom: true)` | ошибка `admissionRequiresAcknowledgement` |
| 10 | оффер + accept + withdraw через 30 ч → Close | открывает review window |
| 11 | тот же сценарий: состав ревью | ушедший присутствует с ролью `formerCommitter` |
| 12 | `closeNow` при незавершённом ревью `formerCommitter` | разрешён |
| 13 | `closeNow` при незавершённом ревью активного committer | запрещён |
| 14 | Reopen дважды | вторая попытка — ошибка |
| 15 | `beaconWithdraw` при `reviewOpen` | ошибка `beaconWithdrawForbidden` |
| 16 | release → `setCoordinationResponse(useful)` по тому же офферу | разрешено, current stake вернулся, в журнале оба события (D13) |
| 17 | Close после accept → withdraw (30 ч) с `expectedRequiresReviewWindow`, посчитанным по P3.11 | без `closeBranchConflict`, открывается review window |
| 18 | состав ревью в сценарии 17 | ушедший — роль 3; у него есть рёбра видимости к автору и к остальным committer'ам (P3.3 п. 4) |

**Acceptance P3:** все 15 сценариев зелёные; существующие тесты
(`beacon_case_cancel_test.dart`, `beacon_case_delete_test.dart`) обновлены под новые правила
и зелёные.

---

## 6. Фаза P4 — «Завершить участие» (решение D5/O2)

### P4.1 Сервер

`coordination_case.dart`, новый метод:

```dart
Future<BeaconStatusResult> releaseCommitment({
  required String beaconId,
  required String offerUserId,
  required String authorUserId,
  required String reason,
})
```

Правила:
1. `_ensureAuthor` (только автор).
2. Статус должен быть в `isOpenFamily`, иначе `beaconNotOpen`.
3. Причина обязательна: переиспользовать `_validateReason` (1..500 символов).
4. Если у пары нет `acknowledged` → новый код `commitmentNotAcknowledged`
   (добавить **в конец** `HelpOfferCoordinationExceptionCode`; **не** переиспользовать
   `helpOfferNotActive` — он про неактивный оффер и вводит в заблуждение).
5. Если текущее состояние уже `released`/`exited` → идемпотентно вернуть текущий снапшот
   без новой записи.
6. Записать `CommitmentEventKind.releasedByAuthor` с причиной. Проекция `stake_state` при этом
   станет `5 = released` автоматически (P1.4) — отдельно её **не** трогать.
7. `beacon_help_offer.status` **не** менять (оффер не withdraw-ится),
   `beacon_help_offer_coordination` **не** менять, доступ в комнату **не** трогать
   (это отдельное действие — D5/O2).
8. Записать attention-intent `commitmentReleased` (новый, см. P4.1a) — получатель `offerUserId`.
   **Не** переиспользовать `offerRemoved`: у него копирайт «Removed from chat», и квитанция
   будет врать.
9. Вернуть `_statusResult(beaconId, snapshot)`.

### P4.1a Новая квитанция `commitmentReleased`

Копирайт строится по `NotificationKind` (`beacon_notification_copy_builder.dart:34` —
`switch (intent.kind)`), поэтому отдельный текст требует нового вида. Изменения (все —
добавление значения **в конец** enum, ничего не переставлять):

1. `packages/server/lib/domain/entity/notification_kind.dart` → `commitmentReleased`.
2. `packages/server/lib/domain/entity/notification_category.dart` → сопоставить с той же
   категорией, что `commitmentRemoved` (найти `categoryOf` и добавить ветку рядом).
3. `packages/server/lib/domain/notification/beacon_notification_copy_builder.dart`:
   - `switch (intent.kind)` → заголовок `'Participation ended'`, тело через `_bodyWithRequest`
     с fallback `'The author ended your participation in this request'`;
   - deep-link `switch` → тот же путь, что у `commitmentRemoved`
     (`'/#$kPathAppLinkView?id=$id&dest=people'`).
4. `packages/server/lib/domain/notification/beacon_notification_recipient_resolver.dart` и
   `beacon_notification_batch_aggregator.dart` — добавить ветку по образцу `commitmentRemoved`
   (в обоих файлах `commitmentRemoved` уже встречается; повторить один в один).
5. `packages/server/lib/domain/attention/attention_models.dart` → `AttentionEventType`,
   значение `commitmentReleased` **в конец**.
6. `attention_intent_case.dart` → метод `commitmentReleased({receiverId, beaconId, actorUserId,
   reason, sourceEventKey})` по образцу `offerRemoved`, с `kind: NotificationKind.commitmentReleased`
   и `eventType: AttentionEventType.commitmentReleased`.
7. Тест: `packages/server/test/domain/attention/attention_intent_case_test.dart` — добавить кейс
   по образцу существующего для `offerRemoved`.

### P4.1b Сигнал состояния участия для клиента

**Перенесено в P3.11** (пункты 1–3), потому что от него зависит контракт Close и корректность
`helpOfferIsCommitter`. К моменту P4 поля `stakeState` / `offerKind` уже есть и на сервере,
и в клиентской модели `TimelineHelpOffer`. Здесь — ничего не делать, только использовать.

### P4.2 GraphQL

`packages/server/lib/api/controllers/graphql/mutation/mutation_coordination.dart`:
добавить поле `releaseCommitment(id: String!, offerUserId: String!, reason: String!)
: v2_BeaconStatusResult!` по образцу `removeFromRoom`, включить в геттер `all`.

### P4.3 Клиент

1. `packages/client/lib/data/gql/schema.graphql`: добавить строку мутации в тип `mutation_root`
   рядом с `removeFromRoom` (сохранить алфавитный порядок файла, если он есть).
2. Новый файл `packages/client/lib/features/beacon_view/data/gql/beacon_release_commitment.graphql`:

```graphql
mutation BeaconReleaseCommitment($id: String!, $offerUserId: String!, $reason: String!) {
  releaseCommitment(id: $id, offerUserId: $offerUserId, reason: $reason) {
    beaconId
    status
    statusChangedAt
  }
}
```
3. Зарегистрировать `'BeaconReleaseCommitment'` в `_tenturaDirectOperationNames`
   (`build_client.dart`).
4. Оркестрация — **через use case, не из кубита в репозиторий**: `BeaconViewCubit` ходит только
   в `_case` (`beacon_view_case.dart`, ср. `acceptHelpOffer` на ~строке 209). Добавить метод
   `releaseCommitment` в `BeaconViewCase` по образцу `acceptHelpOffer`/`removeFromRoom`,
   репозиторный вызов — внутри case; кубит вызывает `_case.releaseCommitment(...)` и делает
   оптимистичный патч состояния так же, как для `removeFromRoom`.
5. UI (`beacon_people_tab_body.dart` + `help_offer_tile.dart`) — всё завязано на `stakeState`
   из P3.11, **не** на `responseType`:
   - существующее действие «Remove from chat» остаётся и **меняет только доступ**;
   - в диалоге remove добавить пояснительную строку (новый l10n-ключ
     `helpOfferRemoveKeepsParticipationNote`): «Только доступ к чату — участие сохраняется.
     Чтобы завершить участие, используйте «Завершить участие».»;
   - новое действие `onReleaseCommitment` (l10n `helpOfferReleaseCommitment`) показывать
     **тогда и только тогда**, когда `stakeState == acknowledged`. При `released` / `exited` /
     `softened` / `offered` / `none` — не показывать;
   - при выборе — тот же `HelpOfferAdmissionReasonDialog` с заголовком
     `helpOfferReleaseDialogTitle` и хинтом `helpOfferReleaseDialogHint`;
   - метки состояния в тайле (взаимоисключающие, по `stakeState`):
     `released` → `helpOfferParticipationEndedLabel` («Участие завершено»),
     `exited` → существующая метка withdrawn (не менять),
     `softened` → `helpOfferAcknowledgementSoftenedLabel` («Ответ автора изменён»),
     `acknowledged` → существующая метка принятого оффера.
   - существующие места, где тайл/список судят об участии по `authorResponseType`, перевести
     на `stakeState` (grep по `coordinationResponse` / `responseType` внутри
     `help_offer_tile.dart` и `beacon_people_tab_body.dart`; `responseType` остаётся только
     там, где показывается **сам ответ автора** как таковой).

### P4.4 l10n

Добавить в `packages/client/l10n/app_en.arb` и `app_ru.arb` (с `@`-описаниями, как в файле):

| Ключ | EN | RU |
|------|----|----|
| `helpOfferRemoveKeepsParticipationNote` | "Chat access only — participation stays recorded." | «Только доступ к чату — участие сохраняется.» |
| `helpOfferReleaseCommitment` | "End participation" | «Завершить участие» |
| `helpOfferReleaseDialogTitle` | "End participation?" | «Завершить участие?» |
| `helpOfferReleaseDialogHint` | "Why is this participation ending?" | «Почему участие завершается?» |
| `helpOfferParticipationEndedLabel` | "Participation ended" | «Участие завершено» |
| `helpOfferAcknowledgementSoftenedLabel` | "Author's reply changed" | «Ответ автора изменён» |

> Перед добавлением любого ключа — `grep` по `packages/client/l10n/app_en.arb`. Если ключ уже
> есть (как `beaconDeleteBlockedTitle` / `beaconDeleteBlockedBody` / `myWorkArchive`), **новый не
> создавать и текст существующего не переписывать** без отдельной причины.

### P4.5 Тесты P4

- Сервер: `packages/server/test/domain/use_case/coordination_case_release_test.dart` —
  release без acknowledged → ошибка `commitmentNotAcknowledged`; release убирает current stake,
  но не снимает `everAcknowledged`; после release Cancel по-прежнему запрещён; повторный release
  идемпотентен (второго события нет); проекция `stake_state` стала `5`.
- Клиент: виджет-тест на `beacon_people_tab_body` — действие «Завершить участие» видно при
  `stakeState == acknowledged` и **исчезает** после release (`stakeState == released`), а тайл
  показывает `helpOfferParticipationEndedLabel`.

**Acceptance P4:** автор может явно завершить участие; remove из чата больше не создаёт
двусмысленности (текст в диалоге); Cancel после release остаётся закрытым.

---

## 7. Фаза P5 — удаление auto-admit (D4)

1. `packages/server/lib/domain/use_case/help_offer_case.dart`:
   - удалить метод `_autoAdmitIfTrusted` целиком;
   - удалить его вызов в конце `offerHelp`;
   - удалить ставшие неиспользуемыми зависимости `ForwardEdgeRepositoryPort`,
     `HelpOfferAdmissionRepositoryPort`, `BeaconRoomRepositoryPort`, **только если** после удаления
     на них нет других ссылок в файле (проверить grep по файлу; лишние поля не оставлять).
2. `HelpOfferAdmissionAction.autoAdmit` и `BeaconRoomAdmissionReason.autoAdmit` **оставить** —
   исторические строки должны читаться.
3. Признак «автор переслал лично» вместо авто-допуска:
   - `packages/server/lib/domain/entity/gql_public/help_offer_with_coordination_row.dart`:
     добавить поле `bool isDirectAuthorForward`;
   - в `CoordinationRepository.helpOffersWithCoordination` заполнять его через существующий
     `ForwardEdgeRepositoryPort.isDirectAuthorForward` (или прямым запросом к
     `beacon_forward_edge`, если так проще в одном SQL: `sender_id = автор AND recipient_id =
     offer_user_id AND cancelled_at IS NULL`);
   - `custom_types.dart` → `gqlTypeHelpOfferWithCoordinationRow`: добавить
     `field('isDirectAuthorForward', graphQLBoolean.nonNullable())`;
   - маппер в `gql_v2_dto_maps.dart` — добавить ключ;
   - клиент: `schema.graphql` + соответствующий `.graphql`-запрос (найти запрос, который тянет
     `helpOffersWithCoordination`) + модель + entity;
   - UI: в `help_offer_tile.dart` показывать чип `helpOfferDirectForwardChip`
     (EN "Forwarded by you" / RU «Вы переслали лично») и сортировать такие офферы **вверх**
     в списке People (сортировка — в месте построения списка в `beacon_people_tab_body.dart`).
4. Тесты:
   - удалить/переписать те кейсы `beacon_room_admission_matrix_test.dart`, которые проверяют
     авто-допуск; добавить кейс «прямой форвард автора + оффер → доступа в комнату **нет** до
     явного Accept»;
   - `help_offer_case_test.dart` — оффер от прямого адресата не создаёт coordination-строку.

**Acceptance P5:** после оффера от прямого адресата автора участник не имеет доступа в чат и не
считается committer'ом; в People tab его оффер помечен чипом и стоит выше остальных.

---

## 8. Фаза P6 — «Enough help»: Forward primary + backup-офферы (D2, вариант A+B)

### P6.1 Сервер: тип оффера

- Колонка `offer_kind`, поле `HelpOfferEntity.offerKind` и чтение в `_toEntity` уже сделаны
  в P1 — **повторно не создавать**.
- `HelpOfferRepositoryPort.upsert` — добавить именованный параметр `int offerKind = 0`;
  в реализации писать колонку.
- `HelpOfferCase.offerHelp`: перед вставкой вычислить
  `final offerKind = beacon.status == BeaconStatus.enoughHelp ? 1 : 0;`
  и передать в `upsert`. Для повторного upsert поверх активного оффера — **не менять** `offerKind`
  (передавать текущее значение).

### P6.2 Сервер: «неотвеченные офферы» игнорируют backup

`packages/server/lib/domain/use_case/beacon_display_case.dart`, вычисление `hasUnreviewed`:

```dart
final hasUnreviewed = beacon.status.isOpenFamily &&
    offers.any((o) => o.status == 0 && o.offerKind == 0 && coords[o.userId] == null);
```

### P6.3 Сервер: ACT при enoughHelp

`packages/server/lib/domain/coordination/derive_beacon_display_status.dart`, функция
`_derivePublic`, ветка `status == BeaconStatus.enoughHelp`:
`suggestedAction: BeaconDisplayPrimaryAction.forward` (было `offerHelp`).
Ветку `_deriveCoordination` (`none`) **не трогать**.

### P6.4 Клиент: зеркальная деривация

`packages/client/lib/domain/coordination/derive_beacon_coordination_phase.dart`,
`_derivePublicTier`, ветка `enoughHelp`: `suggestedAction: BeaconPhasePrimaryAction.forward`.

### P6.5 Клиент: вторичное действие «предложить как запасной»

- Найти место рендера ACT-кнопки (`beacon_hud_action_button.dart` /
  `beacon_definition_hud_row.dart`).
- При `phase == enoughHelpInMotion` и tier == public: primary — Forward, а под ним текстовая
  вторичная кнопка с l10n-ключом `beaconOfferHelpAsBackup` («Предложить как запасной вариант»).
  Нажатие открывает тот же поток оффера, что и обычная кнопка (никаких новых аргументов мутации:
  тип оффера определяет сервер).
- В People tab: офферы с `offerKind == 1` показывать отдельной группой под заголовком
  `helpOffersBackupGroupTitle` («На подхвате»), ниже обычных. Поле `offerKind` уже протянуто
  в `HelpOfferWithCoordinationRow` и клиентскую модель в P3.11 — заново не тащить.
- **Клиентский счётчик неотвеченных офферов** — `beacon_view_state.dart`,
  геттер `unansweredHelpOffersCount` (строка ~342): добавить в фильтр условие
  `c.offerKind == 0`. Иначе backup-оффер поднимет автору «офферы ждут ответа» и попадёт
  в предупреждение перед закрытием (P8.3) — расхождение с серверным `hasUnreviewedOffers`.

### P6.6 l10n P6

| Ключ | EN | RU |
|------|----|----|
| `beaconOfferHelpAsBackup` | "Offer as backup" | «Предложить как запасной вариант» |
| `helpOffersBackupGroupTitle` | "Backup offers" | «На подхвате» |
| `helpOfferBackupBadge` | "Backup" | «Запасной» |

### P6.7 Тесты P6

- `packages/server/test/domain/use_case/beacon_display_case_test.dart`: при `enoughHelp`
  public tier → `forward`; backup-оффер без ответа не переводит фазу в `offersAwaitingAuthor`.
- `packages/client/test/domain/coordination/…` (найти существующий тест деривации фазы):
  зеркальный кейс.
- Тест `help_offer_case_test.dart`: оффер при `enoughHelp` записывается с `offerKind = 1`,
  при `open`/`needsMoreHelp` — с 0.

### P6.8 Hasura

Уже сделано в P1.1 шаг 13 (`offer_kind` и `stake_state` в `select_permissions.columns`).
Здесь только проверить, что метаданные применены: `./scripts/hasura_apply_metadata.sh`.

**Acceptance P6:** при «помощи достаточно» получатель видит Forward как основное действие и
«предложить как запасной» как вторичное; backup-офферы не создают у автора статус
«офферы ждут ответа»; в People tab они в отдельной группе.

---

## 9. Фаза P7 — состояние ответа автора на карточке My Work (D3)

### P7.1 Данные

`MyWorkCardViewModel.authorResponseType` уже существует и приходит из
`my_work_fetch.graphql` (`coordination { response_type updated_at }`). Этого мало: после
withdraw / release / блокировки `response_type` остаётся `useful`, и карточка вечно показывала бы
«Автор принял». Источник состояния — проекция `stake_state` (§2.5).

Изменения в запросе `my_work_fetch.graphql` (обе операции — `MyWorkInit` и `MyWorkArchived`):
в выборку `beacon_help_offer` добавить `stake_state` (колонка открыта в Hasura в P1.1 шаг 13).
`offer_kind` в My Work **не нужен** — не добавлять.

Прокинуть значение: `my_work_fetch_types.dart` → `MyWorkHelpOfferedRow.stakeState`
(тип `CommitmentStakeState` из P3.11) → `my_work_repository.dart` (оба маппера) →
`MyWorkCardViewModel.stakeState`.

Состояние строки вычисляется **на клиенте** новой чистой функцией
`packages/client/lib/features/my_work/domain/derive_offer_response_state.dart`:

```dart
enum MyWorkOfferResponseState {
  awaitingAuthor,          // stake == offered/none && beacon в open-family
  accepted,                // stake == acknowledged
  declined,                // stake ∈ {offered, none} + ответ автора не признающий
  softened,                // stake == softened  — автор изменил ответ
  participationEnded,      // stake == released  — автор завершил участие
  exited,                  // stake == exited    — вышел сам / блокировка
  closedWithoutResponse,   // stake ∈ {offered, none}, ответа нет, beacon вне open-family
}

MyWorkOfferResponseState deriveMyWorkOfferResponseState({
  required CommitmentStakeState stakeState,
  required CoordinationResponseType? authorResponseType,
  required BeaconStatus beaconStatus,
});
```

Приоритет веток (первое совпадение выигрывает, порядок обязателен):
`released` → `exited` → `softened` → `acknowledged` → (нет ответа && beacon вне open-family)
→ (ответ есть && не признающий) → иначе `awaitingAuthor`.

### P7.2 UI

Новый виджет `packages/client/lib/features/my_work/ui/widget/my_work_offer_response_row.dart`:
строка «иконка + текст», токены из design system, без сырых цветов; тон — по состоянию
(`awaitingAuthor` → `textMuted`, `accepted` → `good`, `declined` / `exited` → `textMuted`,
`softened` / `participationEnded` / `closedWithoutResponse` → `warn`).

Встроить в **все три** места рендера help-offered карточек в
`packages/client/lib/features/my_work/ui/widget/my_work_cards.dart`
(там, где сейчас `beaconDeleteBlockedByCommitters` встречается трижды — рядом с ними находятся
билдеры карточек `helpOfferedActive` / `helpOfferedFinished` / `helpOfferedArchived`).
Строка ставится под заголовком карточки, до `my_work_last_event_row`.

Мёртвые `MyWorkStatusLineData.slot1ResponseType` / `slot1CoordinationStatus` — **удалить**
(и их использование в конструкторе), чтобы не осталось второго нерабочего пути.

### P7.3 l10n P7

| Ключ | EN | RU |
|------|----|----|
| `myWorkOfferAwaitingAuthor` | "Waiting for the author's reply" | «Ждёт ответа автора» |
| `myWorkOfferAccepted` | "Author accepted your offer" | «Автор принял ваше предложение» |
| `myWorkOfferDeclined` | "Author declined your offer" | «Автор отклонил ваше предложение» |
| `myWorkOfferSoftened` | "Author changed their reply" | «Автор изменил свой ответ» |
| `myWorkOfferParticipationEnded` | "Author ended your participation" | «Автор завершил ваше участие» |
| `myWorkOfferExited` | "You left this work" | «Вы вышли из этой работы» |
| `myWorkOfferClosedWithoutResponse` | "Author closed the request without replying to your offer" | «Автор закрыл запрос, не ответив на ваше предложение» |

Существующий ключ `myWorkStatusHelpOfferWithResponse` больше не нужен — удалить из обоих `.arb`
и убедиться, что после `flutter gen-l10n` он исчез из `lib/ui/l10n/`.

### P7.4 Тесты P7

- Unit: `packages/client/test/features/my_work/derive_offer_response_state_test.dart` — все 7
  состояний + граничные: `reviewOpen` без ответа → `closedWithoutResponse`;
  `stakeState == released` при `authorResponseType == useful` → `participationEnded`
  (а **не** `accepted` — это регрессионный кейс из ревью);
  `stakeState == exited` при `useful` → `exited`.
- Widget: карточка help-offered рендерит ожидаемую строку для каждого состояния.

**Acceptance P7:** хелпер всегда видит на своей карточке, ответил ли автор, и явную строку,
если запрос закрыт без ответа.

---

## 10. Фаза P8 — клиентские гейты берут правду с сервера

### P8.1 Сервер: новые поля в `beaconDisplayStatuses`

`packages/server/lib/domain/entity/beacon_display_status.dart` — добавить поля
`bool canCancel`, `bool canDelete`, `int everAcknowledgedCommitterCount`.

`BeaconDisplayCase.displayStatuses` — вычислять их **только для автора**
(`tier == coordination && viewerId == beacon.author.id`), иначе `canCancel = false`,
`canDelete = false`, `everAcknowledgedCommitterCount = 0`:

```dart
final everAck = await _commitmentQueryCase.everAcknowledgedUserIds(beaconId);
final isAuthor = viewerId == beacon.author.id;
final canCancel = isAuthor && beacon.status.isOpenFamily && everAck.isEmpty;
// Зеркалит BeaconCase.deleteById: черновик удаляется безусловно (hard delete идёт
// ДО stake-гейта), всё остальное — по ever-acknowledged.
final canDelete = isAuthor &&
    (beacon.status == BeaconStatus.draft || everAck.isEmpty);
```

> Формула обязана совпадать с сервером **буквально**. Ранняя редакция плана содержала
> `status != draft && …`, из-за чего клиент запретил бы удаление собственных черновиков —
> прямое противоречие с `deleteById`. Если по ходу работы сервер изменится, эта формула
> меняется тем же коммитом.

`custom_types.dart` → `gqlTypeBeaconDisplayStatus`: три новых поля
(`canCancel`, `canDelete` — `graphQLBoolean.nonNullable()`;
`everAcknowledgedCommitterCount` — `graphQLInt.nonNullable()`).
`beacon_display_gql_maps.dart` → добавить ключи в map.

### P8.2 Клиент

1. `packages/client/lib/data/gql/schema.graphql` — три поля в тип `v2_BeaconDisplayStatus`.
2. `packages/client/lib/features/beacon_view/data/gql/beacon_display_statuses.graphql` — выбрать
   новые поля.
3. `packages/client/lib/domain/entity/beacon_display_status_dto.dart` — поля + парсинг в
   `fromJson`, `beacon_display_repository.dart` — прокинуть.
4. `packages/client/lib/features/beacon/ui/util/beacon_lifecycle_ui.dart` — переписать:

```dart
bool beaconDeleteBlockedByCommitters(Beacon beacon, {bool? serverCanDelete}) =>
    serverCanDelete != null ? !serverCanDelete : <старое эвристическое правило>;

bool beaconAllowsCancel(Beacon beacon, {bool? serverCanCancel}) =>
    serverCanCancel ?? (beacon.status == BeaconStatus.open && beacon.helpOfferCount == 0);
```
Во всех 4 местах вызова (`beacon_view_app_bar_overflow.dart:475`, `my_work_cards.dart:394/566/719`)
передать значение из DTO, если оно доступно в этом дереве; если DTO там нет — оставить
эвристику (сервер всё равно авторитетен и вернёт ошибку).

5. `packages/client/lib/features/beacon_view/domain/beacon_status_menu.dart` — строка `cancelled`:
   использовать серверный `canCancel`, а причина запрета для автора — новая
   `BeaconStatusMenuDisabledReason.cancelHasCommitters` (добавить **в конец** enum) с l10n-строкой
   «Нельзя отменить: в запросе был участник — используйте «Закрыть»».

### P8.3 Предупреждение перед Close при неотвеченных офферах — **патч существующего sheet**

Нового диалога **не создавать**. Поток уже есть:
`packages/client/lib/features/beacon/ui/sheet/beacon_close_confirm_sheet.dart` — он принимает
`onOpenPeople`, показывает строку-«улику»
`l10n.beaconCloseSheetEvidenceUnansweredCount(summary.unansweredHelpOffersCount)` и кнопку
подтверждения. Требуется ровно три правки:

1. Счётчик `unansweredHelpOffersCount` приходит из
   `beacon_closure_readiness.dart` ← `beacon_view_state.unansweredHelpOffersCount`; после P6.5
   он уже исключает backup-офферы — отдельно здесь ничего не фильтровать, только **проверить**.
2. Когда `summary.unansweredHelpOffersCount > 0`, рядом со строкой-уликой показать действие
   «Сначала ответить», вызывающее существующий `onOpenPeople` (сейчас колбэк передаётся, но
   при неотвеченных офферах отдельной кнопки нет — добавить). Текст — существующий ключ, если
   найдётся подходящий; иначе новый `beaconCloseAnswerFirst`.
3. Текст кнопки подтверждения при `unansweredHelpOffersCount > 0` не менять, если он уже
   достаточно явный; новый ключ `beaconCloseAnyway` заводить **только** если существующего нет
   (проверить `grep beaconCloseSheet packages/client/l10n/app_en.arb`).

Новый ключ `beaconCloseUnansweredOffersWarning` **не заводить** — дублирует
`beaconCloseSheetEvidenceUnansweredCount`.

### P8.4 l10n P8

| Ключ | EN | RU | Условие |
|------|----|----|---------|
| `beaconStatusCancelHasCommitters` | "Can't cancel — someone committed; close instead" | «Нельзя отменить: в запросе был участник — используйте «Закрыть»» | новый |
| `beaconCloseAnswerFirst` | "Answer first" | «Сначала ответить» | только если в `.arb` нет подходящего существующего |

Важно: **не** добавлять `beaconCloseUnansweredOffersWarning` и `beaconCloseAnyway` вслепую —
см. P8.3.

### P8.5 Тесты P8

- Сервер: `beacon_display_case_test.dart` — `canCancel/canDelete` для автора и не-автора,
  при наличии/отсутствии `everAcknowledged`, и **отдельный кейс: черновик автора →
  `canDelete == true`** (регрессия из ревью). Кейса «материальная работа в комнате» быть
  не должно — гейт отменён (D11).
- Клиент: unit-тест `beacon_status_menu` — строка Cancel выключена с новой причиной;
  widget-тест диалога предупреждения.

**Acceptance P8:** клиент больше не «угадывает» доступность Cancel/Delete; автор получает
предупреждение о неотвеченных офферах перед закрытием.

---

## 11. Фаза P9 — issue #108: закрытие → Archive, честный Delete, CTA закрытия

**Тикет:** [#108 [P0][Regression] Closed requests Archive inconsistency](https://github.com/Intersubjective/tentura/issues/108)
(родитель #96, регрессия #74). Ставится **после** P3/P8, потому что три из пяти дефектов тикета —
следствия той же путаницы осей: «Delete молча ничего не делает» и «непонятно, закрылось ли».

### 11.0 Что уже верно и **не** переделывается

- `BeaconStatus.closed` = **6** — единственное каноническое значение; legacy `4` маппится в
  `closed` в `BeaconStatus.fromSmallint`. Второго «closed» в системе нет; требование тикета
  «one canonical lifecycle meaning» уже выполнено — **не вводить** новых статусов.
- Finished-запросы **не** уходят в Archive автоматически: Archive — это per-user флаг
  (`CONTEXT.md` §«Archived»), карточка остаётся в Active с CTA «Archive», пока пользователь не
  заархивирует. Тикет требует ровно этого (Required behavior: «Closed requests … appear in
  "my work" with "Archive" CTA button and "review closed" status»). Автоархив **не делать**.
- Истечение окна ревью уже автоматизировано: `TaskWorkerCase` вызывает
  `AttentionExpirySweepCase.runDue` не чаще раза в минуту
  (`packages/server/lib/domain/use_case/task_worker_case.dart`), плюс ленивая подчистка
  `EvaluationCase._ensureExpiredClosed` перед каждой evaluation-мутацией.

### 11.1 Шаг 1 — воспроизведение и диагностика (обязательно до правок)

Поднять локальный стек (скилл `local-debug`: `./scripts/dev-up.sh`, сервер, web-клиент, Caddy)
и пройти сценарий из тикета, фиксируя результат каждого пункта в журнале:

1. A создаёт запрос, B предлагает помощь, A принимает (committer появился).
2. A закрывает запрос → ожидается `reviewOpen` (Wrapping up).
3. Все обязательные ревьюеры завершают/пропускают отзывы.
4. A нажимает «Close now» → ожидается `closed` (6).
5. **Без перезагрузки** проверить: экран запроса и My Work показывают Closed + CTA Archive.
6. Проверить второй клиент/сессию — то же состояние.
7. Проверить `Delete Request` в overflow.

Зафиксировать в журнале по каждому пункту: `ok` / `сломано: <точное наблюдение>`.
Для проверки серверного состояния использовать SQL:
`SELECT id, status, status_changed_at FROM public.beacon WHERE id = '<B…>';`
и `SELECT * FROM public.beacon_review_window WHERE beacon_id = '<B…>';`

Дальше правки применяются **только к тем пунктам, которые действительно сломаны**; правки,
которые оказались не нужны, помечаются в журнале как «не требовалось» — но пункты 11.2, 11.3
и 11.6 выполняются **всегда**, независимо от результата диагностики.

### 11.2 Delete больше не молчит (выполняется всегда)

Корень: сервер бросает `EvaluationException(beaconNotClosable)` (после P3 — при
`everHadCommitter == true`), а клиент это либо не показывает, либо показывает как
generic-ошибку. Коды ошибок клиент не разбирает (§0.1), поэтому объяснение строится
на предвычисленном `canDelete` из P8.1.

1. Клиент, `packages/client/lib/features/beacon/ui/dialog/beacon_delete_dialog.dart`.
   **Диалог и ключи уже существуют** (`beaconDeleteBlockedTitle` = "Cannot delete",
   `beaconDeleteBlockedBody` = "This request had acknowledged helpers. Archive it from My desk
   instead.", параметр `hasEverHadCommitter` уже передаётся из всех 4 мест). Тексты **не
   переписывать**, новых ключей для заголовка/тела **не заводить**. Не хватает ровно одного:
   в заблокированной ветке нет действия — добавить кнопку архивации с существующим ключом
   `myWorkArchive`, выполняющую ту же операцию, что CTA Archive на карточке My Work
   (найти обработчик архивации в `my_work_cards.dart` и переиспользовать репозиторный вызов).
2. Источник флага — серверный `canDelete` из P8.1 (а не эвристика
   `beaconDeleteBlockedByCommitters`). Во всех 4 местах вызова передавать серверное значение;
   там, где DTO недоступен, — вызывать мутацию и корректно показывать ошибку (п. 3).
3. Обработка ошибки: в кубите, вызывающем `BeaconDeleteById`, ловить исключение,
   выходить из loading-состояния и показывать `SnackBar` с текстом
   `beaconDeleteFailedRetry` и действием «Повторить». Никаких «тихих» catch-ов
   (`catch (_) {}`) на этом пути не оставлять.

### 11.3 CTA «Закрыть запрос», когда отзывы завершены (выполняется всегда)

Требование тикета: CTA должна быть видна **и на карточке My Work, и на экране запроса**,
когда все обязательные ревьюеры закончили.

Источник истины — существующее поле `canCloseNow` в
`reviewWindowStatus` (`packages/server/lib/domain/entity/gql_public/review_window_status_result.dart`,
GQL-тип в `custom_types.dart:640`, клиентский запрос
`packages/client/lib/features/evaluation/data/gql/review_window_status.graphql`).

Проблема: My Work тянет карточки одним Hasura-запросом (`my_work_fetch.graphql`) и статуса окна
ревью не знает. Решение — **батч-запрос**, а не запрос на карточку:

1. Сервер: добавить V2-запрос
   `reviewWindowStatuses(beaconIds: [String!]!): [v2_ReviewWindowStatusResult!]!`
   рядом с существующим `reviewWindowStatus` (файл
   `packages/server/lib/api/controllers/graphql/query/…` — найти, где зарегистрирован
   одиночный запрос, и повторить структуру). Реализация: цикл по id с переиспользованием
   существующего метода `EvaluationCase.reviewWindowStatus`, с пропуском тех, где нет доступа.
2. `packages/client/lib/data/gql/schema.graphql` — добавить запрос.
3. Новый `packages/client/lib/features/my_work/data/gql/my_work_review_windows.graphql`
   (операция `MyWorkReviewWindows`), регистрация имени в `_tenturaDirectOperationNames`.
4. Оркестрация — **в `MyWorkCase`, не в кубите**: кубит уже ходит только в case, новый
   репозиторный вызов из `MyWorkCubit` нарушит правило «cubit с ≥2 репозиториями требует Case»
   (`cubit_requires_use_case_for_multi_repos`). Метод `loadReviewWindows(beaconIds)` живёт
   в `MyWorkCase`; кубит после `loadDeskInit` вызывает его **только** для карточек в
   `reviewOpen` (`vm.beacon.status == BeaconStatus.reviewOpen`); при пустом списке запрос не слать.
5. `MyWorkCardViewModel`: добавить поле `bool showCloseNowCta` (default `false`), заполнять из
   ответа (`canCloseNow == true` и пользователь — автор).
6. UI: в `my_work_cards.dart` для `authoredActive` с `showCloseNowCta == true` показать
   первичную кнопку `beaconCloseNowCta` («Закрыть запрос»), рядом с существующей review-CTA.
   **На экране запроса ничего добавлять не нужно:** `beacon_hud_author_action.dart`
   (`_reviewOpenAuthorAction`, ~строка 123) уже возвращает действие закрытия при
   `canCloseNow`. Это пункт **verify-only** — прогнать сценарий вручную и, если действие
   не появляется, чинить существующую ветку, а не добавлять параллельную.
7. После успешного `closeNow` — инвалидация: кубит запроса и `MyWorkCubit` должны перечитать
   данные (у `MyWorkCubit` уже есть подписка на изменения beacon с debounce —
   `_onDeskRelevantInvalidation`; убедиться в диагностике 11.1, что событие доходит; если нет —
   после мутации звать `fetch(showLoading: false)` напрямую из места вызова).

### 11.4 Идемпотентность и атомарность (по результатам диагностики)

Проверить и, если нужно, починить:

1. `EvaluationCase.closeNow` и `beaconClose` уже выполняются внутри
   `runInBeaconStateTransaction` (блокировка строки beacon) — повторный вызов на уже закрытом
   запросе должен давать `beaconNotClosable`, а **не** дублировать транзицию. Добавить тест.
2. `ReviewFinalizationPort.closeAndFinalize` возвращает `bool didClose` — убедиться, что при
   повторном вызове возвращается `false` и не пишется второй lifecycle-event. Добавить тест.
3. Клиент: кнопки Close / Close now должны блокироваться на время запроса (guard на
   повторный тап) и разблокироваться в `finally`. Проверить/добавить.

### 11.5 Статус «review closed» на карточке (по результатам диагностики)

`derive_my_work_cards.dart` уже строит `authoredFinished` / `helpOfferedFinished` c
`showArchiveAffordance: true` для `status.isFinished`. Если диагностика 11.1 покажет, что
карточка после закрытия остаётся в прежнем виде — причина в неперечитанных данных (см. 11.3 п. 7),
а не в деривации; **деривацию не переписывать**, чинить обновление.

### 11.6 E2E-регрессионный тест (выполняется всегда)

Создать `packages/client/integration_test/request_lifecycle_closed_to_archive_test.dart`
по образцу существующего `request_lifecycle_close_review_test.dart` и хелперов из
`packages/client/integration_test/support/`.

Сценарий (один тест, последовательно):
1. автор создаёт запрос, второй пользователь предлагает помощь, автор принимает;
2. автор закрывает → на экране статус Wrapping up;
3. оба участника пропускают отзывы (skip);
4. автор видит CTA «Закрыть запрос» **на карточке My Work** и нажимает её;
5. без перезагрузки: карточка показывает Closed + CTA Archive;
6. нажатие Archive убирает карточку из Active и показывает её в фильтре Archived;
7. попытка Delete на закрытом запросе показывает объяснение (11.2), а не пустой результат.

Запуск: `./scripts/run_client_integration_web_local.sh
integration_test/request_lifecycle_closed_to_archive_test.dart`
(нужен поднятый локальный стек; см. скилл `local-debug` и
`docs/local-integration-tests.md`).

### 11.7 l10n P9

| Ключ | EN | RU | Условие |
|------|----|----|---------|
| `beaconDeleteFailedRetry` | "Couldn't delete the request" | «Не удалось удалить запрос» | новый |
| `beaconCloseNowCta` | "Close request" | «Закрыть запрос» | новый |

`beaconDeleteBlockedTitle`, `beaconDeleteBlockedBody`, `myWorkArchive` — **уже существуют**,
переиспользовать как есть.

### 11.8 Тесты P9

- Сервер: `evaluation_case_close_idempotency_test.dart` — повторный `closeNow`/`beaconClose`
  не создаёт вторую транзицию и возвращает ошибку; `closeAndFinalize` повторно → `false`.
- Сервер: тест батч-запроса `reviewWindowStatuses` (доступ, пустой список, смешанные статусы).
- Клиент: unit — `showCloseNowCta` выставляется только автору и только при `canCloseNow`;
  widget — карточка Closed показывает CTA Archive; диалог Delete на закрытом запросе показывает
  объяснение.
- E2E: файл из 11.6.

**Acceptance P9 (совпадает с acceptance тикета):**
закрытие обновляет экран запроса и My Work без перезагрузки; на карточке появляется CTA Archive;
CTA «Закрыть запрос» видна автору на карточке и на экране, когда все отзывы завершены;
второй клиент показывает то же состояние; повторное закрытие не ломает состояние;
неуспешная транзиция выходит из loading и показывает ошибку с повтором;
e2e-тест active → review → closed → Archive зелёный.

---

## 12. Фаза P10 — документация, терминология, финальная проверка

### 12.1 Правки документов

| Файл | Что изменить |
|------|--------------|
| `CONTEXT.md` §«Beacon lifecycle» | **Committer**: определить через append-only факты (`everAcknowledged` с грейсом 24 ч и правилом «грейс закрывается любым промежуточным событием»), добавить понятие **Former committer**. **Cancel**: «offered only when the request never had an acknowledged committer». **Deleted**: «ever had an acknowledged committer» (формулировка не расширяется — D11). **Wrapping up**: открывается по `everHadCommitter`. **Close now**: required reviewers = author + current committers; former committers и forwarders не блокируют. **Reopen**: не более одного раза. |
| `CONTEXT.md` (новый подраздел «Commitment facts») | Кратко: таблица `beacon_commitment_event`, три оси A/B/C, правило «факты только добавляются», проекция `stake_state` как display-only, **инвариант допуска** («в комнату пускают только вместе с признанием»; стюарды — явное исключение). Ссылка на этот план. |
| `docs/Tentura_current_status_quo.md` §8.2 | Переписать «Overcommit = coordination, not gatekeeping»: автор принимает/отклоняет **предложение помощи** (не человека); отклонение требует причины и приватно; при «enough help» новые предложения не блокируются, но подаются как **backup**. |
| `docs/Tentura_current_status_quo.md` §9 | Добавить: в окно ревью попадают и former committers; ушедший не блокирует досрочное закрытие. |
| `docs/features/beacon_room.md` §«Admission» | Удалить исключение про auto-admit; записать: допуск всегда явный; оффер от прямого адресата автора помечается и поднимается в списке. Добавить абзац про backup-офферы и про «Remove from chat ≠ End participation». |
| `docs/beacon-evaluation-principles.md` | Добавить пункт про роль former committer и про то, что выход из работы не стирает участие; грейс-период 24 ч. |
| `docs/before-response-terminal-tombstone.md` | Скорректировать §«Withdraw (`beaconWithdraw`)» под запрет withdraw в `reviewOpen` (ветка остаётся только для блокировок). |
| `docs/watching-mechanism.md` | Уточнить, что Watching после withdraw ставится системой (не выбором пользователя) — переформулировать «Into Watching» без изменения поведения. |
| `CONTEXT.md` §«Archived» / «Finished card» | Явно записать: закрытие **не** архивирует автоматически; закрытая карточка остаётся в Active со статус-индикатором «review closed» и CTA **Archive**, пока пользователь не заархивирует её сам (формулировка требования — #108). |
| `docs/README.md` | Добавить ссылку на этот план в индекс планов, если там есть такой раздел. |

### 12.2 Финальная проверка

```bash
cd packages/tentura_lints && dart test
cd packages/server && dart test                        # часть тестов требует Postgres;
cd packages/server && dart test -x pg                  # без БД — этот вариант должен быть зелёным
./scripts/check-custom-lints.sh packages/server
./scripts/check-custom-lints.sh packages/client
cd packages/client && flutter test
bash scripts/check-user-facing-terminology.sh
bash scripts/check-doc-drift.sh
```

Плюс ручная проверка на локальном стеке (скилл `local-debug`):
1. поднять стек (`./scripts/dev-up.sh`), применить миграции, применить метаданные Hasura;
2. сценарий: A создаёт запрос → B предлагает помощь → A принимает → B withdraw через API →
   у A **нет** Cancel и Delete → A закрывает → открывается Wrapping up → B присутствует в составе
   ревью как former committer и **не** блокирует Close now;
3. сценарий: A ставит «enough help» → C (получатель форварда) видит primary Forward и вторичное
   «предложить как запасной»; после оффера у A не появляется статус «офферы ждут ответа»;
4. сценарий: A удаляет B из чата → B по-прежнему числится участником, у A есть отдельное
   «Завершить участие».

### 12.3 Версионирование

Изменения пользовательски видимые → поднять минорную версию в
`packages/client/pubspec.yaml`.

**`kDefaultMinClientVersion` в `packages/server/lib/env.dart` поднять обязательно** — в том же
релизе, что P1–P3+P3.11+P8.1. Причина: `beaconClose` сверяет клиентский
`expectedRequiresReviewWindow` с серверным расчётом и бросает `closeBranchConflict` при
расхождении. После P3.5 старый клиент (считающий committer'ов по активным офферам) будет
систематически ошибаться на запросах, где участник вышел или его участие завершено, — то есть
**закрытие запроса сломается у всех, кто не обновился**. Ослаблять серверную проверку нельзя:
она защищает автора от неожиданной ветки закрытия.

Порядок: сначала выкатывается сервер+клиент, затем поднимается `kDefaultMinClientVersion`
до версии из `packages/client/pubspec.yaml` этого релиза (см. `.cursor/rules/versioning.mdc`).

Побочный эффект, который **не** требует отдельных действий: до обновления у старых клиентов
останется прежняя ACT-подсказка при `enoughHelp` (`offerHelp` вместо `forward`) — деривация
фазы есть и на клиенте (`derive_beacon_coordination_phase.dart`, deprecated-фолбэк).

---

## 13. Порядок, зависимости и оценка

| Фаза | Зависит от | Суть | Отдельный merge |
|------|-----------|------|-----------------|
| P1 | — | таблица, колонки (`offer_kind`, `stake_state`, `review_reopen_count`), предикаты, бэкфилл, Hasura | нет — только в составе «ядра» |
| P2 | P1 | запись фактов везде + проекция | нет — только в составе «ядра» |
| P3 (вкл. P3.11) | P2 | гейты, роль `formerCommitter`, инвариант допуска, клиентский контракт Close | нет — только в составе «ядра» |
| P8.1 | P3 | серверные `canCancel` / `canDelete` / `everAcknowledgedCommitterCount` | нет — только в составе «ядра» (P3.11 п. 4 от него зависит) |
| P4 | ядро | `releaseCommitment`, квитанция `commitmentReleased` | да |
| P5 | P2 | удаление auto-admit | да |
| P6 | P3 (фильтр `offerKind` уже в P3.5) | enough help A+B | да |
| P7 | P3.11 (`CommitmentStakeState` на клиенте), P1 (Hasura) | строка состояния в My Work | да |
| P8 (остальное, кроме P8.1) | P3 | клиентские гейты, статус-меню, патч close sheet | да |
| P9 | P3, P8 | issue #108: Archive/Delete/Close-CTA + e2e | да |
| P10 | все | документация и verify | да |

**Строгая последовательность исполнения:** P1 → P2 → P3 → P4 → P5 → P6 → P7 → P8 → P9 → P10.
Не начинать следующую фазу, пока verify предыдущей не зелёный.

**Границы релиза («ядро» = один PR, один выкат):**
`P1 + P2 + P3 (включая P3.11) + P8.1` + подъём `kDefaultMinClientVersion` (§12.3).

Почему именно так:
- P2 без P3 делает Delete строже, чем задумано (предупреждение в начале P2);
- P3.5 без P3.11 ломает Close (`closeBranchConflict`) на любом запросе, где участник вышел;
- P3.11 п. 4 читает `everAcknowledgedCommitterCount`, который вводит P8.1;
- старые клиенты после выката считают committer'ов по-старому → нужен version gate.

Дальше можно резать по фазам: P4 → P5 → P6 → P7 → P8 (остальное) → P9 → P10.
P7 **нельзя** делать раньше P3.11 (там вводится клиентский `CommitmentStakeState`)
и раньше P1.1 шаг 13 (без него `stake_state` не виден через Hasura и запрос упадёт).

## 14. Открытые вопросы (заполняет исполнитель)

Сюда записывать всё, что потребовало решения не из плана: описание, найденное место, принятое
временное решение. Не менять из-за них объём фаз.

---

## 15. Приложение: что изменили ревизии 2 и 3 (adversarial review)

Таблицы нужны, чтобы исполнитель не «чинил» уже исправленное и понимал, почему решения такие.

### 15.1 Ревизия 3 (второй раунд ревью)

| # | Замечание | Статус | Где закрыто |
|---|-----------|--------|-------------|
| C1 | После P3 сервер считает `requiresReviewWindow` по `everHadCommitter`, клиент — по активным офферам → `closeBranchConflict` на каждом Close с «бывшим» участником | **принято, блокер** | Новый **P3.11** целиком; §13 (P8.1 входит в ядро); §12.3 (подъём `MIN_CLIENT`) |
| C2 | `formerCommitter` ломает 3 exhaustive-switch и молча не получает рёбер видимости | **принято, блокер** | P3.3 переписан: `evaluation_reason_tags` (2 функции), `evaluation_summary_rules`, `buildEvaluationVisibility`, DI через `CommitmentRepositoryPort`, тесты |
| C3 | После `releaseCommitment` клиент по-прежнему считает человека committer'ом (`helpOfferIsCommitter` смотрит `coordinationResponse`) | **принято, блокер** | P3.11 п. 3 (одна строка + протяжка `stakeState` в `TimelineHelpOffer`) |
| H1 | `acknowledgementSoftened` становится почти недостижимым после P3.9 | принято | §2.1 — вид помечен legacy/бэкфилл |
| H2 | Повторный `acknowledged` после release не зафиксирован продуктово | принято | **D13** + оговорка в P3.9 + тест 16 в P3.12 |
| H3 | HUD `closeNow` уже реализован (`_reviewOpenAuthorAction`) | принято | P9.3 п. 6 → verify-only |
| H4 | Клиентская оркестрация: release и batch review-windows должны идти через Case | принято | P4.3 п. 4 (`BeaconViewCase`), P9.3 п. 4 (`MyWorkCase`) |
| H5 | В P8.5 остался тест на отменённый гейт «работа в комнате» | принято | P8.5 переписан (+ кейс на `canDelete` для черновика) |
| H6 | `authorResponseType` не мёртвый — используется в `beacon_hud_metadata_composer.dart:83` | **принято, §1.11 исправлен** | §1.11; в P7 удаляются только `slot1ResponseType` и l10n-ключ |
| M1 | `record` должен вставлять через `customInsert` без `seq` | принято | P1.4 (ссылка на `insertHelpOfferAdmissionEvent:15`) |
| M2 | Бэкфилл без `offered` оставляет дырявый журнал | принято | Новый шаг **8a** (выполняется первым, чтобы `seq` шли естественно) |
| M3 | `BeaconRepositoryPort` в `CommitmentQueryCase` лишний | принято | P1.5 — зависимости сокращены до двух |
| M7 | После C1 старые клиенты ломают Close → «MIN_CLIENT не нужен» больше не верно | принято | §12.3 — подъём `kDefaultMinClientVersion` обязателен |
| M4 | `my_work_cards.dart` шлёт `helpOfferCount > 0` | принято | P3.11 п. 4 |
| M5, M6, LOW | подтверждения корректности | без изменений | — |

### 15.2 Ревизия 2 (первый раунд ревью)

| # | Замечание ревью | Статус | Где закрыто |
|---|-----------------|--------|-------------|
| 1 | После `releaseCommitment` UI не видит «участие завершено»; кнопка висит вечно | принято | §2.5 проекция `stake_state`, P1.1 (7a–7c, 11a), P4.1b → перенесено в P3.11 (рев. 3), P4.3 п. 5 |
| 2 | P7 обещает participation-ended, но модели нет; `offer_kind` в P7 — мёртвый scope | принято | P7.1 переписан на `stake_state`; `offer_kind` из P7 убран |
| 3 | `canDelete` для draft противоречит `deleteById` | принято | P8.1 — формула зеркалит сервер (`draft → isAuthor`) |
| 4 | «Material room work» — новый продуктовый гейт вне D1–D10 и CONTEXT | принято, решение владельца: **гейта не будет** | D11, §2.4 заменён инвариантом допуска, P3.11; `hasMaterialRoomWork` удалён из P1.5/P3.2/P8.1 |
| 5 | P2 без P3 меняет поведение Delete | принято с уточнением | Предупреждение в начале P2. Уточнение: **Cancel не меняется** (withdraw по-прежнему снимает активность оффера), меняется только Delete — становится строже |
| 6 | P8.3 дублирует существующий `beacon_close_confirm_sheet` | принято | P8.3 переписан как патч существующего sheet; лишние ключи отменены |
| 7 | P9.2 описывает greenfield поверх существующего диалога и ключей | принято | P9.2 п. 1 переписан; ключ архивации — `myWorkArchive` |
| 8 | `unansweredAtClose` vs backup-офферы | принято | P3.5 (`offerKind == 0`), P6.2, P6.5 (клиентский счётчик), P8.3 |
| 9 | §13 «P7 independent» противоречит порядку и Hasura-метаданным | принято | Hasura перенесена в P1.1 шаг 13; §13 переписан с явными границами релиза |
| 10 | Дубли `acknowledged` при повторном ответе | принято | Общее правило записи в начале P2 |
| 11 | Клиентские People/My Work читают coordination-строку | принято | `stake_state` (§2.5) + P4.3 п. 5 + P7.1 |
| 12 | Базлайн линтов 115 → на самом деле 112 | принято | §0.3 |
| 13 | Бэкфилл `action IN (0,1)` делает исторические auto-admit вечными committer'ами | принято как **осознанное** решение | Продуктовая заметка в P1.1 после шага 11a |
| 14 | Грейс после `acknowledgementSoftened` работает как ластик | принято | §2.2 — грейс закрывается любым промежуточным событием; тесты P1.6 №12–13 |
| 15 | Семантика исключений; клиент не парсит коды | принято | §0.1 (новое правило про коды), P4.1 п. 4 (`commitmentNotAcknowledged`), P4.1a (отдельная квитанция `commitmentReleased` вместо `offerRemoved`) |
| 16 | Drift-таблица без `uniqueKeys` | принято | P1.2 |
| 17 | P9 слабо связан с ядром и раздувает релиз | решение владельца: **оставить в этом плане** | §13 — P9 мержится отдельным PR после ядра |
| 18 | MIN_CLIENT и ACT-деривация на старых клиентах | принято | §12.3 — явная оговорка |
| — | `ON DELETE CASCADE`, redundant index, отсутствие Hasura-трекинга событий, `formerCommitter(3)` без CHECK, безопасность P5 до P3 | подтверждено ревью как ок | без изменений |
