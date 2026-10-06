# План запроса («либретто», issue #220): дизайн и шаги реализации

Статус: rev 2, 2026-10-05. Rev 1 переработан по трём критикам и верификации. Основа: `docs/plans/baton-who-takes-it-plan.md`. Макеты и решения владельца лежат в `/mnt/project-files/scenarios/plan-mockups.md`; unit X0 копирует их в репозиторий (§6.2).

> **Ветка строится от удалённого `main`, а не от локального checkout.** Локальные HEAD и `origin/main` стоят на `f0e27cb`. Настоящий remote main уже `c93331f` (проверено `git ls-remote origin main`), он на 28 коммитов впереди. В этих коммитах приземлились:
> - baton целиком: B3..B7, C1..C5, V, `kBatonEnabled = true`, marker `batonTaken = 12`;
> - HUD-переделка #223 (`3ef6b912`): `beacon_hud_pinned_block.dart`, `beacon_request_modes.dart`, миграция `m0220`.
>
> Следствия:
> - **Первые свободные значения:** миграция `m0223`, semantic marker `13`, `BeaconExceptionCode` `1330` (коды позиционные, `1300 + index`, `exception_codes.dart:73-115`), `BeaconActivityEventTypeBits` `21` (на main последний `factRemoved = 20`), `BeaconRoomSystemMessageKind` `5` (на main последний `convertedToRequest = 4`, `consts/beacon_hierarchy_consts.dart:24-29`).
> - **Старт:** ни один unit не ждёт HUD или baton. Все начинают с `git fetch && git switch -c feature/plan-220-<unit> origin/main`.
> - **Номера** сверяются в начале и **при merge** каждого unit: `ls packages/server/lib/data/database/migration/`, consts, enum кодов. На main параллельно приземляются другие агенты. Номер получает заранее только S1 (`m0223`). Остальные миграции названы по смыслу (`m02xx_plan_scope`, `m02yy_plan_quote`), номер присваивается при rebase. В тестах используется `migrationsForTesting.last.version` (`AGENTS.md:144`).
> - **Ссылки на строки** взяты из локального `f0e27cb`. Для файлов, изменённых на main, их нужно перепривязать в начале unit:
>   - `98d613c` (baton C3): `room_message_tile.dart`, `room_cubit.dart`, `basic_chat_body.dart`;
>   - `3ef6b91` (HUD): `beacon_view_screen.dart`, `beacon_now_surface.dart`, `beacon_view_cubit.dart`, `beacon_hud_metadata_composer.dart`.

---

> **Поправка владельца (Вадим, 5 окт), отменяет авто-назначение из решения 9:** шаг можно назначить только на допущенного в запрос. При копировании запроса назначения в плане полностью сбрасываются: нет «было: X», нет кнопки «позвать», нет автоназначения при допуске (`former_assignee_id`, `former_reason` и хуки допуска из K2 не нужны).

> **Обновлено 5 окт по main `1f1e094`:** `m0221` занят (visibility-cache trylock), поэтому первая миграция плана была `m0222`. **Обновлено 6 окт:** main занял `m0222` (mutual visibility memo, #232), план переехал на `m0223` (схема) и `m0224` (scope + sweep marks). Markers (13+) и коды исключений (1330+) не изменились. Номера перепроверять при merge.

## 1. Цель и рамки

### 1.1 Что это

У каждого запроса (Request, `beacon.kind = 0`) есть один общий **план**: упорядоченные **шаги**. У шага ровно один исполнитель или «нет исполнителя». Начало и конец необязательны, есть описание и отметка «выполнено». Каждый участник за 2 секунды видит свой текущий шаг (строка ВЫ/ТЫ, подпись решает Q10) и следующий (ДАЛЬШЕ). Строка NOW переключается на шаг плана, когда наступает время его начала.

### 1.2 Что входит в v1

| Блок | Состав |
|---|---|
| Хранение | Шаги лежат в `coordination_item` с новым kind `6`. Заголовок плана, ревизии и ledger подтверждений хранятся в новых таблицах. |
| Правка | Черновик на клиенте, сохранение одной ревизией, слияние по шагам с base seq. Конфликт возникает только на одном и том же шаге. История с возвратом. |
| Отметки | Любой допущенный участник ставит и снимает галку, рядом подпись «отметка: X». Галки не входят в ревизии. Снятая отметка зачёркивается в чате. |
| «Понял» | Изменение вашего шага висит в ВЫ (или ПО ПЛАНУ) и в My Work до «Понял». Ru-копия кнопки по умолчанию «Понятно» (Q11). Автор видит, кто подтвердил, а кто нет. |
| «Не успеваю» | Три варианта: перенести, передать другому (прямое переназначение), написать в обсуждении. Каждый попадает в историю. |
| HUD | ВЫ / ПО ПЛАНУ / ДАЛЬШЕ в pinned-блоке main. NOW с источником «по плану · шаг n/N». |
| Вкладка Plan | Список с линией «сейчас», фильтр [Все ▾] (люди) и [Мои], карточка шага, редактор, история, пустое состояние. Матрица «люди × время», когда панели хватает ширины. |
| My Work | Субкарточки шагов в блоке обязательств, членство `planAssignee`, участниковая карточка для не-авторов. |
| Уведомления | Напоминание за 15 мин, наступление, «ваш ход», изменение с «Понял», просрочка (один раз), автору +30 мин, шаг без исполнителя, «Не успеваю», ambient-правки и отметки. Push и email без абсолютного времени (§4.6). |
| Push-кнопки | «Готово» / «Понятно» в web push в Chromium. В остальных браузерах тап открывает шаг. |
| Чат | Системные строки (`system_message_kind = 5`): ревизия, автоназначение, снятие исполнителя при уходе, склеенные отметки, «Не успеваю», «План скопирован». Цитата шага в сообщении. |
| Копирование | Расширение существующего fork «Создать на основе этого запроса»: сдвиг времени по якорю, «было: X», автоназначение при допуске. |
| Тёмный запуск | Серверный env-флаг `PLAN_ENABLED` и клиентский `kPlanEnabled` (§2, P15). |

### 1.3 Явно вне v1

- CRDT и живое совместное редактирование; черновики на сервере.
- Настраиваемое время напоминания: оно фиксировано, 15 мин (D7).
- Зависимости шагов, кроме порядка; подшаги; повторяющиеся планы; библиотека шаблонов.
- План в Posts (`kind = 1`). План до публикации, кроме draft после fork.
- Push-кнопки в нативных Android/iOS (CI собирает только web, `pipeline.yml:386,400`), в Safari/iOS PWA и в Firefox. Там fallback: тап открывает шаг.
- Офлайн-очередь действий.
- Передача через baton («Кто возьмётся?» для шага).
- Часовой пояс запроса и показ зоны автора. Issue #112 отложил `author_timezone`, данных для сравнения зон нет. Абсолютное время в push и email тоже вне v1 (§4.6).
- Подавление напоминания, если человек сейчас в запросе (Q9). Нет присутствия по запросу.
- Обход тихих часов для plan-push (Q5).
- Отдельный экран «Новый запрос из копии» с суффиксом «(копия)» (Q12).
- Удаление legacy-строк kind=1: отдельный unit X2 после аудита, v1 он не блокирует.

---

## 2. Решения

Источники: **В** = владелец (макет, «Решено», 4 окт); **К** = исправление по проверке кода и критике; **П** = default этого плана, его можно переиграть.

| # | Ист. | Решение |
|---|---|---|
| D1 | В | Шаги хранятся в `coordination_item`. Элементы координации убраны из UI, а фактически и из API: мутаций нет, `lib/domain/use_case/coordination_item/` удалён. Пишем **новый код** (`BeaconPlanRepository` / `BeaconPlanCase`). Legacy `CoordinationItemRepository.create/updateStatus` не используем: `_emitStatusRoomEvent` (`coordination_item_repository.dart:230-289`) и зеркало в `current_line` (`:536-549`) противоречат макету. |
| D2 | В | Галку ставит и снимает любой участник с правом координации. Это `ensureCanCoordinateOnBeacon`: автор, steward или допущенный (`coordination_room_access.dart:6-24`). Показываем «отметка: X». |
| D3 | В | Изменение вашего шага висит до «Понял». Если ВЫ занята системной строкой, изменение уходит в ПО ПЛАНУ (§5.2). Автор видит, кто подтвердил. |
| D4 | В | Свои ревизии: черновик на клиенте, слияние по шагам, конфликт только если двое правили один шаг. Без CRDT. |
| D5 | В | «Не успеваю» предлагает три варианта: перенести, передать другому, написать в обсуждении. Каждый оставляет запись в истории. Вариант «обсуждение» фиксируется отправкой сообщения с цитатой шага (§4.4). |
| D6 | В | Матрица «люди × время» входит в v1. Показывается, когда ширина панели Plan ≥ 600 (§5.4). |
| D7 | В | Напоминание за 15 мин до начала, фиксированное. |
| D8 | В | Кнопки «Готово» / «Понятно» прямо в push. |
| D9 | В | Копия запроса копирует план. Время сдвигается, галки сбрасываются, исполнители становятся «было: X». После допуска X шаг назначается на него автоматически, X подтверждает «Понял». |
| D10 | В | Системные строки в чате пишем для правки, восстановления, автоназначения, снятия исполнителя при уходе, склеенных отметок, «Не успеваю» (перенос / передача) и копии. Не пишем для наступления времени, напоминаний и «Понял». Для «Не успеваю → обсуждение» строкой служит само сообщение человека с цитатой. |
| D11 | В | My Work: субкарточки шагов в существующем блоке обязательств. |
| D12 | В (4 окт) | **For You никогда не несёт то, что человек обязан сделать.** Шаг скоро, шаг начался, шаг просрочен, ваш шаг изменён, ваш ход, автоназначение: всё это идёт только в YOU / My Work / NOW / push. В For You попадают только «План правили, вас не касается» и «кто-то отметил шаг». Маршрутизация в §4.7. |
| K1 | К | Копирование запроса **существует**: `BeaconCase.fork` (`beacon_case.dart:776-842`), мутация `beaconFork` (`mutation_beacon.dart:149-159`), пункт «Создать на основе этого запроса» (`app_ru.arb:5564`) в меню запроса и на 4 типах карточек My Work (`my_work_cards.dart:581-588, 659-666, 870-877, 948-955`). Расширяем fork: он создаёт DRAFT и открывает `BeaconCreateRoute(draftId)`. Отдельный экран — вопрос Q12. |
| K2 | К | Шаги и «было: X» копирует только автор источника или его допущенный участник / steward. Fork открыт любому, кто проходит `canReadContent` (`beacon_case.dart:783-787`), а ADR 0004 запрещает копировать участников (`docs/adr/0004-beacon-lineage-fork.md:20`). ADR дополняется. |
| K3 | К | YOU не строится на `nextMoveText`: у колонки нет писателя (`updateParticipantNextMoveFields` без вызовов, `beacon_room_repository.dart:823-839`). План расширяет чистую лестницу `BeaconYouSituationInput` (`domain/coordination/beacon_you_situation.dart:8-165`). `next_move_*` в v1 не трогаем. |
| K4 | К | У фактов нет слияния, там CAS на весь документ (`beacon_fact_card_repository.dart:576`). Слияние по шагам пишем заново как чистую функцию в `tentura_root`. Два бага фактов не копируем: фиксированный base в истории (`fact_history_cubit.dart:25-46`) и base, взятый при отправке (`beacon_view_cubit.dart:1063-1069`). |
| K5 | К | Строки плана в чате используют новые markers `13..16`, механизм linked-item не годится: он даёт одну строку на элемент без diff. Каждый marker обязан попасть в `_previewKindForSemanticMarker`, иначе `StateError` (`coordination_item_repository.dart:1689-1704`). Маппинг на существующие preview kinds `2`/`7` обязателен. Новый `ThreadMessagePreviewKind` не добавляем: старый клиент бросает на неизвестном (`request_thread_model.dart:16-18`). |
| K6 | К | Lifecycle guard блокирует только статусы `1, 2, 6` (`m0193.dart:1195`), `reviewOpen = 5` пропускается. План редактируется и отмечается в open family и `reviewOpen` (`BeaconStatus.allowsCoordination`, `beacon_status.dart:48`). После close / cancel / delete он read-only. |
| K7 | К | Строки плана пишутся с **`system_message_kind = 5` (`plan`) и `author_id = actor`**, тип строки задаёт semantic marker 13..16. Вариант «`author_id = NULL`, kind NULL» невозможен из-за `beacon_room_message_author_or_system_ck CHECK (author_id IS NOT NULL OR system_message_kind IS NOT NULL)` (`m0193.dart:5315`). При kind ≠ NULL строка обходит lifecycle guard (`m0193.dart:1182`) и переживает стирание: удаляются только строки с kind NULL (`user_erasure_repository.dart:150-160`), FK автора `SET NULL` (`m0193.dart:7623`), сервер отдаёт NULL-автора как `''` (`beacon_room_repository.dart:509`). Побочные эффекты принимаем: строки не двигают `beacon.last_activity_at` (`m0209.dart:63`), не попадают в превью последнего сообщения My Work (`m0215.dart:31`), не получают receipt (`room_message_receipt.dart:36`). |
| K8 | К | NOW не пишется планировщиком и не идёт через `updateRoomNowLine`: тот рассылает `coordinationChanged` всей комнате и режет до 60 символов (`beacon_room_case.dart:698-757`). Эффективный NOW вычисляет одна чистая функция в `tentura_root`. Время ручной записи = `beacon_room_state.updated_at`: он пишется только вместе с `current_line` (`beacon_room_repository.dart:1210`; второй писатель `coordination_item_repository.dart:541` мёртвый) и уже отдаётся клиенту (`BeaconRoomStateGet.updatedAt`). Новой колонки нет. Sweep только толкает realtime и уведомляет исполнителя. |
| K9 | К | «Понял» противоречит `docs/features/request-attention.md` §5 («There is no bare "Done"», `:126-128`). §5 меняется по change control §11 **до** N1/N3: unit X0 и одобрение Q8. Новое правило: сохранённое подтверждение, которое видит ждущая сторона, есть доменный акт. Строка предлагает «Понял» и «Не успеваю». |
| K10 | К | Отметка шага не исполнителем закрывает его обязательство. По §5 «Nothing disappears unexplained» (`request-attention.md:137-139`) исполнитель получает `obligationEnded`. У этого события сейчас нет producer. Категория у него **unblocksMe** (`attention_policy.dart:128`), не asksOfMe. В `updates-event-contract.json` добавляется запись producer. |
| K11 | К | Без доработки For You протекает. Steward или адресат Post без активного help offer не входит в scope (`m0213.dart:7-24`), и его необязательные plan-receipts уходят в For You (`attention_dismissible_sql.dart:31-56`). Добавляем в scope ветку `planAssignee` и фильтр типов (§4.7). |
| K12 | К | Push-кнопок нет нигде. FCM шлёт только data (`fcm_service.dart:187-221`). SW ставит `tag: data.beaconId` и игнорирует `event.action` (`firebase_sw_controller.dart:51-86`). Нет `onMessage` и `flutter_local_notifications`. Это отдельный блок P1..P3. |
| K13 | К | Обычный «Mark done» для живой обязанности сервер отвергает (`attention_settlement_case.dart:34-48`), а клиент его показывает (`attention_receipt.dart:100`). Это существующий баг. N6 убирает кнопку первым отдельным PR. |
| K14 | К | На main NOW-строка подписана «ШАГ» (`beaconHudStepLabel`, `app_ru.arb@main:6367`) с атрибуцией «{name} · {when}». Макет §1 называет её «СЕЙЧАС». Ключ `beaconHudNowLabel` «СЕЙЧАС» на main уже есть (`:4298`). Default плана — макет: «СЕЙЧАС» через `beaconHudNowLabel`; конфликт с вкладкой «Сейчас» выносится в Q6. Слово «план» в коде и копирайте сейчас означает NOW-строку. Переименование делает C0 (§5.12), wire-значения `1` не меняются. |
| K15 | К | **Immediate email.** Всё в asksOfMe по умолчанию шлёт письмо сразу, если человек отсутствует или push не доставлен (`email_notification_service.dart:52-70`, `notification_preferences_entity.dart:51-55`). Для `planStepReminder` и `planStepOverdue` письмо сразу запрещено (`kNoImmediateEmailKinds`), и они исключаются из дайджеста. Для `planStepDue` и `planChangePending` письмо сразу разрешено (§4.6). |
| K16 | К | **Время в push и email.** `tzOffsetMinutes` по умолчанию 0 (`notification_preferences_entity.dart:26`). Клиент шлёт его только при сохранении тихих часов (`notification_settings_cubit.dart:82-92`). Поэтому серверная копия plan-уведомлений не печатает часы: только относительное время («через 15 мин», «ещё 30 мин», «перенесён на +1 ч»). Абсолютное время показывает только клиент, в зоне зрителя. |
| K17 | К | **Гонка с закрытием.** Close и finalize сериализуются через `ClosureRepository.lockRequest` (advisory `hashtextextended(beaconId, 4242)`, `closure_repository.dart:55`; `closure_case.dart:93-94, 835`; `closure_finalize_sweep_case.dart:41`). Все записи плана берут ту же блокировку **до** чтения статуса (P8). |
| K18 | К | `timeline_only` зарезервирован для иерархических уведомлений и гасит receipt на всех индикаторах (`attention_policy.dart:326-343`, `attention_dismissible_sql.dart:120-135`). Напоминание и просрочка получают **`primary`**. Из For You их держит scope `planAssignee` плюс явный фильтр (§4.7). |
| K19 | К | Чистые тесты `tentura_root` CI не запускает: pipeline гоняет только `tentura_lints`, `server` и `client` (`pipeline.yml:119-186`, `pipeline-prod.yml:63-98`). Тесты S2 кладём в `packages/server/test/domain/plan/` (не pg). |
| K20 | К | `kDefaultMinClientVersion` обязан **точно** равняться версии `packages/client/pubspec.yaml` (`min_client_version_gate_test.dart`). Каждое видимое изменение клиента требует semver и `web/index.html ?v=` (`AGENTS.md:33,36`). Отсюда «тройной bump» в каждом клиентском PR, а не только в V. |
| K21 | К | Сервер не закрыт клиентским флагом. Main выкатывается на dev при push, prod — из ветки `release` (`pipeline.yml:3-6, 533`; `pipeline-prod.yml:3-6`). Серверный env `PLAN_ENABLED` гейтит plan-мутации, регистрацию sweep, копию плана в fork и автоназначение (образец `env.dart:355-360`). |
| K22 | К | Триггер с `WHEN (COALESCE(NEW.kind, OLD.kind) <> 6)` на `INSERT OR UPDATE OR DELETE` — недопустимый SQL. Нужны три триггера (§3.1). `CREATE OR REPLACE` функции scope обязан сохранить имя параметра `p_account_id` (`m0213.dart:7`). |
| K23 | К | Realtime плана публикует специализированный DB-триггер на `beacon_plan`, а не вызов из Dart. Contract-тест требует producer в миграциях и фиксирует набор publishers (`realtime_entity_contract_test.dart:21-73`). `emit_realtime_entity_change` принимает `(p_entity, p_id, p_event, p_user_ids, p_extra)` (`m0193.dart:1640`). |
| K24 | К | Admission происходит не в трёх местах, а больше. Кроме `acceptHelpOffer`, `inviteToRoom` и `admit` есть `BeaconRepository.returnToPostAsAddressee` (`beacon_repository.dart:651-677`, SQL `post_reconcile_admission`), `BeaconRoomCase.stewardPromote` (`beacon_room_case.dart:1137`) и записи в `beacon_room_repository.dart:1078, 1141-1151`. Автоназначение вызывается из каждого, полноту покрывает архитектурный тест (§4.10). |
| K25 | К | Источник «было: X» хранится явно (`former_reason`: 1 = копия, 2 = уход). Автоназначение берёт только `former_reason = 1`. Иначе удалённый и снова допущенный X молча получил бы шаги обратно. |
| P1 | П | Шаги получают **новый kind `6`** (`coordinationItemKindPlanStep`), а не legacy `1`. Читатели kind=1 (`_activePlanParticipantUserIds` в `beacon_room_notification_context_repository.dart:87-112`, stale rules, зеркало `current_line`) шагов не видят. Код `4` не используем из-за политики «never renumber» (`discussion_product_policy.dart:17`). Клиентский `CoordinationItemKind.fromInt` бросает на неизвестном (`coordination_item.dart:23-28`), поэтому kind 6 никогда не попадает в `linked_item_id`. Это закрепляет pg-тест. |
| P2 | П | Корневой строки плана нет. Заголовок плана живёт в `beacon_plan` (заодно строка блокировки и realtime). Ревизии лежат в `beacon_plan_revision`: снимок без галок плюс `changes_json`, по образцу `m0199.dart:41-62`. |
| P3 | П | Галки хранятся в колонках `done_at` и `done_by_id` строки шага. В ревизии они не входят и `content_seq` не меняют. Восстановление ревизии сохраняет текущее состояние галок. |
| P4 | П | Удаление шага мягкое: `status = 3`, `cancelled_at`, `removed_seq`. Hard delete обнулил бы `linked_item_id` и цитаты (`m0193.dart:7638`). |
| P5 | П | Порядок хранится в существующем плотном `ordering` (smallint). Сервер перенумеровывает его внутри транзакции под блокировкой. Слияние порядка идёт на уровне списка по снимкам, перестановки не порождают конфликтов. |
| P6 | П | Id нового шага генерирует клиент: `PS` + 12 hex. Сервер проверяет префикс и коллизии. Так черновик переживает конфликт и повтор. |
| P7 | П | «Понял» хранится в ledger `beacon_plan_member` (`pending_from_seq`, `acked_seq`, `acked_at`) по паре (запрос, человек). Обязательство `planChangePending` одно на пару (человек, запрос) и продлевается каждой ревизией. Своё изменение подтверждать не нужно. Подтверждения требуют изменения названия, времени, исполнителя и удаление. Правка только описания или порядка его не требует. |
| P8 | П | **Порядок блокировок для всех записей плана** (save, restore, tick, untick, ack, cant_make, sweep, автоназначение, reconcile из lifecycle-хуков): (1) hierarchy mutation scope, только если вызывающий его уже держит (`admit`, `beacon_room_case.dart:1119`); план сам его не берёт (`beacon_hierarchy_repository.dart:28-34`); (2) `lockRequest(beaconId)` с ключом 4242; (3) повторное чтение статуса запроса под блокировкой; (4) `beacon_plan FOR UPDATE`; (5) `coordination_item`; (6) `beacon_room_message`. Отдельных advisory-блокировок для склейки нет. |
| P9 | П | Realtime идёт через kind `beacon_plan` (id = `beacon_id`). Его публикует триггер на `beacon_plan`, получатели — комната плюс stewards. Каждая запись плана поднимает `beacon_plan.change_seq`, так что и у галок есть видимая клиенту версия. Строковый NOTIFY `coordination_item` для kind 6 отключён, иначе правка N шагов дала бы N полных refresh (`beacon_view_cubit.dart:837-842`). |
| P10 | П | Все plan-I/O идут через V2 server GraphQL; `coordination_item` в Hasura не отслеживается. Время хранится в UTC через `InputFieldDatetime` (`_input_types.dart:95-140`), показывается в зоне зрителя. Сдвиг при копии клиент считает календарной арифметикой (§5.11). |
| P11 | П | «Передать другому» — прямое переназначение на одного человека. Проверяет его новый `PlanAssigneePolicy` на том же предикате, что `beacon_effective_admission` (автор, steward, участник с role 1 или `room_access = 3`, минус `block_hides`; `m0193.dart:791-816`), и не на себя. `BatonSelectionPolicy.validateCandidates` не подходит: он отвергает автора и требует tiers (`baton_selection_policy.dart:59-98`). Тот же набор людей использует picker исполнителя в редакторе. |
| P12 | П | Склейку отметок делает сервер под P8. Если хвостовая строка основной комнаты — marker 14 моложе 30 мин, её payload обновляется (UPDATE), иначе вставляется новая строка. |
| P13 | П | Лимиты: ≤ 100 шагов, название ≤ 120, описание ≤ 1000, комментарий ≤ 280. Не больше 20 сохранений за 60 с на актора, как `factEditRate*` (`env.dart:323-331`). |
| P14 | П | Вкладка Plan есть только в HUD-режиме (insiders). Outsiders в showcase (`beacon_request_modes.dart` на main) план не видят. Сервер отдаёт план при `canUseRoom`. |
| P15 | П | Два флага. Клиентский `const kPlanEnabled = bool.fromEnvironment('TENTURA_PLAN_ENABLED')` в `packages/client/lib/consts.dart` гейтит вкладку, HUD-строки, My Work-строки и лист копии; dev-сборка включает его через `--dart-define`. Серверный env `PLAN_ENABLED` гейтит запись (K21). Unit V включает оба. Минимальная версия клиента поднимается в каждом клиентском PR (K20). Флаги защищают от планов, созданных до появления UI. |
| P16 | П | Ru-копия на «вы» и родо-нейтральная: «Ваш шаг», «Вы свободны до», «Что изменилось», «отметка: X». Это совпадает с регистром приложения («Просьбы к вам», baton). Подписи «ТЫ»/«ВЫ» и «Понял»/«Понятно» решают Q10 и Q11. «Чат» в копии только как название вкладки, в остальных местах «обсуждение» (`.cursor/rules/terminology.mdc`). |
| P17 | П | Снятие отметки не удаляет строку чата. Соответствующая запись в marker-14 строке помечается `undoneAt` / `undoneById` и рисуется зачёркнутой с «отметка снята». Повторная отметка добавляет новую запись по правилам склейки. |
| P18 | П | **Шаг только с концом** (без начала) ведёт себя как шаг без времени: становится текущим после предыдущего. Граница просрочки = `endAt`. Без напоминания, NOW не двигает. В группировке по дням идёт по `endAt`. В матрице рисуется блоком 30 мин, заканчивающимся в `endAt`, с маркером открытого начала. |
| P19 | П | **Несколько активных шагов одновременно.** Текущий — первый в порядке плана среди активных неотмеченных; просроченные идут раньше наступивших. Остальные активные стоят в ДАЛЬШЕ с пометкой «тоже идёт» вместо «через …». Счётчик ⏰ в HUD считает просроченные шаги зрителя, заголовок вкладки — все. |
| P20 | П | **Шаг без исполнителя.** Sweep на его `startAt` (или на `endAt` для шага только с концом) один раз уведомляет автора (`planStepUnassigned`, фаза `unassignedDue`). NOW-строка в варианте «нет исполнителя». |
| P21 | П | **reviewOpen.** Запись разрешена (K6). Reconciler только закрывает и заменяет `planStepDue`/`planStepTurn`, новых не открывает; `planChangePending` открывается. Фазы sweep работают только для open family. Хуки reconcile ставятся на переход в review и на `ClosureCase.reopen` (`closure_case.dart:248`). |

---

## 3. Модель данных

### 3.0 Аудит до миграции (unit X0, read-only, dev и prod)

```sql
SELECT kind, status, (linked_parent_item_id IS NULL) AS root, count(*) FROM coordination_item GROUP BY 1,2,3;
SELECT count(*) FROM beacon_room_message m JOIN coordination_item c ON c.id = m.linked_item_id WHERE c.kind = 1;
SELECT count(*) FROM beacon_activity_event WHERE coordination_item_id IS NOT NULL;
SELECT count(*) FROM notification_outbox WHERE coordination_item_id IS NOT NULL;
SELECT count(*) FROM coordination_item WHERE creator_id IS NULL;
SELECT pg_size_pretty(pg_total_relation_size('public.coordination_item')),
       pg_size_pretty(pg_total_relation_size('public.beacon_room_message')),
       (SELECT count(*) FROM public.beacon_room_message);
```

- Строки kind=1 m0158 оставил намеренно (`m0193.dart:2316-2321`). Благодаря P1 они v1 не мешают, их судьбу решает X2.
- **Множество допустимых kinds в CHECK m0223 выводится из аудита.** Default — `(1, 6)`. Любой найденный kind, кроме 1 (включая 0 и 4), сначала разбирается в X0. Сейчас на `coordination_item` вообще нет CHECK по kind (`m0193.dart:6261, 7773-7808`), так что «неожиданный» kind в prod уронил бы deploy.
- Результаты записываются в issue #220. S1 не мержится, пока они не записаны для dev и prod.

### 3.1 Миграция `m0223` (unit S1; номер сверить)

```sql
-- 0) Guard: only audited kinds may exist (default set: 1)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.coordination_item WHERE kind NOT IN (1)) THEN
    RAISE EXCEPTION 'm0223: unexpected coordination_item kinds; see X0 audit (issue #220)';
  END IF;
END $$;

-- 1) Plan steps on coordination_item (kind = 6)
ALTER TABLE public.coordination_item
  ADD COLUMN start_at timestamptz NULL,
  ADD COLUMN end_at timestamptz NULL,
  ADD COLUMN done_at timestamptz NULL,
  ADD COLUMN done_by_id text NULL REFERENCES public."user"(id) ON DELETE SET NULL,
  ADD COLUMN former_assignee_id text NULL REFERENCES public."user"(id) ON DELETE SET NULL,
  ADD COLUMN former_reason smallint NULL CHECK (former_reason IN (1, 2)),  -- 1 copy, 2 leave
  ADD COLUMN source_item_id text NULL REFERENCES public.coordination_item(id) ON DELETE SET NULL,
  ADD COLUMN created_seq integer NULL,
  ADD COLUMN content_seq integer NULL,   -- plan seq of last content change (quote drift, step card)
  ADD COLUMN ack_seq integer NULL,       -- plan seq of last ack-relevant change (title/time/assignee/removal)
  ADD COLUMN removed_seq integer NULL;

ALTER TABLE public.coordination_item
  ADD CONSTRAINT coordination_item_kind_chk CHECK (kind IN (1, 6)),
  ADD CONSTRAINT coordination_item_plan_step_time_chk
    CHECK (end_at IS NULL OR start_at IS NULL OR end_at >= start_at),
  ADD CONSTRAINT coordination_item_plan_step_shape_chk CHECK (
    kind <> 6 OR (
      status IN (0, 3)
      AND linked_parent_item_id IS NULL
      AND published
      AND created_seq IS NOT NULL AND content_seq IS NOT NULL AND ack_seq IS NOT NULL
      AND ((status = 3) = (removed_seq IS NOT NULL))
      AND (done_at IS NOT NULL OR done_by_id IS NULL)           -- done_by may become NULL on erasure
      AND (former_reason IS NOT NULL OR former_assignee_id IS NULL)  -- former id may become NULL on erasure
    )),
  ADD CONSTRAINT coordination_item_plan_only_cols_chk CHECK (
    kind = 6 OR (start_at IS NULL AND end_at IS NULL AND done_at IS NULL AND done_by_id IS NULL
                 AND former_assignee_id IS NULL AND former_reason IS NULL AND source_item_id IS NULL
                 AND created_seq IS NULL AND content_seq IS NULL AND ack_seq IS NULL AND removed_seq IS NULL));

CREATE INDEX coordination_item_plan_live_order
  ON public.coordination_item (beacon_id, ordering) WHERE kind = 6 AND status = 0;
CREATE INDEX coordination_item_plan_assignee_live
  ON public.coordination_item (target_person_id, beacon_id) WHERE kind = 6 AND status = 0;
CREATE INDEX coordination_item_plan_start_open
  ON public.coordination_item (start_at) WHERE kind = 6 AND status = 0 AND done_at IS NULL AND start_at IS NOT NULL;
CREATE INDEX coordination_item_plan_end_open
  ON public.coordination_item (end_at) WHERE kind = 6 AND status = 0 AND done_at IS NULL AND end_at IS NOT NULL;
CREATE INDEX coordination_item_plan_former_copy
  ON public.coordination_item (beacon_id, former_assignee_id)
  WHERE kind = 6 AND status = 0 AND target_person_id IS NULL AND former_reason = 1;
-- FK-supporting partial indexes (erasure / cascade, cf. m0199.dart:55-60)
CREATE INDEX coordination_item_source_item ON public.coordination_item (source_item_id) WHERE source_item_id IS NOT NULL;
CREATE INDEX coordination_item_done_by ON public.coordination_item (done_by_id) WHERE done_by_id IS NOT NULL;
CREATE INDEX coordination_item_former_assignee ON public.coordination_item (former_assignee_id) WHERE former_assignee_id IS NOT NULL;

-- 2) Plan head (one per Request; lock row; realtime source)
CREATE TABLE public.beacon_plan (
  beacon_id text PRIMARY KEY REFERENCES public.beacon(id) ON DELETE CASCADE,
  revision_seq integer NOT NULL DEFAULT 0,
  change_seq integer NOT NULL DEFAULT 0,     -- bumped by every plan write incl. ticks/acks/sweep touch
  last_edited_by text NULL REFERENCES public."user"(id) ON DELETE SET NULL,
  last_edited_at timestamptz NULL,
  copied_from_beacon_id text NULL REFERENCES public.beacon(id) ON DELETE SET NULL,
  copied_from_seq integer NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX beacon_plan_last_edited_by ON public.beacon_plan (last_edited_by) WHERE last_edited_by IS NOT NULL;
CREATE INDEX beacon_plan_copied_from ON public.beacon_plan (copied_from_beacon_id) WHERE copied_from_beacon_id IS NOT NULL;

-- 3) Revision log (snapshots exclude ticks)
CREATE TABLE public.beacon_plan_revision (
  id text PRIMARY KEY DEFAULT concat('PR', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)),
  beacon_id text NOT NULL REFERENCES public.beacon_plan(beacon_id) ON DELETE CASCADE,
  seq integer NOT NULL,
  base_seq integer NULL,
  kind smallint NOT NULL CHECK (kind IN (0,1,2,3,4,5,6,7)),
     -- 0 created, 1 edited, 2 restored, 3 copied, 4 cant_make, 5 auto_assigned,
     -- 6 unassigned_on_leave, 7 cant_make_chat (history-only, snapshot unchanged)
  actor_id text NULL REFERENCES public."user"(id) ON DELETE SET NULL,
  restored_from_seq integer NULL,
  comment text NOT NULL DEFAULT '' CHECK (char_length(comment) <= 280),
  steps_json jsonb NOT NULL,     -- [{id,title,description,assigneeId,formerAssigneeId,startAt,endAt}] in plan order
  changes_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (beacon_id, seq),
  CHECK (kind <> 2 OR restored_from_seq IS NOT NULL)
);
CREATE INDEX beacon_plan_revision_actor_created ON public.beacon_plan_revision (actor_id, created_at DESC);

-- 4) Per-person ack ledger («Понял»)
CREATE TABLE public.beacon_plan_member (
  beacon_id text NOT NULL REFERENCES public.beacon_plan(beacon_id) ON DELETE CASCADE,
  user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  pending_from_seq integer NULL,  -- first unacked revision that affected this person
  acked_seq integer NOT NULL DEFAULT 0,
  acked_at timestamptz NULL,
  PRIMARY KEY (beacon_id, user_id)
);
CREATE INDEX beacon_plan_member_pending ON public.beacon_plan_member (user_id) WHERE pending_from_seq IS NOT NULL;

-- 5) Realtime publisher for kind 'beacon_plan' (room recipients + stewards)
CREATE FUNCTION public.notify_beacon_plan_change() RETURNS trigger
  LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp' AS $$
BEGIN
  PERFORM public.emit_realtime_entity_change(
    'beacon_plan', NEW.beacon_id, lower(TG_OP),
    ARRAY(SELECT DISTINCT u FROM unnest(
      public.realtime_room_recipients(NEW.beacon_id)
      || ARRAY(SELECT s.user_id FROM public.beacon_steward s WHERE s.beacon_id = NEW.beacon_id)) AS u),
    NULL);
  RETURN NULL;
END $$;
CREATE TRIGGER beacon_plan_entity_notify AFTER INSERT OR UPDATE ON public.beacon_plan
  FOR EACH ROW EXECUTE FUNCTION public.notify_beacon_plan_change();

-- 6) Silence per-row coordination_item NOTIFY for plan steps (P9): three triggers
DROP TRIGGER coordination_item_entity_notify ON public.coordination_item;
CREATE TRIGGER coordination_item_entity_notify_ins AFTER INSERT ON public.coordination_item
  FOR EACH ROW WHEN (NEW.kind <> 6) EXECUTE FUNCTION public.notify_entity_change('coordination_item');
CREATE TRIGGER coordination_item_entity_notify_upd AFTER UPDATE ON public.coordination_item
  FOR EACH ROW WHEN (OLD.kind <> 6 OR NEW.kind <> 6) EXECUTE FUNCTION public.notify_entity_change('coordination_item');
CREATE TRIGGER coordination_item_entity_notify_del AFTER DELETE ON public.coordination_item
  FOR EACH ROW WHEN (OLD.kind <> 6) EXECUTE FUNCTION public.notify_entity_change('coordination_item');
```

Пояснения к миграции:
- **Что сверить до написания миграции.**
  - Точную сигнатуру и тип `p_extra` у `emit_realtime_entity_change` (`m0193.dart:1640`) и формат `p_event`.
  - Что `realtime_room_recipients` возвращает `text[]` (`m0193.dart:4024`).
  - Имя таблицы и колонки stewards (`beacon_steward.user_id`), потому что `realtime_room_recipients` покрывает только автора и `room_access = 3` (`m0193.dart:4024-4038`).
  - Исходное определение `coordination_item_entity_notify` (`m0193.dart:7064`): события и аргументы. Литерал `'coordination_item'` обязан остаться в миграциях ради contract-теста.
- **Контракт realtime приземляется в том же unit S1.** Строка `beacon_plan` в `docs/contracts/realtime-entity-contract.json`. Publisher `notify_beacon_plan_change` добавляется в жёсткий набор `realtime_entity_contract_test.dart:56-73`. Клиентский `RealtimeEntityKind.beaconPlan` с веткой `fromWire` (`realtime_entity_change.dart:35-58`) нужен, потому что клиентский contract-тест требует enum для каждой строки (`client/test/architecture/realtime_entity_contract_test.dart:45-55`). Инвалидация на клиенте подключается позже, в C1; до того неизвестное событие игнорируется (`invalidation_service.dart:156-161`).
- **`published` для kind 6 всегда `true`.** Иначе ветка триггера шлёт только автору, а в БД default `false` (`m0193.dart:5455`).
- **Drift.** `table/coordination_items.dart` получает новые колонки, но читать kind 6 через Drift запрещено: всё идёт raw SQL. Nullable `creatorId` (сейчас `text().references(Users, #id)()`, `:14`, хотя в БД `ON DELETE SET NULL`, `m0193.dart:7783`) — существующий баг, он переезжает в X1. Таблицы `beacon_plan*` работают через raw SQL, как baton, без Drift-классов и без Hasura.
- **Без `beacon_room_state.current_line_set_at`** (K8).
- **Блокировки.** CHECK и индексы на `coordination_item` дешёвые, только если аудит подтвердит малый размер таблицы. Иначе S1 добавляет CHECK как `NOT VALID` с отдельным `VALIDATE`.

### 3.2 Миграция `m02xx_plan_scope` (unit N2; номер при merge): scope `planAssignee`

```sql
CREATE OR REPLACE FUNCTION public.responsibility_scope_base_beacons(p_account_id text)
  RETURNS TABLE(beacon_id text)
  LANGUAGE sql STABLE
  SET search_path TO 'public', 'pg_temp'
  AS $$
  -- existing two branches from m0213.dart:7-24 verbatim (authored kind-0 Requests ∪ active help offers)
  ...
  UNION
  SELECT ci.beacon_id
  FROM public.coordination_item ci
  JOIN public.beacon b ON b.id = ci.beacon_id AND b.kind = 0 AND b.status IN (0, 5, 7, 8)  -- = allowsCoordination
  WHERE ci.kind = 6 AND ci.status = 0                  -- any live step, ticked or not
    AND ci.target_person_id = p_account_id
    AND public.beacon_effective_admission(ci.beacon_id, p_account_id)  -- signature per m0193.dart:791-816
$$;
```

- Тело `m0213` сохраняется дословно, имя параметра, `STABLE` и `search_path` не меняются.
- В ветку попадает и отмеченный шаг. Иначе после отметки последнего шага settled-receipts steward перетекли бы в For You.
- Whitelist статусов совпадает с `allowsCoordination` (`beacon_status.dart:48`; legacy 4 → closed, `:24`). Закрытый или отменённый запрос выходит из scope.

### 3.3 Миграция `m02yy_plan_quote` (unit S9; номер при merge): цитата шага в сообщении

```sql
ALTER TABLE public.beacon_room_message
  ADD COLUMN quoted_plan_step_id text NULL REFERENCES public.coordination_item(id) ON DELETE SET NULL,
  ADD COLUMN quoted_plan_seq integer NULL;
ALTER TABLE public.beacon_room_message
  ADD CONSTRAINT beacon_room_message_plan_quote_pair_chk
    CHECK (quoted_plan_step_id IS NULL OR quoted_plan_seq IS NOT NULL) NOT VALID;
CREATE INDEX beacon_room_message_quoted_plan_step ON public.beacon_room_message (quoted_plan_step_id)
  WHERE quoted_plan_step_id IS NOT NULL;
```

- `NOT VALID` безопасен: новые колонки у существующих строк NULL. Перед построением индекса на большой таблице смотрим размер из аудита X0.
- `linked_item_id` для цитаты не используем. Иначе строка стала бы coordination-строкой и выпала бы из realtime paint (`room_message_snapshot_lookup.dart:33-38`), baton и promotion.
- Если шаг удалят физически, обнулится только id, `quoted_plan_seq` останется, и клиент нарисует «шаг удалён». При мягком удалении (P4) id остаётся, и клиент видит `removed`.

### 3.4 Что происходит с существующим `coordination_item`

| Что | v1 | Позже |
|---|---|---|
| Строки kind 1 | не трогаем, план их не видит (P1) | X2: удалить по рецепту m0158 (`m0193.dart:2373-2400`) или оставить, по итогам аудита |
| Kinds 2/3/5 и любые другие | guard в m0223 падает; CHECK `(1, 6)` | — |
| `status` 0..4, `linked_event_kind` 1..6 | для kind 6 только `status` 0/3 (CHECK) | — |
| `ordering` smallint | для kind 6 плотный 1..n | — |
| `linked_parent_item_id`, `accepted_by_id`, `last_reminded_at`, `stale_*`, `published=false` | для kind 6 не используются | X1: чистка мёртвого кода |
| `beacon_room_state.open_blocker_id` (мёртвый, `hasura/metadata.json:1865`) | не трогаем | X1 вместе с клиентом |
| `_activePlanParticipantUserIds` (без проверки допуска) | kind 6 не затрагивает | X1: сузить до допущенных или удалить |
| Drift `creatorId` non-null | не трогаем | X1 или отдельный bugfix |
| `linked_item_id` → kind 6 | запрещено; pg-тест в S7 | — |

### 3.5 Кто что видит

| Зритель | Вкладка Plan | Шаги, история | Галка | Правка, восстановление | «Понял» | «Не успеваю» |
|---|---|---|---|---|---|---|
| Автор (open / reviewOpen) | да | да | любой шаг | да | на свои шаги | на свои |
| Steward, допущенный | да | да | любой шаг | да (Q7) | на свои | на свои |
| Исполнитель, удалённый из комнаты / заблокированный / отозвавший предложение | нет | нет | нет | нет | нет; обязательства superseded | нет |
| Outsider (showcase) | нет вкладки | нет (сервер требует `canUseRoom`) | нет | нет | — | — |
| Автор draft после fork | секция плана в редакторе draft | да | нет | да (draft-гейт) | — | — |
| Любой после close / cancel | да, read-only | да | нет | нет | нет; обязательства superseded | нет |
| Любой после delete (status 2) | нет (запрос недоступен) | нет | нет | нет | обязательства superseded | нет |

---

## 4. Серверная логика

### 4.1 Общий домен в `tentura_root` (`/home/user/tentura/lib/domain/plan/`, новый)

Чистый Dart без Freezed. Его используют сервер и клиент (`packages/client/pubspec.yaml:31`, `packages/server/pubspec.yaml:24`).

- **`plan_snapshot.dart`.** `PlanStepSnapshot {id, title, description, assigneeId?, formerAssigneeId?, startAt?, endAt?}` (UTC, ISO с миллисекундами) и `PlanSnapshot {steps}` с каноническим JSON-кодеком. Порядок задаётся порядком в списке.
- **`plan_diff.dart`.** `PlanDiff.between(a, b)` → `List<PlanChange>`.
  - Операции: `added`, `removed`, `retitled`, `redescribed`, `retimed {fromStart, toStart, fromEnd, toEnd}`, `reassigned {from, to}`, `moved`.
  - `affectedUserIds(change)`: старый и новый исполнитель при `retitled / retimed / reassigned / removed / added`. При `redescribed` и `moved` никто не затронут (P7).
- **`plan_merge.dart`.** `PlanMerge.threeWay(base, theirs, mine)` → `PlanMergeMerged(snapshot, theirChangedStepIds)` или `PlanMergeConflict(stepIds)`. Алгоритм в §4.4.
- **`plan_schedule.dart`.** `PlanStepState {id, index, assigneeId, startAt, endAt, doneAt, removed}` и функции:
  - `currentStepFor(viewerId, steps, now)`: первый в порядке плана **активный** неотмеченный шаг зрителя; просроченные идут раньше просто наступивших (P19).
    - Шаг с `startAt` активен при `startAt ≤ now`.
    - Шаг без `startAt` (без времени или только с концом, P18) активен, если предыдущий живой шаг плана (любого исполнителя) отмечен или шаг первый. Это default вопроса Q2.
  - `alsoActiveFor`: остальные активные неотмеченные шаги зрителя (P19).
  - `nextStepFor`: следующий неотмеченный неактивный шаг зрителя после текущего.
  - `freeUntil`: `startAt` ближайшего будущего шага зрителя.
  - `overdueBoundary(step)` и `overdueBy(step, now)`. Граница = `endAt`; без конца — `startAt + 15 мин` (Q1); шага без времени нет просрочки.
  - `effectiveNow(manual{text, setAt, setById}, steps, status, now)` → `{source: manual|plan|none, stepId, index, count, assigneeId, setAt}`:
    - `manual.setAt` = `beacon_room_state.updated_at` (K8);
    - кандидаты в прибытие — живые шаги с `startAt ≤ now`, не отмеченные до своего начала (`doneAt == null || doneAt ≥ startAt`);
    - берётся максимальный `startAt`; при равенстве первый неотмеченный в порядке плана, иначе последний;
    - план побеждает, если `arrival.startAt > manual.setAt` или ручной строки нет; шаги без `startAt` NOW не двигают;
    - если шаг, державший NOW, удалили или перенесли в будущее, функция сама возвращает предыдущего «писателя»;
    - в `reviewOpen` и закрытых статусах источник всегда `manual` (main прячет строку шага в review);
    - `index` — позиция среди живых шагов плана, начиная с 1; одна нумерация на HUD, карточку и копию (в макете 3/9 и 4/9 расходятся).
- **Тесты:** `packages/server/test/domain/plan/*_test.dart`, не pg, их запускает server-job CI (K19).

### 4.2 Серверные слои

| Слой | Файл (новый, если не указано иное) |
|---|---|
| Entities | `packages/server/lib/domain/entity/beacon_plan.dart` (`BeaconPlan`, `PlanStep`, `PlanRevision`, `PlanMember`); `beacon_plan_outcome.dart` — sealed: `Applied(seq)`, `Merged(seq, theirStepIds, theirActorIds)`, `NoOp(headSeq)`, `Conflict(headSeq, stepIds)`, `RateLimited`, `NotFound`, `RestoreSourceMissing` (образец `beacon_fact_card_outcome.dart:4-43`) |
| Consts | `packages/server/lib/consts/beacon_plan_consts.dart`: `coordinationItemKindPlanStep = 6`, revision kinds 0..7, `formerReasonCopy = 1`, `formerReasonLeave = 2`, лимиты P13, `kPlanReminderLead = 15 min`, `kPlanUntimedOverdueGrace = 15 min`, `kPlanTickCoalesceWindow = 30 min`, `kPlanSystemLineMaxChanges = 20`. Markers 13..16 в `consts/beacon_room_consts.dart`, `BeaconRoomSystemMessageKind.plan = 5` в `consts/beacon_hierarchy_consts.dart`, activity types 21..24 в `consts/beacon_activity_event_consts.dart`. Всё это S3, вместе с маппингом превью и клиентскими mirrors |
| Exceptions | `domain/exception.dart` + `exception_codes.dart`, начиная с 1330: `planEditConflict` (extensions `currentSeq`, `conflictStepIds`), `planStepNotFound`, `planNotEditable`, `planActionStale`, `planRestoreSourceMissing`, `planRateLimited`, `planAssigneeNotAdmitted`, `planTooLarge`, `planDisabled`. Тест буквальных значений, потому что коды позиционные |
| Policy | `domain/policy/plan_assignee_policy.dart` (P11) |
| Ports | `domain/port/beacon_plan_repository_port.dart`; `domain/port/plan_write_effects_port.dart` — `afterWrite(PlanWriteEvent, tx)` с no-op реализацией по умолчанию. S7 (строки чата и activity) и N3 (reconcile) подключают свои реализации, S4..S6 вызывают хук без знания о них |
| Repository | `data/repository/beacon_plan_repository.dart` (raw SQL `customSelect`/`customStatement`) |
| Use case | `domain/use_case/beacon_plan_case.dart` (Injectable). Каталог `use_case/coordination_item/` не подходит, но producers плана **объявляются** в `updates-event-contract.json`, а `updates_event_coverage_test.dart:17-44` расширяется на `beacon_plan_case.dart`, `plan_step_sweep_case.dart` и `plan_obligation_reconciler.dart` |
| Reconciler | `domain/use_case/plan_obligation_reconciler.dart` (§4.6) |
| Sweep | `domain/use_case/plan_step_sweep_case.dart` (§4.5) |
| Auto-assign | `domain/use_case/plan_auto_assign_case.dart` (§4.10) |
| Env | `PLAN_ENABLED` в `env.dart` (образец `:355-360`). Выключенный флаг: мутации бросают `planDisabled`, sweep не регистрируется, fork не копирует план, автоназначение не работает, `beaconPlan` возвращает пустой план |
| API | `api/controllers/graphql/query/query_beacon_plan.dart`, `mutation/mutation_beacon_plan.dart` (lazy GetIt, как `mutation_room_baton.dart` на main); регистрация в `_queries_all.dart` / `_mutations_all.dart`; типы в `custom_types.dart` |

**Preflight для всех записей (P8, K17):**
1. Request-only (`BeaconKindPolicy.requireRequest`) и `PLAN_ENABLED`.
2. Внутри `TransactionalAttentionCase.runAction(actorUserId:)` (`transactional_attention_case.dart:14-22`): `lockRequest(beaconId)`.
3. Статус перечитывается под блокировкой: нужен `status.allowsCoordination`, либо draft-гейт (только автор, только fork-копия, только правка).
4. `ensureCanCoordinateOnBeacon` (`coordination_room_access.dart:6-24`).
5. `beacon_plan FOR UPDATE`.

### 4.3 GraphQL V2

**Queries**

| Операция | Вход | Выход |
|---|---|---|
| `beaconPlan` | `beaconId` | `BeaconPlanRow {beaconId, revisionSeq, changeSeq, lastEditedById, lastEditedByTitle, lastEditedAt, copiedFromBeaconId, copiedFromTitle (только если зритель может читать источник), steps: [PlanStepRow], members: [PlanMemberRow], viewerPendingAck: PlanPendingAckRow}` |
| `beaconPlanRevisions` | `beaconId, before: String?, aroundSeq: Int?` | `PlanRevisionPage {items: [PlanRevisionRow {seq, kind, actorId, actorTitle, comment, changesJson, restoredFromSeq, createdAt}], nextCursor}`. Keyset `'<iso>\|<lpad seq>'`, как `beacon_fact_card_repository.dart:750-819`. `aroundSeq` открывает историю на ревизии из чата |
| `beaconPlanRevision` | `beaconId, seq` | `{seq, stepsJson}` для «Вернуть эту версию» и предпросмотра |
| `inboxRoomContextBatch` (существует, `query_beacon_room.dart:106-115`) | — | + `planSliceJson` (§4.9) |
| `BeaconRoomStateGet` (существует) | — | `updatedAt` уже отдаётся и используется как `manual.setAt` (K8) |

`PlanStepRow {id, index, title, description, assigneeId, assigneeTitle, formerAssigneeId, formerAssigneeTitle, formerReason, startAt, endAt, doneAt, doneById, doneByTitle, contentSeq, ackSeq, assigneeAckedAt, assigneeAckPending}`:
- `assigneeAckedAt` = `acked_at` исполнителя, если его `acked_seq ≥ ack_seq`;
- `assigneeAckPending` = `ack_seq > acked_seq` и изменение сделал не исполнитель. Это индикатор «ждёт подтверждения» в списке.

**Mutations**

| Операция | Вход | Выход | Права |
|---|---|---|---|
| `beaconPlanSave` | `beaconId, baseRevisionSeq: Int!, stepsJson: String!, comment: String` | `PlanSaveResult {outcome: applied/merged/noop, revisionSeq, theirStepIds, theirActorIds}`; конфликт → исключение 1330 | §3.5 |
| `beaconPlanRestore` | `beaconId, fromSeq, baseRevisionSeq` | `PlanSaveResult` (строгий CAS без слияния) | как save |
| `beaconPlanStepSetDone` | `stepId, done: Boolean!` | `PlanStepRow` | любой с правом координации |
| `beaconPlanAck` | `beaconId, uptoSeq: Int!` | `PlanMemberRow` | сам человек |
| `beaconPlanStepCantMake` | `stepId, option: reschedule/handover, baseRevisionSeq, newStartAt?, newEndAt?, toUserId?` | `PlanSaveResult` | исполнитель шага |
| `roomMessageCreate` (существует, `mutation_beacon_room.dart:62-128`) | + `quotedPlanStepId, quotedPlanSeq, planCantMake: Boolean` | как сейчас | участник комнаты; `planCantMake` только исполнителю цитируемого шага |
| `beaconFork` (существует) | + `planStepTimes: [PlanStepTimeInput {sourceStepId, startAt, endAt}]`, `copyPlan: Boolean` | как сейчас | §4.10 |

Клиент регистрирует каждое имя в `_tenturaDirectOperationNames` (`build_client.dart:193`).

### 4.4 Сохранение ревизии и слияние

`BeaconPlanCase.save(actor, beaconId, baseSeq, draft, comment)`:

1. Preflight (§4.2), лимиты, rate limit (число ревизий актора за 60 с по индексу `actor_id, created_at`). Каждый исполнитель в draft проверяется `PlanAssigneePolicy`. Кандидат «было: X» допустим только как неизменённое значение.
2. `INSERT … ON CONFLICT DO NOTHING` в `beacon_plan`, затем `SELECT … FOR UPDATE` → `head`.
3. Если `head.seq == baseSeq`, то `merged = draft`. Иначе `base = snapshot(baseSeq)` (пусто при 0), `theirs = snapshot(head)` и `PlanMerge.threeWay(base, theirs, draft)`:
   - для каждого id из объединения: `mineChanged = mine[id] != base[id]`, `theirChanged = theirs[id] != base[id]`. Добавление и удаление тоже считаются изменением. Сравниваются только `title, description, assigneeId, startAt, endAt`;
   - изменились обе стороны и `mine[id] != theirs[id]` → **конфликт**. Сюда входит «я правил, они удалили» и наоборот. Два удаления совпадают, это не конфликт;
   - иначе берётся изменившаяся сторона;
   - **порядок.** Основа — порядок `theirs`. Шаг, который я передвинул (предшественник в `mine` ≠ предшественник в `base`), а они нет, вставляется после моего предшественника или в начало. Мои новые шаги тоже идут после моего предшественника. Если оба передвинули один шаг, побеждает `theirs`. Порядок никогда не конфликтует.
4. Конфликт → исключение 1330 с `{currentSeq: head.seq, conflictStepIds}`, ничего не пишется. `merged == theirs` → `NoOp(head.seq)`.
5. Запись под той же блокировкой:
   - `changes = PlanDiff.between(theirs, merged)`;
   - INSERT ревизии `seq = head+1`: `kind = created` при head 0, иначе `edited`; плюс `base_seq`, `steps_json = merged`, `changes_json`;
   - материализация шагов:
     - новые → INSERT (kind 6, `published = true`, `created_seq = content_seq = ack_seq = seq`);
     - изменённые → UPDATE контентных колонок и `content_seq = seq`; при ack-значимом изменении ещё `ack_seq = seq`;
     - смена исполнителя очищает `former_assignee_id` и `former_reason`;
     - удалённые → `status = 3, cancelled_at, removed_seq`;
     - `ordering` перенумеровывается 1..n только у изменившихся;
     - **колонки галок не трогаются никогда**;
   - `beacon_plan`: `revision_seq`, `change_seq + 1`, `last_edited_*`, `updated_at`. Триггер публикует realtime;
   - ledger: для каждого `affectedUserIds`, кроме актора, `pending_from_seq = COALESCE(pending_from_seq, seq)`;
   - `PlanWriteEffects.afterWrite(revised)`: строка marker 13 и activity 21 (S7), `PlanObligationReconciler.reconcile` (N3).
6. Ответ: `Applied(seq)` или `Merged(seq, theirStepIds, theirActorIds)`. `theirActorIds` — акторы ревизий в `(baseSeq, head]`.

**Restore** (`fromSeq`, `baseSeq`). Строгий CAS: `head.seq != baseSeq` → 1330. Снимок `fromSeq` становится новой ревизией `kind = restored`. Удалённые с тех пор шаги оживают (`status = 0`, `removed_seq = null`) **с текущими галками**. Исполнители проходят `PlanAssigneePolicy`; недопущенный становится «нет исполнителя (было: X)» с `former_reason = 2`. Подтверждения, строка 13 и reconcile проходят как при обычной правке.

**Tick** (`setDone`):
1. Preflight, затем `UPDATE … SET done_at = now(), done_by_id = actor` при `done` и `done_at IS NULL`. Повтор идемпотентен. `change_seq + 1`.
2. Effects: склейка строки 14 (§4.8) и activity 22.
3. Reconcile:
   - закрыть `planStepDue`/`planStepTurn` исполнителя со `settled_by_user_id = actor`;
   - если актор не исполнитель, отправить исполнителю `obligationEnded`;
   - если следующий шаг без `startAt` стал текущим → `planStepTurn` (кроме reviewOpen, P21).

**Untick:** `done_at = NULL, done_by_id = NULL`, `change_seq + 1`. В строке 14 запись помечается `undoneAt` (P17). Reconcile возвращает обязательство и снимает `planStepTurn` у следующего шага, если тот ещё не начат.

**Ack** (`uptoSeq`):
- `acked_seq = max(acked_seq, uptoSeq)`, `acked_at = now()`, `change_seq + 1`;
- если после `uptoSeq` нет ревизий, затронувших человека, то `pending_from_seq = null` и `planChangePending` закрыт (settled);
- иначе `pending_from_seq` = первая такая ревизия, обязательство остаётся;
- строки в чате нет (D10).

**Cant make:**
- `reschedule` → ревизия `kind = cant_make` с новыми временами. Одна строка marker 15, строки 13 нет. Автору `planCantMake`.
- `handover(toUserId)` → проверка `PlanAssigneePolicy` (допущен, автор или steward; не сам). Затем ревизия `cant_make` со сменой исполнителя, `pending_from_seq` у нового исполнителя, строка 15, автору `planCantMake`. Сам актор подтверждать не должен.
- **Обсуждение** — отдельной мутации нет. Клиент открывает composer с цитатой шага и флагом `planCantMake`. Когда сообщение отправлено, `roomMessageCreate` в той же транзакции:
  - вставляет сообщение;
  - пишет ревизию `kind = cant_make_chat` с неизменным снимком, `changes_json = [{op:'cantMake', stepId}]` и `comment` = первые 280 символов сообщения;
  - шлёт автору `planCantMake` с фрагментом сообщения.
  Строки 15 нет: само сообщение и есть след в чате. Если человек закрыл composer, ничего не происходит.
- Любой вариант закрывает висящий `planChangePending` актора: это доменный акт (K9).

### 4.5 Планировщик `PlanStepSweepCase`

- **Регистрация.** В `TaskWorkerCase._tasks` (`task_worker_case.dart:194-300`) с каденсом **30 с** (`_lastPlanStepSweepAt`). Регистрируется только при `PLAN_ENABLED`. Фабрика и ctor по образцу `DeadlineReminderSweepCase` (`deadline_reminder_sweep_case.dart:19-52`).
- **Кандидаты.** Выборка по индексам §3.1. Статус запроса строго **open family `IN (0, 7, 8)`** (P21; whitelist, а не список исключений).
- **Фазы:**
  - `remind` (нужен исполнитель): `start_at - 15 мин ≤ now < start_at`. Пропуск, если шаг отмечен, если до начала меньше 2 мин или если шаг создан или перенесён позже, чем за 15 мин до начала.
  - `due` (нужен исполнитель): `start_at ≤ now`. Шаг только с концом через `due` не проходит, он становится текущим по предшественнику.
  - `overdue` (нужен исполнитель): `now ≥ overdueBoundary`.
  - `authorLate`: `now ≥ overdueBoundary + 30 мин`.
  - `unassignedDue` (исполнителя нет): `now ≥ start_at` или `≥ end_at` для шага только с концом. Автору `planStepUnassigned` (P20).
- **Изоляция ошибок.** Каждый кандидат обрабатывается в своём `runAction` и своём `try/catch`, чтобы одна ошибка не обрывала проход (`task_worker_case.dart:448-453`). Внутри порядок P8, затем перепроверка: не отмечен, тот же исполнитель, то же время. Потом `PlanObligationReconciler.reconcile`.
- **Идемпотентность.**
  - Ключ `source_event_key` = `plan_step:<stepId>:<phase>:<assigneeId|none>:<epochMs(boundary)>`.
  - `immutable_payload` содержит **ровно** факты ключа `{stepId, assigneeId, phase, boundaryMs}`. Заголовок, описание и «на N мин» туда не входят.
  - Повторное использование ключа с другими фактами бросает `StateError` (`attention_dispatch_repository.dart:45-64`). Если окажется, что dispatch сравнивает title/body, sweep сначала читает существующее occurrence и пропускает кандидата.
  - Перенос или переназначение дают новый ключ.
- **После простоя.** Напоминание, опоздавшее больше чем на 10 мин, пропускается. `due` и `overdue` создают состояние, но если граница старше 10 мин, идут с `channelEligible = false`.
- **При `due`** sweep делает `change_seq + 1` на `beacon_plan`. Триггер толкает realtime, и у всех обновляются NOW и HUD. В чат ничего не пишется, `coordinationChanged` не создаётся.
- **Задержка канала.** Троттлинг 1 push в минуту на аккаунт (`attention_channel_delivery_repository.dart:46-58`) остаётся. Это риск, а не изменение.

### 4.6 Уведомления: события, категории, обязательства

Каждое событие проходит по рецепту baton B3 / S7:
- `attention_models.dart`, все switch в `attention_policy.dart`, `AttentionIntentCase`;
- `NotificationKind` + `categoryOf` (`notification_category.dart:26-50`) **в паре** с `_category`;
- copy builder с ru-веткой. **Абсолютного времени в копии нет** (K16): только относительные длительности от `now` в момент записи (`через 15 мин`, `ещё 30 мин`, `+1 ч`);
- `updates-event-contract.json` и клиентский `attention_event_classification.dart`.

Колонка «Email сразу» ниже — это `EmailNotificationService.considerImmediate`. Новый набор `kNoImmediateEmailKinds` исключает напоминание и просрочку. «Дайджест» — `email_digest_case.dart:72-79` с исключением тех же kinds.

| `AttentionEventType` | Кому (reason) | Класс | Категория (receipt и push) | Placement | Push | Email сразу | Дайджест | Logical key / закрытие |
|---|---|---|---|---|---|---|---|---|
| `planStepDue` | исполнитель (`planStepAssignee`) | обязательство | asksOfMe | primary | да | да (если push не доставлен и человек отсутствует) | да | `v1\|planStepDue\|{beacon}\|{step}\|{acct}`. Закрывают: галка, переназначение, удаление, перенос в будущее, cant_make, close |
| `planStepTurn` (шаг без начала после предыдущего) | исполнитель | обязательство | unblocksMe | primary | да | нет | по категории | `v1\|planStepTurn\|{beacon}\|{step}\|{acct}`. Закрывается так же |
| `planChangePending` | затронутый (старый или новый исполнитель), кроме актора | обязательство | asksOfMe | primary | да, «Понятно» | да | да | Subject `beaconId`, продлевается каждой ревизией (supersede, `attention_dispatch_repository.dart:124-174`). Закрывают: ack до head, cant_make, close. Одно occurrence на получателя (`plan_rev:<beacon>:<seq>:<acct>`), копия персональная (варианты в §5.12) |
| `planStepReminder` | исполнитель | optional | asksOfMe | **primary** (K18) | да | **нет** | **нет** | — |
| `planStepOverdue` | исполнитель | optional | asksOfMe | **primary** | да, один раз | **нет** | **нет** | Красное состояние клиент считает из `planStepDue` |
| `planStepLate` | автор запроса | optional | coordination | primary | да, один раз | нет | да | — |
| `planCantMake` | автор (если не актор) | optional | coordination | primary | да | нет | да | — |
| `planStepUnassigned` | автор | optional | coordination | primary | да | нет | да | Варианты: исполнитель ушёл / удалён / стёрт; начался шаг без исполнителя |
| `planEdited` | допущенные без изменений по их шагам, кроме актора | optional | **ambient** (новая ветка в `_category`, `attention_policy.dart:117-152`) | primary | нет (`channelEligible = false`) | нет | нет | collapse `plan_edited:{beacon}:{acct}` |
| `planStepDone` | допущенные, кроме актора и исполнителя | optional | ambient | primary | нет | нет | нет | collapse `plan_done:{beacon}:{acct}`, coalescing «count» |
| `obligationEnded` (есть в policy, producer появляется впервые) | исполнитель, чей шаг отметил другой или убрал без его участия | optional | **unblocksMe** (`attention_policy.dart:128`) | primary | нет | нет | по категории | Запись producer в `updates-event-contract.json` |

Вне таблицы:
- `planCopied` — не уведомление, а строка в чате.
- Автоназначение после копии создаёт `planChangePending` в варианте «на вас назначен шаг» (ревизия `auto_assigned`).

**Счётчик My Work** (`myDeskCount`) = живые обязательства. На один запрос у человека их не больше двух: `planStepDue|Turn` и `planChangePending`. Если оба про один шаг, считаются как 2: это два разных действия (default, риск в §7). Будущие шаги не считаются никогда.

**`PlanObligationReconciler.reconcile(beaconId, now, tx)`:**
1. По живому состоянию шагов, `plan_schedule.dart` и статусу запроса (P21) вычисляет у каждого исполнителя текущий шаг и висящее изменение.
2. Сравнивает с живыми receipts (`notification_outbox` по `logical_task_key`). Затем через новые методы `AttentionSystemSettlementPort` делает `record` / `settle` / `supersede`: `settlePlanStepDue`, `supersedePlanObligationsForAccount`, `resolvePlanChangePending(uptoSeq)`, `supersedePlanObligationsOnBeaconClose` (образец `attention_system_settlement_repository.dart:16-105`).
3. Вызывается:
   - из save, restore, tick, untick, ack, cant_make (в том числе через `roomMessageCreate`), sweep и автоназначения;
   - из `CoordinationCase.removeFromRoom`, `HelpOfferCase.withdraw`, очистки блокировки, стирания аккаунта (§4.11);
   - из close / cancel / delete (рядом с `supersedeAuthorHelpOfferObligationsOnBeaconClose`), из перехода в review и из `ClosureCase.reopen`.
4. Уход исполнителя (удаление, withdraw, блок, стирание): `target_person_id = null`, `former_assignee_id = X`, `former_reason = 2`, ревизия `unassigned_on_leave`, строка 13 в варианте «больше не участвует», автору `planStepUnassigned`.

**Reset counters:** `ObligationReconciliationCase.reconcileAccount` (`obligation_reconciliation_case.dart:51-91`) вызывает `settleObsoletePlanObligations` и `listUnbackedPlanTasks`.

### 4.7 For You: где строится и как план туда не попадает (правило D12)

**Где строится.**
- **Сервер.** `AttentionDismissibleSql.visibleWithSurface` (`attention_dismissible_sql.dart:31-56`) помечает receipt `'myWork'`, если его beacon входит в `scope = responsibility_scope_base_beacons(viewer)` ∪ beacon'ы с живым обязательством. Иначе receipt получает `'activity'`, это и есть For You.
  - Поток For You собирает `attention_repository.dart:318-420`: `activity_child_receipts` (`v.surface = 'activity'` **и** `primaryPlacement`, `:392-405`), `eligible_forward`, `eligible_pinned` и синтетический `requestActivity`.
  - Флажок и sweep — `forYouDot` / `forYouSweepEligible` (`query_attention.dart:87-88`).
- **Клиент** только раскладывает по серверному surface: `AttentionSurface` / `surfaceForDestination` (`domain/attention/entity/attention_feed.dart:12-86`), `for_you_stream_entries.dart`, `activity_stream_view.dart`, `inbox_screen.dart`, `home_attention_cubit.dart`. **Клиент ничего не перекладывает.** Это закреплено тестом `single_attention_owner_test.dart`.

**Маршрутизация плана.**

| Событие | Почему не попадает в For You |
|---|---|
| `planStepDue`, `planStepTurn`, `planChangePending` | Живое обязательство всегда тянет запрос в scope (`attention_dismissible_sql.dart:38-46`). Закрытые — см. следующие строки |
| `planStepReminder`, `planStepOverdue`, закрытые plan-обязательства | (1) Ветка `planAssignee` (§3.2) держит запрос в scope, пока у человека есть живой шаг (отмеченный или нет) в незакрытом запросе. (2) **Явный фильтр**: в `activity_child_receipts`, `forYouDot` и `forYouSweepEligible` типы `planStepDue`, `planStepTurn`, `planChangePending`, `planStepReminder`, `planStepOverdue` исключены всегда. Это покрывает закрытый запрос и переназначенный шаг |
| `planStepLate`, `planCantMake`, `planStepUnassigned` | Получатель — автор, а авторский запрос всегда в scope (`m0213.dart:7-24`) |
| `obligationEnded` (plan) | Необязательная информация. Пока запрос открыт и у человека есть шаги, он в My Work. Иначе может уйти в For You, что допустимо (пропуск без последствий) |
| `planEdited`, `planStepDone` | Ambient. В For You попадают только для зрителей вне scope, что D12 разрешает |

Unit X0 добавляет в `request-attention.md` §1 `responsible()` четвёртую ветку: «…OR is the assignee of a live plan step of an open Request while admitted». Фильтр типов фиксируется в §10 того же документа.

### 4.8 Системные строки в чате

Все строки пишутся с `system_message_kind = 5` (`plan`), `author_id = actor` (у автоназначения NULL допустим, так как kind ≠ NULL) и `semantic_marker` 13..16 (K7).

| Marker | Когда | `system_payload` (l10n-нейтральный) | Превью для старых клиентов |
|---|---|---|---|
| 13 `planRevised` | save, restore, `auto_assigned`, `unassigned_on_leave` (не cant_make) | `{actorId?, revisionSeq, revisionKind, restoredFromSeq?, changeCount, changes:[≤20 {op, stepId, title, from?, to?}], comment, subjectUserId?}` | `planUpdated = 2` |
| 14 `planStepsDone` | tick; склейка в хвост (P12); untick помечает запись (P17) | `{ticks:[≤20 {stepId, title, assigneeId, actorId, at, undoneAt?, undoneById?}]}` | `done = 7` |
| 15 `planCantMake` | cant_make reschedule / handover | `{actorId, stepId, title, option, shiftMinutes?, toStartAt?, toUserId?, revisionSeq}` | `planUpdated = 2` |
| 16 `planCopied` | `publishDraft` запроса-копии с шагами | `{sourceBeaconId, stepCount, revisionSeq: 1}`. Названия источника нет (ADR 0004 Decision 8: ссылка по id). Клиент показывает название, только если зритель может читать источник, иначе «из другого запроса» | `planUpdated = 2` |

- **Склейка** под P8, без отдельной advisory-блокировки. Хвост = последняя строка основной комнаты (`thread_item_id IS NULL`, индекс `beacon_room_message_beacon_created_idx`, `m0193.dart:6639`). Если хвост — marker 14 моложе 30 мин, payload обновляется (образец `_mergeSourceMessageLastStatusEvent`, `coordination_item_repository.dart:1188-1235`), иначе вставляется новая строка. UPDATE клиент получает через refetch; для ambient это приемлемо.
- **Старые клиенты:** неизвестный `system_message_kind` с неизвестным marker рисуется как «System» (`room_message_tile.dart:389`). Падает только неизвестный `ThreadMessagePreviewKind`, поэтому новых preview kinds нет (K5). Это правило S3.
- **Activity events:** 21 `planRevised`, 22 `planStepDone`, 23 `planCantMake` (включая `cant_make_chat`), 24 `planCopied`. `coordination_item_id` заполняется для шаговых событий. В Log их включает явный `switch` в `isCoordinationLogEventType`: он покрывает 100..499 **и** явный список низких типов 1..20 (`beacon_activity_event_consts.dart:8-58`). Нужен и клиентский mirror.
- **`linked_item_id`** у plan-строк всегда NULL (P1).
- **Строк нет** при наступлении времени, напоминаниях и «Понял» (D10).

### 4.9 `planSliceJson` для My Work и inbox

Поле добавляется в `InboxRoomContextRow` (`custom_types.dart:641-660`) и вычисляется **одним** batched SQL по `beaconIds`, без вызова на каждый beacon (`beacon_room_case.dart:760-818` уже делает около 5 запросов на beacon).

```json
{"done":4,"total":9,"overdueMine":1,
 "current":{"stepId":"…","title":"…","description":"…","startAt":"…","endAt":"…","overdueSince":"…"|null},
 "alsoActive":[{"stepId":"…","title":"…"}],
 "next":{"stepId":"…","title":"…","startAt":"…"},
 "pendingAck":{"fromSeq":12,"headSeq":14,"changeCount":3,"actorIds":["…"],"lastAt":"…","sample":{"op":"…","title":"…","from":"…","to":"…"}},
 "now":{"source":"plan","stepId":"…","title":"…","assigneeId":"…"|null,"startAt":"…","index":3,"count":9}}
```

- Если `status.allowsCoordination` ложно, отдаются только `done/total`, а `current`, `alsoActive`, `next`, `pendingAck` и `now` равны `null`. Так закрытый запрос не предлагает [Готово], которое сервер отвергнет.
- `now` вычисляет `effectiveNow` из `tentura_root`. Для старых клиентов `currentLine` не меняется (K8).

### 4.10 Копия запроса с планом

**`BeaconCase.fork`** (`beacon_case.dart:776-842`) получает `copyPlan` и `planStepTimes`. Создание beacon и копия плана идут **одной транзакцией** через новый метод порта `BeaconRepositoryPort.createForkWithPlan`. Сейчас `createBeacon` открывает свою транзакцию (`beacon_repository.dart:165-269`). Копии картинок остаются вне транзакции, как и сейчас (`beacon_case.dart:793-810`).

1. **Гейт:** `PLAN_ENABLED`, `copyPlan` и вызывающий — автор источника, его допущенный участник или steward. Иначе шаги **молча не копируются**, fork выполняется как сейчас. Покрыто pg-тестом.
2. Создаются `beacon_plan(beacon_id = new, revision_seq = 1, copied_from_beacon_id, copied_from_seq)` и ревизия 1 `kind = copied`.
3. Шаги копируются в порядке плана: `title`, `description`, а `start/end` берутся из `planStepTimes` (клиент считает их, §5.11). Шаг без времени копируется без времени. `done_*` очищаются, `source_item_id` заполняется.
4. Исполнитель:
   - если `X == caller`, шаг сразу назначается на caller, `former` = null;
   - если X заблокирован новым автором или скрыт `block_hides`, `former` = null;
   - иначе `target = null`, `former_assignee_id = X`, `former_reason = 1`.
5. Обязательства, строки чата и напоминания в draft не создаются: sweep берёт только open family.

**`publishDraft`** (`beacon_case.dart:297-315`). Включая ветку дочернего запроса `_childCreateCase.publishDraft`: если `beacon_plan.copied_from_beacon_id` задан, пишется строка 16 и вызывается reconcile.

**Автоназначение при допуске** — `PlanAutoAssignCase.onAdmitted(beaconId, userId, tx)`:

```sql
UPDATE coordination_item
SET target_person_id = $user, former_assignee_id = NULL, former_reason = NULL, ack_seq = $newSeq, content_seq = $newSeq
WHERE beacon_id = $b AND kind = 6 AND status = 0
  AND target_person_id IS NULL AND former_assignee_id = $user AND former_reason = 1
```

- Затрагивается только незанятый шаг с `former_reason = 1` (копия), один раз. Шаг, освобождённый уходом (`former_reason = 2`), автоматически не возвращается (K25).
- Если строки обновились: ревизия `auto_assigned` (актор NULL), строка 13 «Шаги назначены: X», `pending_from_seq` у человека, reconcile → `planChangePending`.
- **Места вызова.** Все внутри своих `runAction`, **не** из data-layer recorder (`beacon_room_participant_join_recorder.dart:9-47`):
  - `CoordinationCase.acceptHelpOffer` (`coordination_case.dart:360-405`);
  - `setCoordinationResponse(inviteToRoom)` (`:628-709`, вызов `:689`);
  - `BeaconRoomCase.admit` (`beacon_room_case.dart:1099-1135`);
  - `BeaconRoomCase.stewardPromote` (`:1137`);
  - путь `BeaconRepository.returnToPostAsAddressee` / `post_reconcile_admission` (`beacon_repository.dart:651-677`), через его use case;
  - вызывающие `beacon_room_repository.dart:1078, 1141-1151`.
- **Полнота.** Архитектурный тест `plan_auto_assign_hook_coverage_test.dart` ищет в `lib/data` все записи `room_access = 3` и вставки steward. Каждый найденный писатель должен быть в allowlist с хуком.
- **Backstop:** bookkeeping-сверка по образцу `UserBookkeepingCase` (`user_bookkeeping_case.dart:40-66`).

### 4.11 Стирание аккаунта и удаление запроса

- **Стёртый исполнитель.** До удаления пользователя flow стирания вызывает для его живых шагов тот же путь ухода (§4.6, п. 4): ревизия `unassigned_on_leave`, автору `planStepUnassigned`. Иначе FK `SET NULL` (`m0193.dart:7808`) молча снимает исполнителя.
- **`scrubDeletedOwnedBeaconContent`** (`user_erasure_repository.dart:65-112`) для запросов стёртого автора дополнительно:
  - очищает `title`/`description` шагов;
  - удаляет строки `beacon_plan_revision` (снимки и комментарии);
  - очищает названия шагов в `system_payload` marker 13..15.
- **Комментарии ревизий** стёртого пользователя в чужих запросах заменяются на `''`. Названия шагов, которые он писал в чужих планах, остаются: это общий контент, как текст запроса.
- **User id** в оставшихся JSON-снимках читатели разрешают через LEFT JOIN. Отсутствующий пользователь показывается как «удалённый участник» (`planDeletedUser`).

---

## 5. Клиент

### 5.1 Слои (clean-architecture)

| Слой | Файлы (новые, `packages/client/lib/features/beacon_plan/`) |
|---|---|
| domain/entity | `beacon_plan.dart`, `plan_step.dart`, `plan_revision_entry.dart`, `plan_member.dart`, `plan_viewer_slice.dart` (`tryParse` для `planSliceJson`: неизвестные ключи игнорируются, битые данные → null) |
| domain/exception | `beacon_plan_exceptions.dart` (1330+ с `currentSeq` и `conflictStepIds`; декодирование в `build_client.dart`, как `throwIfBeaconFactCardError`) |
| domain/use_case | `beacon_plan_case.dart` (обёртка над репозиторием, без UI) |
| data/gql | `beacon_plan_get.graphql`, `beacon_plan_save.graphql`, `beacon_plan_restore.graphql`, `beacon_plan_revisions.graphql`, `beacon_plan_revision.graphql`, `beacon_plan_step_set_done.graphql`, `beacon_plan_ack.graphql`, `beacon_plan_step_cant_make.graphql` |
| data/repository | `beacon_plan_repository.dart` |
| ui/bloc | `plan_cubit.dart` (план, фильтр, оптимистичная галка с откатом), `plan_edit_cubit.dart` (черновик; `baseSeq` берётся **при открытии**), `plan_history_cubit.dart` (обновляет base после каждого restore/Undo; вход `aroundSeq`) |
| ui/widget | `beacon_plan_surface.dart`, `plan_step_row.dart`, `plan_now_line.dart`, `plan_step_sheet.dart`, `plan_cant_make_sheet.dart`, `plan_edit_sheet.dart`, `plan_conflict_resolver.dart`, `plan_history_sheet.dart`, `plan_people_matrix.dart`, `plan_empty_state.dart`, `plan_datetime_field.dart`, `plan_person_filter.dart`, `plan_copy_sheet.dart` |

- Общие правила `tentura_root/domain/plan` используются напрямую. HUD, My Work, inbox и пин чата считают одной функцией.
- **Schema:** `lib/data/gql/schema.graphql` через schema_fetcher или руками. Какой способ, указать в коммите (`direct_v2_schema_overlay_test.dart:5-9`). Затем `build_runner`.
- **Realtime:**
  - `RealtimeEntityKind.beaconPlan` появился ещё в S1; C1 подключает `BeaconRoomEntityType.plan` (`beacon_room_invalidation.dart:49-62`);
  - `BeaconViewCubit` делает **точечный** refetch плана в `_fetchForEntityTypes` (`beacon_view_cubit.dart:885-910`), а не полный refresh;
  - `RoomCubit` обновляет пин NOW; сейчас он игнорирует hint `beacon`, поэтому `plan` маппится в room invalidation;
  - My Work добавляет `plan` в desk-relevant (`beacon_threads_case.dart:55-63`).
- **Mirrors** (приземляются в S3, §6): markers 13..16, `BeaconRoomSystemMessageKind.plan = 5` (`domain/entity/beacon_room_consts.dart:62-67`), activity 21..24, коды 1330+.

### 5.2 Лестница ВЫ / ПО ПЛАНУ / ДАЛЬШЕ (чистая, `domain/coordination/beacon_you_plan_slots.dart`)

Вход: существующий `BeaconYouSituationInput` плюс `PlanYouInput {current, alsoActive, next, freeUntil, pendingAck, overdueBy}`. Подпись первой строки: `beaconHudYouLabel` («ВЫ» на main; Q10).

| Приоритет | Условие | ВЫ | ПО ПЛАНУ | ДАЛЬШЕ |
|---|---|---|---|---|
| 0 | запрос закрыт, отменён или удалён | существующий closed fallback | — | — |
| 1 | системное обязательство зрителя: автор рассматривает предложения, helper terminal stake (`beacon_you_presentation.dart:181-211`) | системная строка | `pendingAck`, если есть (с [Понятно] [Не успеваю]); иначе текущий шаг | текущий шаг, если `pendingAck` занял ПО ПЛАНУ; иначе следующий |
| 2 | `pendingAck` | «{actor} · {when}: «{step}» {change}» или «{actor} · {when}: изменено ваших шагов: {n}» + [Понятно] [Не успеваю]; если изменение касается текущего шага, ещё [Готово] | текущий шаг, если он другой | следующий или «тоже идёт» |
| 3 | `current` | шаг + описание (одна строка, обрезка) + время + [Готово] [Не успеваю]; при `overdueBy` тон `danger`, «⏰ +N мин», «нужно было к HH:MM» | — | `alsoActive` («тоже идёт») или следующий (приглушённо, «через …») |
| 4 | будущий шаг, `current` нет | «Вы свободны до HH:MM» | — | следующий |
| 5 | шагов нет | существующие fallbacks (`deriveBeaconYouEmptyFallback`, `beacon_you_situation.dart:99-142`) | — | — |

- Группа занимает не больше 3 строк. Если не помещается, первой выпадает ДАЛЬШЕ. `pendingAck` не выпадает никогда (D3).
- Шаг плана считается личным обязательством в `hasBeaconYouPersonalObligation` / `isBeaconYouRowVisible`.
- Авторская кнопка ACT остаётся отдельной (`beacon_hud_author_action.dart:81-120`).

**NOW.** `effectiveNow` выбирает между ручной строкой и строкой плана. Подпись строки — `beaconHudNowLabel` «СЕЙЧАС» (макет; Q6).
- Ручная строка: текст + существующая атрибуция «{name} · {when}» (`beaconHudStepAttribution`).
- Плановая строка: «HH:MM {assignee}: {title}» или «HH:MM {title} · нет исполнителя». Обрезка только при отображении, подпись «по плану · шаг {n}/{N}».
- ✎ остаётся ручной правкой. Она пишет `updated_at` и поэтому всегда новее.

**Счётчик** «▤ план {done}/{total}», при просрочке ещё «⏰ {n}» (просрочки зрителя, P19). У обоих есть semantics-подписи, как у `beaconHudCounterFacts`. Тап открывает вкладку Plan.

**Тикер.** `ui/widget/next_boundary_ticker.dart` — обобщённый `StaleDeadlineTicker` (`stale_deadline_ticker.dart:9-60`, сейчас без пользователей). Перестраивает виджет по ближайшей границе: старт или конец моих шагов, старт любого шага для NOW, минута для «+N мин». Это не polling: данные не перезапрашиваются.

**Файлы на main:** `beacon_hud_pinned_block.dart` (слот «participant scenarios will reuse that slot»), `beacon_hud_metadata_composer.dart`, `beacon_hud_row_lead.dart` (иконки `next`, `plan`), `beacon_hud_derivation.dart`. Новые поля плана нужно добавить в ручной список `buildWhen` у `BeaconNowSurface`.

### 5.3 Вкладка Plan

- **`BeaconSurface.plan`** (`beacon_view_constants.dart:5-35`): compact `[now, plan, room, people]`, split `[now, plan, people]`. Только в HUD-режиме (P14).
- **Подключение:**
  - `BeaconSurfaceTabs` (`beacon_surface_tabs.dart:32-133`) с бейджем: моё наступившее / просроченное / неподтверждённое, тон danger при просрочке;
  - `kBeaconViewTabPlan` + `kQueryPlanStep` (`consts.dart:102-117`);
  - нормализатор (`app/router/beacon_view_route_normalizer.dart:64-86`);
  - `TestIds.beaconTabPlan`;
  - `_buildSelectedSurface` и PopScope (`beacon_view_screen.dart:643-685, 1029-1037`);
  - destination kind `beacon_plan_step` (`domain/attention/destination_map.dart:12-34`).
- **Список:**
  - заголовок «План · 4/9 · правка: {name}, {when}» и ⏰ по всем просрочкам;
  - управление: [Все ▾] (выпадающий список людей: все / конкретный человек / «Нет исполнителя»), [Мои], «История», ✎, и на ширине ≥ 600 переключатель «Список / По людям»;
  - фильтр и переключатель строятся из компонентов дизайн-системы без `Chip` / `SegmentedButton` / `Badge`. Lint `no_operational_pill_widgets_in_beacon_view` (`tentura_lints/lib/src/rules/no_operational_pill_widgets.dart:55`) расширяется на `features/beacon_plan/`;
  - группы по дням в зоне зрителя;
  - «—» означает шаг без времени, «до HH:MM» — шаг только с концом;
  - ✓ приглушён, ⏰ красный;
  - «нет исполнителя» показывается с «было: X»;
  - редакторам видна пометка «ждёт подтверждения: {name}» (`assigneeAckPending`);
  - линия «сейчас» стоит между последним шагом с `startAt ≤ now` и следующим и двигается тикером;
  - «Мои» показывает мои шаги и приглушает соседние чужие;
  - тап по ☐ ставит галку оптимистично; при ошибке откат и snackbar `planErrorTickFailed`.
- **Пустое состояние** (§7 макета): `planEmptyTitle` / `planEmptyBody` / новый ключ `planEmptyCta`. CTA видят только те, кто может править. Если ревизии есть (все шаги удалены), показывается ссылка «История плана ›». Ноль живых шагов = пустое состояние, счётчик HUD скрыт, обязательства superseded. Отдельного действия «удалить план» нет.
- **Часовой пояс:** время всегда в зоне зрителя, без показа чужой зоны (§1.3).

### 5.4 Матрица «люди × время»

- `plan_people_matrix.dart` показывается через `LayoutBuilder` **ширины панели Plan**, при ≥ 600. В split это левая панель: чат на main всегда открыт справа. Переключатель «Список / По людям»; на узкой панели переключателя нет.
- **Строки:** исполнители плюс «Нет исполнителя».
- **Колонки:** часы выбранного дня. Выбор дня — кнопки «‹ ›» с semantics «Предыдущий день» / «Следующий день». Горизонтальный скролл только внутри матрицы.
- **Блоки шагов** по `start/end`:
  - шаг без конца — блок 30 мин с маркером открытого конца;
  - шаг только с концом — блок 30 мин до `endAt` с маркером открытого начала;
  - шаг без времени — в колонке «Без времени».
- Вертикальная линия «сейчас». Тап по блоку открывает карточку шага.

### 5.5 Карточка шага (`plan_step_sheet.dart`)

- **Содержимое:**
  - «Шаг {n} из {N}», название, описание, исполнитель, «{day} {start} – {end}»;
  - «⏰ опаздывает на N мин»;
  - статус подтверждения: «Изменение подтверждено: ✓ HH:MM» или «Изменение ещё не подтверждено»;
  - «отметка: X».
- **Кнопки:**
  - [Готово] / [Снять отметку];
  - [Перенести]: это `cant_make reschedule`, если я исполнитель, иначе редактор с этим шагом;
  - [⋯]: «Передать», «Изменить», «Удалить шаг» (с подтверждением);
  - «Обсудить ›»: composer с цитатой шага.
- **Deep link** `tab=plan&step=<id>` прокручивает к шагу и подсвечивает его через `FocusFlashHighlight`.

### 5.6 Редактор и конфликт

- `PlanEditCubit` хранит черновик и `baseSeq`, взятый при открытии.
- **Перестановка** через `ReorderableListView` с ≡ handle (не только long-press).
- **Поля:**
  - «Что сделать» (название);
  - «Подробности» (описание);
  - «Исполнитель»: single-select из `PlanAssigneePolicy`-набора (автор, stewards, допущенные; не список baton) плюс «Без исполнителя»;
  - «Начало» и «Конец»: `plan_datetime_field.dart` = `showDatePicker` с границами `_calendarDate` (`info_tab.dart:922-945`) плюс `showTimePicker`; «Без времени» очищает.
- **Действия:** добавить шаг, удалить шаг, комментарий «Что изменилось», «Сохранить». Закрытие с несохранёнными правками спрашивает «Отменить изменения?».
- **Валидация** на клиенте: пустое название, конец раньше начала, больше 100 шагов, длины полей.
- **Merged** → snackbar с именами из `theirActorIds`: «Пока вы правили, изменено шагов: {n} ({names}). Объединили».
- **Conflict** → `plan_conflict_resolver.dart`: для каждого конфликтного шага выбор «Моя версия / Их версия», затем повтор с `base = currentSeq`. Черновик не теряется.

### 5.7 История

- `plan_history_sheet.dart`. Rail, сворачиваемое тело и Undo-баннер выносятся из `fact_history_sheet.dart:131-184, 495-541, 570-656` в общие виджеты.
- Строки рисуются из `changesJson` и `kind`: создан, правка, возврат к версии, копия («скопирован из …» / «из другого запроса»), «не успевает» (оба вида), автоназначение (без актора), снятие исполнителя при уходе. `wordDiff` используется только для описания.
- «Вернуть эту версию» запускает restore с актуальным base; после restore cubit обновляет base. Вход `aroundSeq` открывает историю из строки чата.

### 5.8 My Work

- **`MyWorkPlanStepRows`** (`features/my_work/ui/widget/my_work_plan_step_rows.dart`) рендерится **первым** внутри `MyWorkObligationBlock` (`my_work_obligation_block.dart:39-60`) из `PlanViewerSlice`:
  - строка изменения с [Понятно] [Не успеваю];
  - текущий шаг с описанием и [Готово] [Не успеваю], красный только при просрочке;
  - тусклая строка ДАЛЬШЕ или будущего шага без кнопок («через 2 дня»).
  - Скрыто при `kPlanEnabled == false` и при закрытом запросе (slice без `current`).
- Plan-receipts остаются в фактах `MyWorkCardAttentionView` для индикаторов, но исключаются из строк `ActivityEventSubcardBlock` и из `eventTotal`. Расширяется `myWorkObligationBlockVisible`.
- **Членство** `MyWorkMembershipSource.planAssignee` (`my_work_card_view_model.dart:29`) идёт через `MyWorkRepository.fetchInit` (`my_work_case.dart:91-97`), `derive_my_work_cards.dart:262-310` и отзыв при архиве (`:380-414`).
- **Маршрутизация карточек.** Obligation-only и planAssignee-карточки не-авторов получают участниковую карточку без меню Close/Cancel/Edit/Delete. Сейчас `obligationActive` ведёт на `_AuthoredActiveCard` (`my_work_cards.dart:123-131`).
- **NOW.** Строка ⚑ NOW использует `slice.now`, а не только `roomCurrentLine` (`my_work_case.dart:296-301`). То же в строке inbox watchlist (`inbox_watchlist_row.dart:299-300`).
- Строку YOU на карточке скрывает существующее правило при obligation-строках (`my_work_cards.dart:169-178`). В подзаголовке `nextMoveText` план **не** дублируется.
- **Сортировка** не меняется: Needs-you идёт по `needsYouAt` живого обязательства (`derive_my_work_cards.dart:65-74`). Будущие шаги карточку не поднимают.

### 5.9 Push-действия (P1..P3)

| Сторона | Изменения |
|---|---|
| Сервер, payload | `AttentionChannelDecision` → `_decisionPayload` → `FcmNotificationEntity` → `buildFcmMessagePayload` (`fcm_service.dart:187-221`) получают `stepId`, `actions: [{id: done\|ack\|open, title}]` (заголовки en/ru на сервере), `actionToken`, `tag: 'plan:' + stepId`, `ttlSeconds` (напоминание живёт до старта), `webpush.headers.Urgency = high`. TTL сейчас жёстко 3600 (`fcm_remote_repository.dart:69`), делается параметром |
| Сервер, батч | Plan-push обходят `FcmBatchQueue`, по образцу ветки reviewReady (`beacon_notification_service.dart:73-84`) |
| Токен | `PushActionToken` по образцу `UnsubscribeToken` (`unsubscribe_token.dart:13-67`): `{accountId, action, stepId или beaconId, seq, exp ≤ 24 ч}`, HMAC, новый env-секрет |
| Endpoint | `api/controllers/push_action_controller.dart`, только POST, регистрация в `api/root_router.dart` рядом с `:187-196`. `handle /api/v2/push-action` в `Caddyfile` и `Caddyfile.local`, иначе `/api/*` уйдёт в Hasura (`Caddyfile:129-130`). Вызывает те же `setDone` / `ack`. Устаревший seq, переназначенный шаг или закрытый запрос → 409 `planActionStale` |
| Service worker | `firebase_sw_controller.dart:51-86`. При `Notification.maxActions > 0` передать `actions`. В `notificationclick` по `event.action`: `fetch POST` с токеном, затем заменить уведомление на «Отмечено: {step}» / «Подтверждено» (успех) или «Не получилось — откройте шаг» (ошибка). Без action открыть `data.link` (deep link шага) |
| Клиент | `FirebaseMessaging.onMessage` в web-lifecycle показывает in-app баннер, потому что видимая вкладка глотает push |

- **Поддержка:** Chromium desktop и Android. В Safari/iOS и Firefox тап открывает карточку шага.
- **Порядок выкладки.** SW отдаёт сервер (`Caddyfile:122-123`), поэтому он уходит вместе с серверным деплоем. Маршрут Caddy (P2) обязан выйти тем же или более ранним деплоем, чем SW (P3).

### 5.10 Чат

- **Виджеты строк:** `room_plan_revision_line.dart`, `room_plan_tick_line.dart` (зачёркнутые записи, P17), `room_plan_cant_make_line.dart`, `room_plan_copied_line.dart`. Ранний return в `RoomMessageTile.build` по `systemMessageKind == plan` ставится рядом с веткой `convertedToRequest` (`room_message_tile.dart:492`), до bubble. Якорь перепривязать на main.
- **Payload.** Типизированные геттеры возвращают null при битой форме. Тогда строка рисуется общим «Изменение плана».
- **Цитата шага:**
  - `RoomCubit.setPendingQuotedPlanStep(stepId, seq, {cantMake})` (зеркало `room_cubit.dart:440-462`);
  - передача в `sendMessage` (`:1121-1213`);
  - chip «Шаг: {step}» в composer (`basic_chat_body.dart:~1592`);
  - `room_message_plan_step_quote.dart` по образцу `RoomMessageFactQuote`;
  - цитата живая: «изменён», если `contentSeq > quotedSeq`; «шаг удалён», если шаг удалён.
- **Realtime paint INSERT** для строк плана и цитат: `room_message_snapshot_lookup.dart:40-59`, `realtime_room_message_paint.dart`. Склейка 14 и зачёркивание идут через refetch.

### 5.11 Копирование (клиент)

- `runBeaconCreateFromAction` (`beacon_lineage_overflow_actions.dart:12-19`) и `BeaconViewCubit.forkFromThis` (`beacon_view_cubit.dart:375-386`). Если у источника есть план, зритель может его читать и `kPlanEnabled`, сначала открывается `plan_copy_sheet.dart`. Иначе fork идёт как сейчас.
- **Состав листа:**
  - заголовок «ПЛАН · {n} шагов»;
  - якорь: дата и время начала **первого шага со временем**; если таких шагов нет, picker скрыт и показан текст «В плане нет шагов со временем»;
  - подпись сдвига со знаком и pluralization («все шаги сдвинутся на +7 дней / −1 день»);
  - предпросмотр «было: X»;
  - кнопки «Продолжить» и «Без плана».
- **Сдвиг:** `deltaDays` = разница календарных дат якоря, `deltaMinutes` = разница времени суток якоря. Каждый шаг со временем: `DateTime(y, m, d + deltaDays, h, min + deltaMinutes)` в локальной зоне. Так сохраняются интервалы и длительности, и на границе DST 08:30 остаётся 08:30.
- Затем `fork(copyPlan, planStepTimes)` и существующая навигация в draft (`beacon_lineage_fork_navigation.dart:12-15`).
- **В редакторе draft** есть секция плана (`plan_edit_sheet` с draft-гейтом). «Позвать» — preselect в embedded forward (`beacon_create_screen.dart:213-226`) или `ForwardBeaconRoute(beaconId)` после публикации.
- **Общий util `toWireUtcIso`:** вынести `scheduleDateTimeToIso` из `beacon_repository.dart:46` и убрать дубль `beacon_hierarchy_repository.dart:34`.

### 5.12 l10n (en / ru; ru канонический, на «вы», родо-нейтральный)

**HUD**

| Key | en | ru |
|---|---|---|
| `beaconHudNowLabel` (существует) — подпись NOW-строки (Q6) | NOW | СЕЙЧАС |
| `beaconHudYouLabel` (существует) — без изменений (Q10) | YOU | ВЫ |
| `beaconHudNextLabel` | NEXT | ДАЛЬШЕ |
| `beaconHudByPlanLabel` | BY PLAN | ПО ПЛАНУ |
| `beaconHudFreeUntil` | Free until {time} | Вы свободны до {time} |
| `beaconHudInDuration` | in {duration} | через {duration} |
| `beaconHudAlsoRunning` | also running | тоже идёт |
| `beaconHudOverdueBy` | +{duration} | +{duration} |
| `beaconHudDueBy` | was due by {time} | нужно было к {time} |
| `beaconHudNowByPlan` | by plan · step {n}/{total} | по плану · шаг {n}/{total} |
| `beaconHudNowPlanLine` | {time} {assignee}: {title} | {time} {assignee}: {title} |
| `beaconHudNowPlanLineUnassigned` | {time} {title} · no assignee | {time} {title} · нет исполнителя |
| `beaconHudPlanCounter` | plan {done}/{total} | план {done}/{total} |
| `beaconHudPlanOverdueCounter` | ⏰ {count} | ⏰ {count} |
| `beaconHudCounterPlan` (semantics) | Plan: {done} of {total} steps done | План: выполнено {done} из {total} |
| `beaconHudCounterPlanOverdue` (semantics) | Your overdue steps: {count} | Ваших просроченных шагов: {count} |
| `planChangeOne` | {actor} · {when}: «{step}» {change} | {actor} · {when}: «{step}» {change} |
| `planChangeMany` | {actor} · {when}: {count, plural, one{# of your steps} other{# of your steps}} changed | {actor} · {when}: изменено ваших шагов: {count} |
| `planChangeMoved` | {from} → {to} | {from} → {to} |
| `planChangeAssignedToYou` | assigned to you | назначен на вас |
| `planChangeHandedTo` | handed to {name} | передан: {name} |
| `planChangeRemoved` | removed | удалён |
| `planChangeRenamed` | renamed | переименован |

**Вкладка, список, матрица**

| Key | en | ru |
|---|---|---|
| `labelBeaconTabPlan` | Plan | План |
| `planHeader` | Plan · {done}/{total} · edited by {name}, {when} | План · {done}/{total} · правка: {name}, {when} |
| `planFilterAll` | All | Все |
| `planFilterMine` | Mine | Мои |
| `planFilterUnassigned` | No assignee | Нет исполнителя |
| `planViewList` | List | Список |
| `planViewPeople` | By people | По людям |
| `planHistoryAction` | History | История |
| `planNowLineLabel` | {time} now | {time} сейчас |
| `planNoAssignee` | no assignee | нет исполнителя |
| `planFormerAssignee` | was: {name} | было: {name} |
| `planInvite` | Invite | Позвать |
| `planUntimed` / `planUntimedSemantics` | — / no time | — / без времени |
| `planEndOnly` | by {time} | до {time} |
| `planDoneBy` | marked by {name} | отметка: {name} |
| `planAwaitingAck` | awaiting confirmation: {name} | ждёт подтверждения: {name} |
| `planEmptyTitle` | No plan yet. | Плана пока нет. |
| `planEmptyBody` | Write down who does what and when, and everyone will see their step. | Распишите, кто что делает и когда, и каждый увидит свой шаг. |
| `planEmptyCta` (новый; `itemsTabCreatePlanCta` не трогаем, X1) | Create plan | Составить план |
| `planEmptyHistoryLink` | Plan history › | История плана › |
| `planMatrixUnassignedRow` | No assignee | Нет исполнителя |
| `planMatrixUntimedColumn` | No time | Без времени |
| `planMatrixPrevDay` / `planMatrixNextDay` | Previous day / Next day | Предыдущий день / Следующий день |
| `planMatrixOpenEnd` / `planMatrixOpenStart` (semantics) | no end time / no start time | без времени конца / без времени начала |
| `planStepCheckboxDone` (semantics) | Mark done: {step} | Отметить выполненным: {step} |
| `planStepCheckboxUndone` (semantics) | Unmark: {step} | Снять отметку: {step} |
| `planStepOverdueSemantics` | Overdue: {step} | Просрочено: {step} |

**Действия и карточка шага**

| Key | en | ru |
|---|---|---|
| `planActionDone` | Done | Готово |
| `planActionUndone` | Unmark | Снять отметку |
| `planActionCantMake` | Can't make it | Не успеваю |
| `planActionAck` (Q11) | Got it | Понятно |
| `planActionReschedule` | Move | Перенести |
| `planCantMakeReschedule` | Move to… | Перенести на… |
| `planCantMakeHandover` | Hand over to someone | Передать другому |
| `planCantMakeChat` | Write in the discussion | Написать в обсуждении |
| `planStepMenuHandover` / `planStepMenuEdit` / `planStepMenuDelete` | Hand over / Edit / Delete step | Передать / Изменить / Удалить шаг |
| `planStepDeleteConfirmTitle` | Delete «{step}»? | Удалить шаг «{step}»? |
| `planStepDeleteConfirmBody` | The step leaves the plan; you can bring it back from history. | Шаг исчезнет из плана, его можно вернуть из истории. |
| `planStepOf` | Step {n} of {total} | Шаг {n} из {total} |
| `planStepLate` | late by {duration} | опаздывает на {duration} |
| `planStepAcked` | Change confirmed: ✓ {time} | Изменение подтверждено: ✓ {time} |
| `planStepNotAcked` | Change not confirmed yet | Изменение ещё не подтверждено |
| `planDiscuss` | Discuss › | Обсудить › |
| `planHandoverPickerTitle` | Hand over to | Кому передать |

**Редактор, слияние, конфликт**

| Key | en | ru |
|---|---|---|
| `planEditTitle` | Edit plan | Правка плана |
| `planEditSave` | Save | Сохранить |
| `planEditAddStep` | Add step | Добавить шаг |
| `planEditDeleteStep` | Delete step | Удалить шаг |
| `planEditReorderHandle` (semantics) | Drag to reorder | Перетащить шаг |
| `planEditComment` | What changed (optional) | Что изменилось (необязательно) |
| `planFieldTitle` / `planFieldDescription` | What to do / Details | Что сделать / Подробности |
| `planFieldAssignee` / `planFieldNoAssignee` | Assignee / No assignee | Исполнитель / Без исполнителя |
| `planAssigneePickerTitle` | Who does this step | Кто выполняет шаг |
| `planFieldStart` / `planFieldEnd` / `planFieldClearTime` | Start / End / No time | Начало / Конец / Без времени |
| `planDiscardTitle` / `planDiscardBody` | Discard changes? / Unsaved edits will be lost. | Отменить изменения? / Несохранённые правки пропадут. |
| `planDiscardConfirm` / `planDiscardKeep` | Discard / Keep editing | Отменить правки / Продолжить правку |
| `planValidationTitleRequired` | Write what to do | Напишите, что сделать |
| `planValidationEndBeforeStart` | End is before start | Конец раньше начала |
| `planValidationTooManySteps` | At most 100 steps | Не больше 100 шагов |
| `planValidationTooLong` | At most {max} characters | Не длиннее {max} символов |
| `planMerged` | {count} steps changed meanwhile ({names}) — merged | Пока вы правили, изменено шагов: {count} ({names}). Объединили |
| `planConflictTitle` | The same step was changed at the same time | Этот же шаг изменили одновременно с вами |
| `planConflictMine` / `planConflictTheirs` | My version / Their version | Моя версия / Их версия |

**История**

| Key | en | ru |
|---|---|---|
| `planHistoryTitle` | Plan history | История плана |
| `planHistoryRestore` | Restore this version | Вернуть эту версию |
| `planHistoryCurrent` | Current | Текущая |
| `planHistoryCreated` | {name} created the plan | {name}: план составлен |
| `planHistoryEdited` | {name} edited the plan | {name}: правка |
| `planHistoryRestored` | {name} restored version {seq} | {name}: возврат к версии {seq} |
| `planHistoryCopied` / `planHistoryCopiedUnknown` | Copied from «{title}» / Copied from another request | Скопирован из «{title}» / Скопирован из другого запроса |
| `planHistoryCantMake` | {name} can't make it | {name}: не успевает |
| `planHistoryCantMakeChat` | {name} can't make it — message in the discussion | {name}: не успевает — сообщение в обсуждении |
| `planHistoryAutoAssigned` | Steps assigned to {name} after joining | Шаги назначены: {name} (после допуска) |
| `planHistoryUnassignedOnLeave` | {name} left — steps have no assignee | {name} больше не участвует — шаги без исполнителя |
| `planHistoryUndoBanner` / `planHistoryUndo` | Version {seq} restored / Undo | Версия {seq} возвращена / Отменить |
| `planOpAdded` / `planOpRemoved` | + {step} / – {step} | + {step} / – {step} |
| `planOpRetitled` / `planOpRedescribed` | ~ {from} → {to} / {step}: details changed | ~ {from} → {to} / {step}: изменены подробности |
| `planOpRetimed` / `planOpReassigned` | {step}: {from} → {to} | {step}: {from} → {to} |
| `planOpMoved` | {step}: moved | {step}: новое место в плане |

**Чат**

| Key | en | ru |
|---|---|---|
| `planLineRevised` | {name} changed the plan | Правка плана: {name} |
| `planLineRestored` | {name} restored version {seq} | {name}: возврат к версии {seq} |
| `planLineAutoAssigned` | Steps assigned to {name} | Шаги назначены: {name} |
| `planLineUnassigned` | {name} left — {count} steps have no assignee | {name} больше не участвует — шагов без исполнителя: {count} |
| `planLineMore` | {count} more | ещё {count} |
| `planLineHistory` | History › | История › |
| `planLineDoneOwn` | ✓ {name}: {step} | ✓ {name}: {step} |
| `planLineDoneFor` | ✓ {actor} for {assignee}: {step} | ✓ {actor} за {assignee}: {step} |
| `planLineDoneMany` | ✓ {count, plural, one{# step done} other{# steps done}} | ✓ {count, plural, one{# шаг выполнен} few{# шага выполнено} many{# шагов выполнено} other{# шага выполнено}} |
| `planLineTickUndone` | unmarked | отметка снята |
| `planLineCantMakeMoved` | ⏰ {name} can't make it: {step} → moved to {time} | ⏰ Не успевает: {name}. {step} → перенос на {time} |
| `planLineCantMakeHanded` | ⏰ {name} can't make it: {step} → handed to {to} | ⏰ Не успевает: {name}. {step} → передано: {to} |
| `planLineCopied` / `planLineCopiedUnknown` | Plan copied from «{title}» / Plan copied from another request | План скопирован из «{title}» / План скопирован из другого запроса |
| `planLineFallback` | Plan changed | Изменение плана |
| `planQuoteChip` | Step: {step} | Шаг: {step} |
| `planQuoteChanged` / `planQuoteRemoved` | changed / step removed | изменён / шаг удалён |

**Ошибки**

| Key | en | ru |
|---|---|---|
| `planErrorConflict` | Someone changed the same step — choose a version | Этот шаг уже изменили — выберите версию |
| `planErrorStepNotFound` | Step not found — the plan was updated | Шаг не найден — план обновлён |
| `planErrorNotEditable` | The plan can't be changed now | План сейчас нельзя менять |
| `planErrorActionStale` | The plan changed — open the step again | План изменился — откройте шаг заново |
| `planErrorRestoreSourceMissing` | This version is unavailable | Эта версия недоступна |
| `planErrorRateLimited` | Too many edits in a row — try again in a minute | Слишком много правок подряд — попробуйте через минуту |
| `planErrorAssigneeNotAdmitted` | This person isn't in the request | Этот человек не участвует в запросе |
| `planErrorTooLarge` | A plan can have at most 100 steps | В плане не больше 100 шагов |
| `planErrorTickFailed` | Couldn't mark the step. Try again | Не удалось отметить шаг. Попробуйте ещё раз |
| `planDeletedUser` | deleted member | удалённый участник |

**Копия**

| Key | en | ru |
|---|---|---|
| `planCopyHeader` | PLAN · {count, plural, one{# step} other{# steps}} | ПЛАН · {count, plural, one{# шаг} few{# шага} many{# шагов} other{# шага}} |
| `planCopyStartLabel` | First timed step starts | Начало первого шага со временем |
| `planCopyShift` | all steps shift by {sign}{days, plural, one{# day} other{# days}} | все шаги сдвинутся на {sign}{days, plural, one{# день} few{# дня} many{# дней} other{# дня}} |
| `planCopyNoTimes` | No timed steps — nothing to schedule | В плане нет шагов со временем — время задавать не нужно |
| `planCopyConfirm` / `planCopyWithoutPlan` | Continue / Without plan | Продолжить / Без плана |

**Push и email** (серверная копия en/ru, без абсолютного времени, K16; для email тема = заголовок, тело + «Открыть шаг»)

| Event | en | ru |
|---|---|---|
| `planStepReminder` | In 15 min: {step} · {description} | Через 15 мин: {step} · {description} |
| `planStepDue` | Your step has started: {step} · {remaining} left | Ваш шаг начался: {step} · ещё {remaining} |
| `planStepTurn` | {prev} is done. Your step: {step} | Выполнено: {prev}. Теперь ваш шаг: {step} |
| `planChangePending` (один) | {actor}: your step «{step}» {changeRel} | {actor}: ваш шаг «{step}» {changeRel} |
| `planChangePending` (много) | {actor} changed {count} of your steps | {actor}: изменено ваших шагов: {count} |
| `planChangePending` (назначен / автоназначен) | {actor} assigned you «{step}» / You were assigned «{step}» | {actor}: на вас назначен шаг «{step}» / На вас назначен шаг «{step}» |
| `planChangePending` (передан / удалён) | {actor}: «{step}» handed to {to} / «{step}» removed | {actor}: шаг «{step}» передан: {to} / шаг «{step}» удалён |
| `changeRel` | moved by {sign}{duration} / renamed / time cleared | перенесён на {sign}{duration} / переименован / время снято |
| `planStepOverdue` | Overdue: {step} | Просрочено: {step} |
| `planStepLate` | Step is 30 min late: {step} ({name}) | Шаг опаздывает на 30 мин: {step} ({name}) |
| `planCantMake` | {name} can't make it: {step} · «{excerpt}» | Не успевает: {name} — {step} · «{excerpt}» |
| `planStepUnassigned` (ушёл / начался без исполнителя) | {name} left — «{step}» has no assignee / Step started with no assignee: {step} | {name} больше не участвует — шаг «{step}» без исполнителя / Начался шаг без исполнителя: {step} |
| `planEdited` (in-app) | {name} changed the plan | Правка плана: {name} |
| `planStepDone` (in-app) | ✓ {step} ({name}) | ✓ {step} ({name}) |
| `obligationEnded` (plan) | «{step}» was marked done by {name} | Шаг «{step}» выполнен — отметка: {name} |
| Кнопки push | Done / Got it / Open | Готово / Понятно / Открыть |
| Ответ на кнопку | Marked: {step} / Confirmed / Didn't work — open the step | Отмечено: {step} / Подтверждено / Не получилось — откройте шаг |

**Переименования NOW-«плана»** (unit C0; wire-значения не меняются)

| Key | Было (ru) | Станет (ru) | Станет (en) |
|---|---|---|---|
| `beaconRoomActionUpdatePlan` | Обновить план… | Изменить следующий шаг… | Edit next step… |
| `beaconRoomActionUpdatePlanFromMessage` | Обновить план из сообщения… | Следующий шаг из сообщения… | Next step from message… |
| `beaconRoomSemanticPlan` | План | Следующий шаг | Next step |
| `beaconActivityPlanUpdated` | План обновлён | Следующий шаг обновлён | Next step updated |
| `updatesFallbackTitleCoordinationChanged` | План обновлён | Следующий шаг обновлён | Next step updated |
| `beaconHudYouAuthorIdle` | Автор · обновите план при необходимости | Автор · обновите следующий шаг при необходимости | Author · update the next step if needed |
| `beaconRoomActionJumpToPlan` | Перейти к плану | Перейти к следующему шагу | Go to next step |
| `beaconRoomPlanAnnounceLine` / `…WithTitle` | {author} обновил(а) план | Следующий шаг обновлён: {author} | {author} updated the next step |
| `beaconPhaseCoordinating` (en) | — | — | Coordinating |
| `coordinationPlan*`, `coordinationPlanStepCardLabel`, `coordinationSemanticPlanStepResolved` (legacy kind 1) | «Шаг плана…» | удалить, если нет использований; иначе «Пункт (устар.)…»; окончательно в X1 | — |

- Подпись NOW-строки по умолчанию переходит с `beaconHudStepLabel` («ШАГ») на `beaconHudNowLabel` («СЕЙЧАС») по ответу на Q6. Это C0.
- `.cursor/rules/terminology.mdc` получает: План / шаг плана / Понятно / Не успеваю / Дальше / «обсуждение» вместо «чат».
- `now_line_terminology_test.dart` сканирует **все** ru/en значения на «план» / «plan» с allowlist ключей фичи План (`plan*`, `labelBeaconTabPlan`, `beaconHud*Plan*`).

---

## 6. Units

**Правила для каждого unit:** `docs/plans/post-implementation-steps.md` §0 и baton §3 (`baton-who-takes-it-plan.md:190-215`).
- Тесты пишутся первыми и падают по ожидаемой причине.
- Одна новая миграция на unit. Номер берётся при merge, отгруженные миграции не редактируются.
- pg-тесты с `TENTURA_PG_TESTS_REQUIRED=1`. Все тесты последовательно и через `scripts/run_with_test_cleanup.sh`.
- Custom lints не выше baseline; `scripts/check-analyze-baseline.sh` для обоих пакетов (`pipeline.yml:132, 173`); import-gate `! rg package:tentura_server/data/ lib/domain` (`pipeline.yml:134-136`); `scripts/check-doc-drift.sh`.
- UI только через skill `material-3-flutter`.
- **Клиентский PR (definition of done):** bump semver в `packages/client/pubspec.yaml`, `web/index.html ?v=` и `kDefaultMinClientVersion` = версия pubspec (K20). Перепроверяется при merge, потому что main параллельно занимает версии (ср. `83d8715`).
- Один коммит `feat(plan): <unit> <title>` (или `tentura-<bead>.<n>: <unit>: <title>` через alloy).

**Старт:** `git fetch`, ветвление от `origin/main` (≥ `c93331f`). HUD и baton уже на main. Зависимости ниже только внутренние. Каждая строка карты — отдельный PR, который можно смержить и откатить сам по себе.

### 6.1 Карта

| PR | Unit(ы) | Название | Зависит от | Пакет |
|---|---|---|---|---|
| 0 | N6 | Убрать legacy «Mark done» у живых обязательств (существующий баг) | — | client |
| 1 | X0 | Аудит prod/dev; доки (request-attention §1/§5/§10, ADR 0004, terminology); макеты и этот план в `docs/plans/` | — | docs |
| 2 | C0 | Переименование NOW-«плана», подпись NOW (Q6), сканирующий тест | — (Q6 для подписи) | client+server |
| 3 | S2 | `tentura_root`: Snapshot / Diff / Merge / Schedule / EffectiveNow; тесты в `packages/server/test/domain/plan/` | — | root+server tests |
| 4 | S1 | Схема m0223 + realtime publisher + контракт (сервер и клиентский enum) | X0 (аудит записан) | server+client |
| 5 | S3 | Серверный домен: entities, outcome, exceptions 1330+ (литералы), port, `PlanWriteEffects`, `PlanAssigneePolicy`, consts (markers 13..16, system kind 5, activity 21..24), маппинг превью, Log-предикат, клиентские mirrors, env `PLAN_ENABLED` | S2 | server+client mirrors |
| 6 | S4 | `BeaconPlanCase` read + save + restore (repo, ревизии, ledger, P8) | S1, S3 | server |
| 7 | S5, S6, S7 | Tick/untick + склейка; ack + «Не успеваю» (reschedule/handover); строки чата и activity как реализация `PlanWriteEffects` | S4 | server |
| 8 | N1 | Attention event types (рецепт B3), email-правила, относительная копия | X0 **одобрен (Q8)**, S3 | server+client mirror |
| 9 | N2 | Scope `planAssignee` (`m02xx_plan_scope`) + фильтр For You + pg-тесты | S1, N1 | server |
| 10 | N3, N5 | `PlanObligationReconciler` как реализация effects; хуки close/review/reopen/remove/withdraw/block/erasure; scrub; Reset counters | N1, N2, S4..S7 | server |
| 11 | N4 | `PlanStepSweepCase` | N3 | server |
| 12 | S8, C1 | GraphQL V2 + `planSliceJson`; клиентский data layer, флаг, инвалидация | S4..S7, N3 | server+client |
| 13 | C2, C3 | Деривации (ВЫ-слоты, slice, тикер); вкладка Plan: список, фильтры, линия «сейчас», галка, пустое состояние, расширение lint | C1, S2 | client |
| 14 | C4, C5, C6 | Карточка шага + «Не успеваю»; редактор + слияние/конфликт + дата-время; история + restore | C3, S6 | client |
| 15 | C7 | Матрица «люди × время» | C3 | client |
| 16 | C8, C9, C11 | HUD; My Work + inbox NOW + участниковая карточка; Updates copy, destination, deep link | C2, C3, N2, N3, N1 | client |
| 17 | S9, C10 | Цитата шага (`m02yy_plan_quote`), cant_make через сообщение; строки плана в чате | S1, S6, S7, C1 | server+client |
| 18 | K1..K4 | Fork копирует план (одна транзакция); автоназначение + покрытие писателей допуска + backstop; `publishDraft` (обе ветки); клиентский лист копии и секция в draft | S4, S7, N3, C5 | both |
| 19 | P1, P2 | Push payload, TTL / Urgency, обход батча, per-step tag; токен + endpoint + **Caddy** | N1, S5, S6 | server+infra |
| 20 | P3 | Service worker actions + in-app баннер `onMessage` | P2 (Caddy уже выкачен) | server+client |
| 21 | V | Релиз: оба флага, доки, полные проверки, ручной smoke | всё, кроме X1/X2 | manual |
| 22 | X1 | Чистка мёртвого coordination-кода, Drift `creatorId`, legacy-строки l10n | V | both |
| 23 | X2 | Legacy kind=1: миграция по итогам аудита | X0 | server |

**Критический путь:** X0 → S1 → S3 → S4 → (S5..S7) → N1 (после Q8) → N2 → N3 → S8+C1 → C2/C3 → C8/C9 → V.

**Сразу параллельно:** N6, C0, S2. K*, P* идут после своих зависимостей.

### 6.2 Units подробно

**N6 — Legacy «Mark done».**
- Файлы: `updates_feed_tile.dart:181-188`, `updates_feed_pane.dart:346-359`, `activity_stream_view.dart:1131-1133`, `attention_receipt.dart:100` (`isUserSettleable = false` для обязательств).
- Тесты: виджет-тест — у живого обязательства нет «Mark done»; у optional кнопка остаётся.

**X0 — Аудит и доки.**
- Аудит: SQL из §3.0, результаты (dev и prod) в issue #220, не в репозитории.
- Доки:
  - `docs/features/request-attention.md`: §1 (ветка `planAssignee`), §5 (подтверждение как доменный акт; «Готово» шага — доменный переход), §10 (фильтр plan-типов из For You);
  - `docs/adr/0004-beacon-lineage-fork.md`: поправка о копии плана под гейтом K2 и о названии источника по id;
  - `.cursor/rules/terminology.mdc`;
  - пометка «superseded» на `my-desk-obligation-subcards-plan.md` D-SC4/D-SC6;
  - **коммит макетов и этого плана** в `docs/plans/plan-220-mockups.md` и `docs/plans/plan-220-libretto-plan.md` с правками из раздела «Перепроверка».
- Тесты: `bash scripts/check-doc-drift.sh`, `scripts/check-user-facing-terminology.sh`.
- Готово, когда владелец одобрил правки §5 (Q8) и ответил на Q6/Q10/Q11 или явно принял defaults.

**C0 — Переименование NOW-«плана».**
- Файлы:
  - `RoomCubit.updatePlan` → `updateNowLine`; `canUpdatePlan` / `isPlanEditor` → `canEditNowLine` / `isNowLineEditor` (`room_cubit.dart:140-156, 966-987`, `room_state.dart:83-98`);
  - `RoomCapabilities.plan` → `nowLine`; `showBeaconRoomUpdatePlanSheet`; `beaconViewRoomUpdatePlanAction`;
  - все ключи из таблицы переименований §5.12; подпись NOW-строки (Q6);
  - сервер: текст ошибки `beacon_room_case.dart:706-711`.
- Тесты:
  - существующие тесты комнаты и HUD зелёные после переименования;
  - `arb_l10n_consistency_test.dart`;
  - новый `test/l10n/now_line_terminology_test.dart`: сканирование всех ru/en значений с allowlist.
- Клиентский bump версии.

**S2 — Общий домен.**
- Файлы: `/home/user/tentura/lib/domain/plan/{plan_snapshot,plan_diff,plan_merge,plan_schedule}.dart`.
- Тесты в `packages/server/test/domain/plan/` (K19):
  - законы слияния: `merge(b, b, y) = y`, `merge(b, x, b) = x`, непересекающиеся правки коммутируют;
  - одинаковая правка с обеих сторон — не конфликт; правка против удаления — конфликт; удаление против удаления — нет;
  - мой перенос плюс их правка; оба переставили один шаг → `theirs`; мой новый шаг после предшественника;
  - `currentStepFor`: шаг со временем; шаг без времени (предшественник отмечен / не отмечен / первый); шаг только с концом (P18); просроченный ранний шаг раньше наступившего позднего; `alsoActive` (P19);
  - `effectiveNow`: ручная запись позже прибытия; прибытие позже ручной; перенос в будущее; удаление; ничья по времени; отмеченный до старта; reviewOpen; шаг без исполнителя; нумерация `index`;
  - `overdueBoundary`: с концом, без конца, только конец, без времени.

**S1 — Схема m0223.**
- Файлы:
  - `packages/server/lib/data/database/migration/m0223.dart`, `_migrations.dart`, `table/coordination_items.dart` (только колонки);
  - `docs/contracts/realtime-entity-contract.json`;
  - набор publishers в `packages/server/test/architecture/realtime_entity_contract_test.dart`;
  - клиентский `RealtimeEntityKind.beaconPlan` + `fromWire`.
- Тесты `test/data/database/m0222_plan_steps_pg_test.dart`:
  - путь обновления с `0220`, строки kind=1 сохраняются;
  - guard падает при kind 2 и при kind 4;
  - CHECKs: `end < start`, kind 6 со статусом 2, kind 6 без `created_seq`, plan-колонки на kind 1;
  - `UNIQUE(beacon_id, seq)`;
  - удаление beacon каскадно сносит план, ревизии и шаги;
  - стирание исполнителя → `target = NULL`; стирание `done_by` и `former` → NULL **без нарушения CHECK** (при `former_reason` ≠ NULL);
  - kind 1 даёт NOTIFY `coordination_item` на INSERT, UPDATE и DELETE, kind 6 не даёт ни на одном (`PgNotificationRecorder.drain`);
  - UPDATE `beacon_plan` даёт `beacon_plan` автору, участникам `room_access = 3` и stewards, а не-участникам не даёт.
- Плюс оба `realtime_entity_contract_test` (сервер и клиент).

**S3 — Серверный домен и общие константы.**
- Файлы: §4.2 (entities, outcome, exceptions, policy, ports, consts, env); `_previewKindForSemanticMarker` (`coordination_item_repository.dart:1689-1704`; 13/15/16 → 2, 14 → 7); `isCoordinationLogEventType` + клиентский mirror; клиентские mirrors markers, system kind 5, activity 21..24, кодов 1330+.
- Тесты:
  - `test/domain/entity/beacon_plan_test.dart`;
  - литеральные значения каждого нового кода (1330..1338);
  - client/server mirror-тесты markers, activity и кодов;
  - `beaconThreads` с хвостовой строкой marker 13..16 не бросает, превью 2/7;
  - клиентский forward-compat: `RoomMessage` с `systemMessageKind = 5` и marker 13..16, `BeaconActivityEvent` 21..24 не бросают;
  - `PlanAssigneePolicy`: автор и steward допустимы, недопущенный и `block_hides` — нет, сам себе — нет;
  - `PLAN_ENABLED=false` → `planDisabled`.

**S4 — Read + save + restore.**
- Файлы: `beacon_plan_repository_port.dart`, `beacon_plan_repository.dart`, `beacon_plan_case.dart` (§4.4).
- Тесты `test/domain/use_case/beacon_plan_save_pg_test.dart`:
  - первое сохранение даёт seq 1 `created`;
  - два соединения с одинаковым base и разными шагами → Applied + Merged;
  - один шаг с двух сторон → Applied + Conflict(currentSeq, [id]) без записи;
  - одинаковое содержимое → NoOp;
  - удалённый шаг получает status 3 и `removed_seq`;
  - restore оживляет шаг с прежней галкой; restore с недопущенным исполнителем даёт «было: X» с reason 2; restore на устаревшем base → Conflict;
  - outsider, closed и draft без гейта → `planNotEditable`; в reviewOpen работает;
  - **гонка с закрытием:** save, параллельный close, ни одного живого plan-обязательства на закрытом запросе;
  - rate limit; лимит 100 шагов; чужой или битый id шага отклоняется; исполнитель вне `PlanAssigneePolicy` → `planAssigneeNotAdmitted`;
  - `pending_from_seq` ставится затронутым, но не актору; `redescribed` pending не ставит;
  - `change_seq` растёт на каждой записи;
  - `PlanWriteEffects.afterWrite` вызван ровно один раз на запись (fake).

**S5, S6, S7 — Tick, ack / «Не успеваю», строки чата.**
- Тесты `beacon_plan_tick_pg_test.dart`:
  - отметка не меняет `revision_seq` и `content_seq`; повтор идемпотентен;
  - отметка не-исполнителем пишет `done_by = actor`;
  - отметка → сообщение → отметка даёт 2 строки; три отметки подряд — 1 строку с 3 ticks; старше 30 мин — новую строку;
  - 10 параллельных отметок дают одну строку (P8);
  - снятие отметки помечает `undoneAt` и не удаляет строку;
  - на закрытом запросе → `planNotEditable`.
- Тесты `beacon_plan_ack_cant_make_pg_test.dart`:
  - ack до head снимает pending; ack до старого seq при более новом изменении оставляет pending;
  - reschedule даёт ревизию `cant_make` и одну строку 15 без строки 13;
  - handover автору разрешён; недопущенному или себе → ошибка; pending ставится новому исполнителю, а не актору;
  - любой вариант снимает pending актора.
- Тесты `beacon_plan_room_lines_pg_test.dart`:
  - строки имеют `system_message_kind = 5`, `author_id = actor`, ключи payload как в §4.8;
  - запись разрешена в reviewOpen;
  - строки переживают стирание актора;
  - строки **не** двигают `beacon.last_activity_at`;
  - `changes` ограничены 20 + `changeCount`;
  - строки для `auto_assigned` и `unassigned_on_leave` пишутся;
  - ни один `beacon_room_message.linked_item_id` не ссылается на kind 6.

**N1 — Event types.**
- Файлы:
  - §4.6 по рецепту B3 (коммит `cae5dd0c` на main);
  - `logicalTaskKey` для трёх обязательств;
  - ветка ambient в `_category` и `categoryOf` в паре;
  - `obligationEnded` остаётся unblocksMe + запись producer;
  - `kNoImmediateEmailKinds` в `EmailNotificationService.considerImmediate` и исключение тех же kinds из дайджеста;
  - копия en/ru без абсолютного времени.
- Тесты:
  - `test/domain/attention/plan_attention_policy_test.dart`: класс, категория, placement (reminder и overdue = primary), `channelEligible` и ключ для каждого типа; категории receipt и push совпадают;
  - `plan_email_policy_test.dart`: reminder и overdue без immediate и без дайджеста; due и changePending с immediate;
  - копия для пользователя с `tzOffsetMinutes = 0` и без тихих часов не содержит `HH:MM`;
  - `updates_event_contract_test` и `updates_event_coverage_test` (с расширенной областью) на сервере и клиенте;
  - `attention_event_classification_test`.

**N2 — Scope `planAssignee`.**
- Файлы: `m02xx_plan_scope.dart`; фильтр plan-типов в `activity_child_receipts` (`attention_repository.dart:392-405`), `forYouDot` и `forYouSweepEligible`.
- Тесты `test/data/database/plan_assignee_scope_pg_test.dart`:
  - steward-исполнитель без help offer: Request в scope; после отметки **последнего** шага остаётся в scope, пока запрос открыт;
  - закрытый и отменённый запросы выходят из scope;
  - недопущенный исполнитель вне scope;
  - receipts reminder / overdue / закрытого `planStepDue` у steward имеют `surface = myWork` и **учитываются** в индикаторах My Work;
  - после close их нет в `activity_child_receipts`, `forYouDot` и `forYouSweepEligible`;
  - `planEdited` у зрителя вне scope → `activity`;
  - повтор predicate-unification и sweep pg-тестов; inbox tombstone guard (`m0193.dart:1920-1955`).

**N3, N5 — Reconciler и жизненный цикл.**
- Тесты `plan_obligation_pg_test.dart` (реальный dispatch, образец `help_offer_obligation_settlement_pg_test.dart`):
  - один текущий шаг на человека даёт одно `planStepDue`;
  - отметка другим → resolved + `obligationEnded` исполнителю;
  - переназначение → superseded у старого, pending у нового;
  - правка 3 моих шагов → ровно 1 receipt и 1 delivery job;
  - две быстрые правки → 1 pending job (collapse);
  - у `planEdited` / `planStepDone` нет канальной задачи;
  - ack закрывает; отметка открывает `planStepTurn` следующему шагу без начала; снятие отметки его снимает;
  - в reviewOpen новые due/turn не открываются, на reopen открываются;
  - `myDeskCount` включает plan-обязательства и никогда не включает будущие шаги.
- Тесты `plan_lifecycle_pg_test.dart`:
  - `removeFromRoom`, `withdraw` и block дают `target NULL`, `former = X`, `former_reason = 2`, ревизию и строку, superseded-обязательства, автору `planStepUnassigned`;
  - стирание исполнителя даёт то же; scrub чистит шаги, ревизии и payload запросов стёртого автора;
  - close / cancel / delete → все plan-обязательства superseded, запись → `planNotEditable`;
  - Reset counters закрывает осиротевшие plan-обязательства.

**N4 — Sweep.**
- Файлы: `plan_step_sweep_case.dart`, `task_worker_case.dart`.
- Тесты `plan_step_sweep_pg_test.dart` (фиксированные часы):
  - два прохода → одно напоминание; перенос → новый ключ без `StateError`;
  - **название изменено между проходами — без `StateError`, без второго напоминания**;
  - отмеченный шаг пропускается; переназначенный уходит новому исполнителю;
  - просрочка один раз; автору +30 мин один раз; `unassignedDue` автору один раз;
  - шаг, созданный менее чем за 15 мин до старта, без напоминания;
  - draft, reviewOpen, closed и legacy 4 пропускаются;
  - после простоя remind пропускается;
  - битый кандидат не обрывает остальных;
  - тихие часы: receipt есть, push нет; immediate email для reminder нет;
  - выключенный `PLAN_ENABLED` → задача не зарегистрирована.
- Плюс `test/architecture/plan_step_sweep_task_worker_wiring_test.dart`.

**S8 + C1 — GraphQL, slice, клиентский data layer.**
- Файлы сервера: `query_beacon_plan.dart`, `mutation_beacon_plan.dart`, `custom_types.dart`, `_queries_all.dart`, `_mutations_all.dart`, `InboxRoomContextRow.planSliceJson`, `roomMessageCreate` пока без цитаты.
- Файлы клиента: §5.1 data и domain; `kPlanEnabled` (`bool.fromEnvironment`); инвалидация `beaconPlan` → `BeaconRoomEntityType.plan` → точечный refetch и room invalidation.
- Тесты:
  - `mutation_beacon_plan_test.dart`: mocked case, `sub` → актор, аргументы, код 1330 с extensions;
  - `plan_slice_batch_pg_test.dart`: один SQL на 80 beacons, правильные current / alsoActive / next / pending / now; на закрытом запросе только счёт;
  - клиент: `plan_viewer_slice_test.dart` (все формы, неизвестные ключи, битые данные → null);
  - клиент: `beacon_plan_repository_test.dart` (переменные, маппинг, 1330 → `PlanEditConflictException` с id);
  - клиент: invalidation-тест (образец `invalidation_service_room_seen_peer_test.dart`);
  - клиент: `realtime_entity_contract_impacts_test.dart`.
- Клиентский bump версии.

**C2, C3 — Деривации и вкладка.**
- Тесты `beacon_you_plan_slots_test.dart`:
  - каждая ступень лестницы §5.2, кап 3 строки;
  - `pendingAck` при системной строке уходит в ПО ПЛАНУ и не выпадает;
  - overdue → danger; «Вы свободны до»; «тоже идёт».
- Тест тикера с фейковыми часами: перестройка ровно на границе.
- Тесты `beacon_plan_surface_test.dart`:
  - дни в зоне зрителя; линия «сейчас» двигается;
  - [Все ▾] по людям и «Нет исполнителя»; «Мои» приглушает соседей;
  - «было: X»; «ждёт подтверждения»;
  - оптимистичная галка, откат и snackbar;
  - пустое состояние, CTA и ссылка на историю;
  - вкладки скрыты при `kPlanEnabled == false` и в showcase.
- Плюс `beacon_surface_tabs_test.dart` (порядок compact/split, бейдж), тест нормализатора `tab=plan&step=`, lint-тест расширенного пути.

**C4, C5, C6 — Карточка, редактор, история.**
- `plan_step_sheet_test.dart`: поля, статус подтверждения, кнопки по роли, подтверждение удаления.
- `plan_cant_make_sheet_test.dart`:
  - три варианта;
  - handover показывает набор `PlanAssigneePolicy`, включая автора и исключая меня;
  - «обсуждение» открывает composer с цитатой и флагом.
- `plan_edit_cubit_test.dart`: base берётся при открытии и не меняется при realtime; Merged → snackbar с именами; Conflict → resolver → повтор с `currentSeq`; черновик переживает конфликт; диалог отмены.
- `plan_edit_sheet_test.dart`: reorder ручкой, добавление и удаление, «Без времени», валидация, комментарий ≤ 280.
- `plan_datetime_field_test.dart`: на проводе UTC ISO.
- `plan_history_cubit_test.dart`: после restore base = новый head; второй restore и Undo без конфликта; `aroundSeq`.
- `plan_history_sheet_test.dart`: все `kind`, строки + ~ – из `changesJson`, «Вернуть эту версию» только у не-head.

**C7 — Матрица.**
- Тесты `plan_people_matrix_test.dart`:
  - при ширине панели < 600 не рендерится; при ≥ 600 есть переключатель;
  - строки = исполнители + «Нет исполнителя»; блоки на своих часах; шаг только с концом; линия «сейчас»;
  - тап открывает карточку; нет горизонтального overflow страницы;
  - в split рендерится по ширине левой панели.

**C8, C9, C11 — HUD, My Work, Updates.**
- Файлы:
  - HUD: `beacon_hud_pinned_block.dart`, `beacon_hud_metadata_composer.dart`, `beacon_hud_row_lead.dart`, `beacon_hud_derivation.dart`, `buildWhen` у `BeaconNowSurface`;
  - My Work: §5.8;
  - inbox: `inbox_watchlist_row.dart`.
- Тесты HUD — `beacon_hud_plan_rows_test.dart`:
  - макеты 1, 1a–1d с поправками раздела «Перепроверка»;
  - NOW «по плану · шаг n/N» против «{name} · {when}», вариант без исполнителя;
  - счётчик и ⏰ с semantics; при закрытом запросе плана нет.
- Тесты My Work — `my_work_plan_step_rows_test.dart`:
  - изменение первой строкой с [Понятно] [Не успеваю];
  - текущий шаг с описанием, красный только при просрочке;
  - тусклая ДАЛЬШЕ без кнопок и не в счётчике; нет ×;
  - на закрытом запросе строк нет.
- `derive_my_work_cards_test.dart`: будущий шаг → In progress; наступивший → Needs you; `planAssignee` и архив.
- Тест маршрутизации карточки: не-автор не видит Close / Cancel / Edit.
- Тест inbox: NOW из `slice.now`.
- Updates: `updates_receipt_display_copy_test.dart` (fallback для каждого plan-типа en/ru); `destination_map_test.dart` (`beacon_plan_step` → `tab=plan&step=`).
- Плюс `beacon_operational_header_card_test.dart` зелёный.

**S9 + C10 — Цитата и строки чата.**
- Файлы:
  - сервер: `m02yy_plan_quote.dart`, `insertRoomMessage` (`beacon_room_repository.dart:716-801`), batch-обогащение (`:208-250`), `mutation_beacon_room.dart:62-128` (+ `planCantMake`), `RoomMessageRow.quotedPlanStep`;
  - клиент: §5.10.
- Тесты сервера `room_message_plan_quote_pg_test.dart`:
  - шаг чужого запроса → отказ;
  - удалённый шаг → «removed»; drift при `contentSeq > seq`;
  - `planCantMake` от не-исполнителя → отказ; от исполнителя → ревизия `cant_make_chat`, автору `planCantMake` с фрагментом, pending снят;
  - путь обновления.
- Правки `beacon_room_mutation_kind_table_test.dart:231-232` и `general_only_public_contract_test.dart:89-90`.
- Тесты клиента:
  - виджет-тест каждой строки: 1 против 3+ изменений, «ещё N», комментарий, «История ›» открывает seq, своя отметка, «за», склеенная, зачёркнутая, копия с названием и без;
  - `room_cubit_plan_quote_test.dart`: chip → `sendMessage` с id, seq и флагом;
  - цитата «изменён» и «шаг удалён».

**K1..K4 — Копия плана.**
- K1, `beacon_case_fork_plan_pg_test.dart`:
  - автор копирует: шаги без галок, «было: X» с reason 1, `X == caller` назначен сразу, ревизия 1 `copied`;
  - не-участник, видящий запрос, получает fork **без** шагов и имён;
  - заблокированный X не попадает в «было»;
  - `planStepTimes` применяются; `copyPlan = false` → без плана;
  - сбой копии плана откатывает создание beacon (одна транзакция);
  - sweep draft не трогает.
- Плюс расширение `beacon_case_fork_media_test.dart`.
- K2, `plan_auto_assign_pg_test.dart`:
  - допуск X через **каждый** путь (acceptHelpOffer, inviteToRoom, admit, stewardPromote, returnToPostAsAddressee и прочие найденные писатели) назначает его шаги, ставит pending и `planChangePending`;
  - шаг, уже назначенный другому, не трогается;
  - повторный допуск ничего не делает;
  - **удалённый и снова допущенный X не получает шаги** (reason 2);
  - backstop назначает пропущенное.
- Плюс `plan_auto_assign_hook_coverage_test.dart`.
- K3: публикация копии даёт одну строку 16 и reconcile, в том числе через ветку дочернего запроса; публикация без плана — без строки.
- K4, `plan_copy_sheet_test.dart`:
  - +7 дней через границу DST сохраняет 08:30;
  - изменение только времени якоря сдвигает все шаги и сохраняет интервалы;
  - первый шаг без времени → якорь = первый шаг со временем;
  - без шагов со временем picker скрыт;
  - отрицательный сдвиг даёт знак и plural;
  - «Без плана»; лист не показывается, если зритель не может читать план источника;
  - fork вызывается с per-step instants.
- Плюс тест секции плана в draft. Клиентский bump версии.

**P1, P2 — Push payload, endpoint и Caddy.**
- Тесты:
  - `buildFcmMessagePayload`: actions с ru/en заголовками, tag, ttl, Urgency;
  - plan-push не проходит через `FcmBatchQueue`;
  - `push_action_controller_test.dart`: подделанный, просроченный, устаревший seq и закрытый запрос → 4xx; валидный → `setDone` / `ack`, идемпотентно; GET → 405.
- Проверить маршрут в `Caddyfile` и `Caddyfile.local`. Этот PR выкатывается **до** P3.

**P3 — Service worker и баннер.**
- Тест `firebase_sw_controller_test.dart` **структурный**: проверяет строки сгенерированного скрипта. SW JS не исполняется ни одним suite (`firebase_sw_controller.dart:48-50`). Проверяются: передача actions при `maxActions > 0`, ветка `event.action` → fetch POST, fallback-ссылка, tag `plan:`, тексты обратной связи.
- Клиентский тест баннера `onMessage`. Реальная проверка — ручной smoke в V. Клиентский bump версии.

**V — Релиз (manual).**
- `PLAN_ENABLED=true` на dev, затем на prod. Клиентский default `kPlanEnabled = true`. Тройной bump версии. `docs/features/beacon_room.md` получает секцию «План».
- Все suites из `AGENTS.md` § Verify, оба прогона custom-lint, analyze baseline, terminology, doc-drift.
- Smoke на web с тремя QA-пользователями:
  - правка с конфликтом, отметка за другого, «Понятно», все три варианта «Не успеваю»;
  - напоминание (сдвинуть время шага на +16 мин), push-кнопка в Chrome через `/api/v2/push-action`;
  - копия с планом и допуск X; удаление и повторный допуск без автоназначения;
  - проверить, что в For You нет plan-обязательств у steward-исполнителя.

**X1 — Чистка мёртвого кода** (после V).
- Объём:
  - workItems «PR 0» из клиентских находок;
  - серверный dead code `CoordinationItemRepository` (`coordination_item_repository_port.dart:7-190`);
  - `openBlocker*` вместе с клиентскими документами и `open_blocker_id`;
  - `_activePlanParticipantUserIds`;
  - Drift `creatorId` nullable;
  - legacy-ключи `coordinationPlan*` и `itemsTabCreatePlanCta`.
- Тесты: существующие suites зелёные; обновлён `general_only_boundary_inventory_test.dart:64-93`.

**X2 — Legacy kind=1.** Миграция по итогам X0 и pg-тест пути обновления.

---

## 7. Риски и открытые вопросы

### 7.1 Риски

1. **Устаревший локальный checkout.** Ветвление от `f0e27cb` столкнётся с m0220, marker 12, кодами 1322-1329 и новыми HUD-файлами. Ветвиться только от `origin/main` после fetch. Ссылки на строки перепривязать (шапка плана).
2. **Гонка номеров и версий.** Параллельные агенты на main (`9bf2f4b0`, `83d8715`). Номера миграций, markers, кодов (позиционные!), activity-типов, версия клиента и baseline lint берутся при старте и перепроверяются при merge.
3. **Широкий эффект scope (N2).** Расширение `responsibility_scope_base_beacons` двигает surface всех receipts этих запросов и inbox tombstone guard. Нужно повторить predicate-unification и sweep pg-тесты.
4. **Очередь доставки.** Троттлинг 1 push в минуту на аккаунт и последовательный TaskWorker (`task_worker_case.dart:445-456`) могут задержать напоминание на минуты.
5. **Тихие часы.** Push в тихие часы, snooze и mute **отбрасывается** (`notification_preference_gate.dart:41-57`), так что 15-минутное напоминание в эти часы теряется. Письма сразу для напоминания тоже нет (K15). Вопрос Q5.
6. **Платформы push.** Кнопки работают только в Chromium. Видимая вкладка без `onMessage` глотает push, это закрывает P3.
7. **Старые клиенты.** Неизвестные realtime kinds они игнорируют (`invalidation_service.dart:156-161`). Строки плана рисуют как «System» (`room_message_tile.dart:389`). Plan-обязательство появится без CTA, если запись пройдёт до обновления клиента. Это закрывают `PLAN_ENABLED` и минимальная версия, равная текущей (K20). Жёсткий сбой бывает только на неизвестном `ThreadMessagePreviewKind` (`request_thread_model.dart:16-18`), поэтому новых preview kinds нет.
8. **Двойной счёт.** `planStepDue` + `planChangePending` на одном шаге дают 2 в счётчике (принятый default). Если будут жалобы, `planChangePending` по текущему шагу будет заменять (supersede) `planStepDue` до «Понял».
9. **Общая блокировка (P8).** Сохранения, отметки и закрытие ждут друг друга на `lockRequest`. Для человеческого темпа это безопасно, но длинный save со 100 шагами нужно замерить в S4.
10. **Приватность.** User id в JSON-снимках чужих запросов при стирании не вычищаются, показываем «удалённый участник». Названия шагов, которые стёртый человек писал в чужих планах, остаются (§4.11). Гейт копии (K2) обязателен.
11. **Часовые пояса.** У запроса нет своей зоны: участники из разных зон видят разные часы. Push и email говорят только относительным временем (K16). Показ зоны вне v1.
12. **Смысл и подпись NOW-строки.** Макет называет её «СЕЙЧАС», вкладка тоже «Сейчас», а ручная строка по смыслу «следующий шаг». Вопрос Q6.
13. **Подавление напоминания при присутствии.** Правило макета §9 в v1 не работает (Q9). Активную вкладку покрывает баннер `onMessage`.
14. **Тёмный запуск.** Если кто-то включит `PLAN_ENABLED` на prod до V, клиенты увидят обязательства без UI. Флаг меняется только в unit V.

### 7.2 Вопросы владельцу (только существенные)

| # | Вопрос | Рекомендация | Почему |
|---|---|---|---|
| Q1 | ~~Когда шаг «просрочен»?~~ **Решено (Вадим, 5 окт): после конца; без конца — через 15 мин после начала.** | После времени конца; если конца нет, через 15 мин после начала. «+N мин» считать от той же границы | §1c и §4 считают от начала, §9 от конца. «Красный только для просрочки» требует одной границы |
| Q2 | ~~Когда шаг без времени становится текущим?~~ **Решено (Вадим, 5 окт): после выполнения предыдущего (или если он первый).** | Когда выполнен предыдущий шаг плана (или он первый) | Совпадает с «после предыдущего» (§3) и push «теперь ваш» (§9). Буквально §1b делает обязательствами сразу все шаги без времени |
| Q3 | ~~Кто может копировать план с «было: X»?~~ **Решено (Вадим, 5 окт): только автор, впущенные участники и steward источника.** | Только автор источника или его допущенный участник / steward | Fork открыт любому, кто видит запрос. Иначе утекают закрытые шаги и имена, а ADR 0004 запрещает копировать участников |
| Q4 | ~~Исполнитель без предложения помощи: запрос в его My Work?~~ **Принят default (5 окт, Вадим не возражал): да, пока у него есть шаг.** | Да, пока у него есть шаг в открытом запросе | Иначе напоминания и закрытые шаги перетекают в For You, что нарушает правило 4 окт. Меняет request-attention §1 |
| Q5 | ~~Push-кнопки и тихие часы~~ **Решено (Вадим, 5 окт): кнопки там, где поддерживаются, иначе открытие; тихие часы не трогать.** | Кнопки там, где поддерживаются, иначе открытие; тихие часы не трогать | Обход тихих часов — вопрос доверия пользователей |
| Q6 | ~~Подпись NOW~~ **Решено (Вадим, 5 окт): «СЕЙЧАС».** | Как в макете: «СЕЙЧАС» (ключ `beaconHudNowLabel` уже есть) | Решение макета. Конфликт с вкладкой мягче, чем «ШАГ», который путается с шагом плана. Альтернатива — новое слово («ИДЁТ») |
| Q7 | ~~Кто правит план~~ **Решено (Вадим, 4 окт, исходное ТЗ «автор или любой другой участник»): любой допущенный участник.** | Любой допущенный участник; исполнителей защищает «Понял» | Решения 2 и 4 подразумевают открытую правку, но прямо этого не говорят. От ответа зависит, может ли любой отдать шаг другому |
| Q8 | ~~«Понял» как обязательство~~ **Решено (Вадим, 5 окт): да, поправить request-attention §5; рядом всегда «Не успеваю».** | Да. Формулировка: сохранённое подтверждение, которое видит ждущий, есть доменный акт; строка всегда даёт и «Понял», и «Не успеваю» | §11 change control требует одобрения до N1/N3. Без ответа блокируются PR 8+ |
| Q9 | ~~Не напоминать, если человек в запросе~~ **Решено (Вадим, 5 окт): не в v1; на открытой вкладке in-app баннер.** | В v1 нет. Активная вкладка получает in-app баннер; push всё равно приходит | Нужен новый сигнал присутствия (websocket-подписка или свежий `beacon_room_seen`), это отдельная работа |
| Q10 | ~~«ТЫ» или «ВЫ»~~ **Решено (Вадим, 5 окт): «ВЫ».** | «ВЫ» | Приложение везде на «вы» («Просьбы к вам», baton); «ТЫ» осталось бы единственным исключением |
| Q11 | ~~«Понял» или «Понятно»~~ **Решено (Вадим, 5 окт): «Понятно».** | «Понятно» | «Понял» по роду мужское, а копия приложения родо-нейтральная |
| Q12 | ~~Отдельный экран копии или fork~~ **Принято (5 окт, следует из ответа на Q3): существующий fork, без «(копия)».** | Существующий fork и лист плана, без суффикса | Fork уже отгружен, у него есть меню и карточки My Work; второй путь копирования дублировал бы его |

**Файлы.** В этой задаче ничего не создавалось и не менялось. Прочитано: `/mnt/project-files/scenarios/plan-mockups.md`, `/home/user/tentura/docs/plans/baton-who-takes-it-plan.md`, `/home/user/tentura/docs/features/request-attention.md`, `/home/user/tentura/packages/server/lib/data/repository/attention_dismissible_sql.dart`, `/home/user/tentura/packages/server/lib/data/repository/attention_repository.dart`, `/home/user/tentura/packages/client/lib/domain/attention/for_you_stream_entries.dart`. Этот проход сверил по коду: `m0193.dart:5315` (CHECK author_or_system), `m0213.dart:7` (`p_account_id`), `attention_policy.dart:128`, `email_notification_service.dart:52-70`, `notification_preferences_entity.dart:26, 51-55`, `beacon_status.dart:48`, `BeaconRoomStateGet.updatedAt`, `room_message_tile.dart:389, 492`, `beacon_repository.dart:667-672`, `beacon_room_case.dart:1137`. Скретч-копию remote `app_ru.arb` (`/tmp/claude-0/-home-user-tentura/13c147f1-119a-50f4-aa86-6fd90c7ea71d/scratchpad/app_ru_remote.arb`) создал верификатор, а не этот проход.

---

## Перепроверка: что изменилось относительно макетов

- **§10 / решение 9, «копирования запроса нет, новая функция».** Расширяется существующий fork в черновик, отдельного экрана и «(копия)» нет (Q12). `beacon_case.dart:776-842`, `mutation_beacon.dart:149-159`, `app_ru.arb:5564`.
- **§10, «было: X» при любой копии.** Копирует только автор, допущенный участник или steward источника; заблокированные X в «было» не попадают. `beacon_case.dart:783-787`, `docs/adr/0004-beacon-lineage-fork.md:20`.
- **§10, выбор даты и времени первого шага.** Сдвиг = дни + минуты якоря, якорь — первый шаг со временем; без шагов со временем picker скрыт; интервалы и длительности сохраняются. Макет §10 «сохраняются интервалы»; ошибка rev 1 в §5.11.
- **§10, «План скопирован из «…»».** Название показывается, только если зритель может читать источник, иначе «из другого запроса». ADR 0004 Decision 8 (ссылка по id).
- **Решение 9, автоназначение.** Только для «было: X» из копии (`former_reason = 1`). После удаления и повторного допуска шаг не возвращается. `m0193.dart:7808`, §4.10.
- **Решение 9, кто считается допущенным.** Хуки на всех путях допуска, включая steward и адресата Post. `beacon_repository.dart:651-677`, `beacon_room_case.dart:1137`.
- **«Что уже есть», «ВЫ берётся из nextMoveText».** Неверно: у колонки нет писателя, план расширяет лестницу `BeaconYouSituationInput`. `beacon_room_repository.dart:823-839`.
- **«Что уже есть», «как у фактов, если правки не одновременные».** У фактов нет слияния, только CAS. Слияние по шагам пишется заново. `beacon_fact_card_repository.dart:576`.
- **«Что уже есть», «у элементов координации есть исполнитель и время».** Времени, `done_by` и «было» нет, добавляются колонки. `m0193.dart:5435-5459`.
- **§11, «тот же механизм системных строк».** Новые markers 13..16 с `system_message_kind = 5`, а не linked-item. `coordination_item_repository.dart:1689-1704`.
- **§11, строки без автора.** Невозможно из-за CHECK. Автор = актор, kind = 5, строка переживает стирание. `m0193.dart:5315`, `user_erasure_repository.dart:150-160`.
- **§11, какие правки идут в чат.** Автоназначение и снятие исполнителя при уходе тоже пишут строку. Снятая отметка зачёркивается, а не исчезает. Решение D10, §4.8.
- **§1, подпись NOW «СЕЙЧАС».** Сохранена как default через существующий `beaconHudNowLabel`, конфликт с вкладкой вынесен в Q6. `app_ru.arb@main:4298, 6367`.
- **§1, подпись «ТЫ».** Default «ВЫ», как на main (Q10). `app_ru.arb@main:4299`.
- **Копия «Понял», «Твой шаг», «Свободен до», «Что поменял».** Регистр «вы» и нейтральные формы: «Понятно» (Q11), «Ваш шаг», «Вы свободны до», «Что изменилось». `notificationCatAsksOfMe` «Просьбы к вам», `app_ru.arb:2271-2280`.
- **«Написать в чат», «Обсудить в чате».** Заменено на «обсуждение»: «Чат» допустим только как название вкладки. `.cursor/rules/terminology.mdc`.
- **§1c и §4 против §9, от чего считать опоздание.** Одна граница: конец, а без конца начало + 15 мин (Q1). Макет: §1c «должно было быть к 10:00» против §9 «прошло время конца».
- **§1b, шаг без времени текущий сразу.** Становится текущим после выполнения предыдущего (Q2). Шаг только с концом ведёт себя так же. Макет §3 «после предыдущего», §9 «теперь твой».
- **§1c, «любой вариант «Не успеваю» в истории».** Вариант «обсуждение» пишет ревизию-след, только когда сообщение с цитатой отправлено; автор получает уведомление уже с текстом. §4.4.
- **§1a, пример Ивана «Рассмотри 2 предложения».** Рассматривает только автор; пример для участника нужно заменить. `beacon_you_presentation.dart:181-211`.
- **§1a и решение 3, «изменение висит в ТЫ».** Если ВЫ занята системной строкой, изменение показывается в ПО ПЛАНУ и не выпадает при капе 3 строки. §5.2.
- **§2, нумерация «шаг 3/9» против «Шаг 4 из 9».** Одна нумерация по порядку живых шагов. Макет, строки 90-92 против 152.
- **§2, текст NOW «10:00 Иван везёт доски».** Формат «HH:MM {исполнитель}: {название}»: из повелительного названия шага такой текст не выводится. §5.2.
- **§2, «последний пишущий выигрывает».** Время ручной записи = `beacon_room_state.updated_at`; прибытие шага вычисляется при чтении, а не записывается. `beacon_room_case.dart:698-757`, `BeaconRoomStateGet.updatedAt`.
- **§3, «[Все ▾]».** Выпадающий фильтр по людям плюс «Мои». На ширине ≥ 600 переключатель «Список / По людям». §5.3.
- **§3a, матрица от 840 по окну.** Решает ширина панели Plan ≥ 600: в split у вкладки только левая панель. `beacon_view_constants.dart` на main.
- **§3, шаг без исполнителя «автору заметно сразу».** На старте шага автору приходит уведомление; есть вариант NOW «нет исполнителя». §4.5, фаза `unassignedDue`.
- **§3, автор видит, кто подтвердил.** Добавлены пометка «ждёт подтверждения» в списке и «ещё не подтверждено» в карточке. §4.3 `assigneeAckPending`.
- **§4, цитата шага «как у фактов».** Новые колонки цитаты вместо `linked_item_id`. `room_message_snapshot_lookup.dart:33-38`.
- **§5 и решение 7, «Передать другому».** Передать можно и автору, и steward. Своя политика вместо baton. `baton_selection_policy.dart:72-75`.
- **§9, push с временем «до 10:30», «10:00 → 11:00».** Серверная копия только с относительным временем. `notification_preferences_entity.dart:26`, `notification_settings_cubit.dart:82-92`.
- **§9, категория «Просьбы к вам» для напоминания и просрочки.** Без письма сразу и без дайджеста; письмо сразу только для «шаг начался» и «ваш шаг изменён». `email_notification_service.dart:52-70`, `notification_preferences_entity.dart:51-55`.
- **§9, «не напоминать, если человек в запросе».** В v1 не реализуется (Q9): присутствие только глобальное. `packages/server/lib/data/database/table/user_presence.dart:8-25`.
- **§9, напоминание и просрочка в обычной ленте.** Placement `primary`; от For You их держат scope `planAssignee` и явный фильтр. `attention_policy.dart:326-343`, `attention_dismissible_sql.dart:120-135`.
- **§9, «ваш ход» и «шаг отметил другой».** «Ход» = обязательство в «Разблокировки». «Шаг отметил другой» (`obligationEnded`) тоже в «Разблокировки», а не в «Просьбы к вам». `attention_policy.dart:128`.
- **§9, тихие часы.** Push не обходит, ответ за Q5. `notification_preference_gate.dart:41-57`.
- **§9a, кнопки в push везде.** Только Chromium; tag отдельный для каждого шага; заголовки кнопок и ответ на нажатие с сервера. `firebase_sw_controller.dart:51-86`.
- **§9a, строка описания в push и в ВЫ.** Описание добавлено в напоминание, «шаг начался», строку ВЫ и My Work. §5.2, §5.12.
- **§8a, 1d, 9a, «Ольга перенесла 3 мин назад».** Копия изменения содержит актора и «когда». Слияние называет, кто правил. §5.12 `planChangeOne` / `planMerged`.
- **§8, обязательства My Work.** Отдельный блок строк плана; карточка не-автора без авторского меню. `my_work_cards.dart:123-131`.
- **Общий «Готово» в History / Activity.** Убирается для живых обязательств отдельным PR. `attention_receipt.dart:100`, `attention_settlement_case.dart:34-48`.
- **Read-only в review.** Неверно: в `reviewOpen` план правится и отмечается, просто новые «шаг начался» не создаются. `m0193.dart:1195`, `beacon_status.dart:48`.
- **Пустой и удалённый план.** Ноль живых шагов = пустое состояние со ссылкой на историю; отдельного «удалить план» нет. §5.3.
- **Часовой пояс автора рядом со временем.** Убрано: данных о зоне автора нет (#112). `docs/plans/issue-112-timezone-display-and-wire-fix-plan.md`.
- **«Создать план» в пустом состоянии.** Новый ключ `planEmptyCta` «Составить план» вместо мёртвого `itemsTabCreatePlanCta` («Создать план»). `app_ru.arb:4295`.
- **Слово «план» у строки «Следующий шаг».** Переименование расширено на все такие строки, тест сканирует весь arb. `app_ru.arb@main:4340, 5129, 5570-5571`.