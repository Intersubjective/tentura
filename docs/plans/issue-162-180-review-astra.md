---
status: archived
kind: review-record
reviewer: Astra (gpt-6-astra, high reasoning, read-only)
date: 2026-09-17
target: docs/plans/issue-162-180-review-package-state-plan.md
target_revision: 1
outcome: revision 2 issued
---

# Adversarial review of the #162 + #180 plan, revision 1

Independent read-only review by Astra via the codex CLI. Verdict: revision 1 was
not executable; revision 2 of the plan incorporates every P1 below. Absolute
paths in the citations are as the reviewer emitted them.

---

**Вердикт: нужна revision 2. Исполнять revision 1 по одному UNIT с обязательным зелёным Verify нельзя.** Основные проблемы — неверная трактовка статуса `1`, неполный lifecycle-контракт, пропущенные потребители данных и разрывы между UNIT.

План прочитан целиком. Проверка статическая; файлы не изменялись, тесты не запускались. Зафиксированные продуктовые решения не оспариваю. Ниже P1 — блокер исполнения или acceptance, P2 — существенный пробел спецификации.

## A. Фактические ошибки о live code

### A1 — P1. `userReviewStatus == 1` не означает «ранее отправил, затем изменил»

[D10, строки 89–94 плана](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:89) и UNIT 06 строят на этом различие между «Отправить оценки» и «Отправить изменения».

Фактически:

- таблица определяет `1` как `in_progress`: [beacon_review_statuses.dart:14](/home/vader/MY_SRC/tentura/packages/server/lib/data/database/table/beacon_review_statuses.dart:14);
- первое сохранение оценки переводит пакет **из `0` в `1`**, а также из `2` в `1`: [evaluation_case.dart:1355](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:1355);
- отдельная атомарная демоция `2 → 1` действительно существует: [evaluation_repository.dart:391](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/evaluation_repository.dart:391).

**Следствие:** обычный впервые заполненный чек-лист получит «Отправить изменения», хотя пакет ещё никогда не отправлялся.

**Исправление:** до UNIT 06 определить серверный источник различия *never sent / edited after send*. Например, сохранить `0` до первой отправки, оставляя обязательную демоцию `2 → 1`; отдельно определить обработку существующих `1`. Одного клиентского enum недостаточно. Это не требует `reviewRoundId`.

### A2 — P1. Все адресные серверные Verify указывают несуществующий тестовый файл

UNIT 01/02/04/05 используют:

```text
packages/server/test/domain/use_case/evaluation_case_test.dart
```

Реальный файл — [test/domain/evaluation/evaluation_case_test.dart:866](/home/vader/MY_SRC/tentura/packages/server/test/domain/evaluation/evaluation_case_test.dart:866). Тесты graph builder также находятся в `test/domain/evaluation/`, а не в неопределённом `test/domain/use_case/evaluation/…`: [evaluation_participant_graph_builder_test.dart:20](/home/vader/MY_SRC/tentura/packages/server/test/domain/evaluation/evaluation_participant_graph_builder_test.dart:20).

**Исправление:** заменить пути в Owns и Verify. Новые тесты перечислить по точным именам файлов.

### A3 — P1. У `contributionSummary` есть пропущенный UI-потребитель

UNIT 07 удаляет поле, UNIT 08 заменяет его только в списке. Но поле читает ещё **detail sheet**: [evaluation_detail_sheet.dart:238](/home/vader/MY_SRC/tentura/packages/client/lib/features/evaluation/ui/widget/evaluation_detail_sheet.dart:238).

Кроме того, добавление `formerCommitter` ломает исчерпывающие `switch` в том же файле: [evaluation_detail_sheet.dart:140](/home/vader/MY_SRC/tentura/packages/client/lib/features/evaluation/ui/widget/evaluation_detail_sheet.dart:140), [evaluation_detail_sheet.dart:151](/home/vader/MY_SRC/tentura/packages/client/lib/features/evaluation/ui/widget/evaluation_detail_sheet.dart:151).

**Исправление:** включить sheet в обязательную адаптацию модели и общего локализованного participant context. Это совместимость с новым DTO, не редизайн #76.

Утверждение об отсутствии UI-чтения `causalHint` существенно ближе к истине, но серверные мапперы продолжают читать оба legacy-поля: [evaluation_mapper.dart:19](/home/vader/MY_SRC/tentura/packages/server/lib/data/mapper/evaluation_mapper.dart:19), [evaluation_case.dart:705](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:705).

### A4 — P1. Exception mapping расположен не там; коды не различают paused и closed

UNIT 09 предлагает следовать «existing exception-mapping style in repository». Фактический mapper:

- [evaluation_error_mapper.dart:6](/home/vader/MY_SRC/tentura/packages/client/lib/features/evaluation/data/model/evaluation_error_mapper.dart:6);
- подключение — [build_client.dart:19](/home/vader/MY_SRC/tentura/packages/client/lib/data/service/remote_api_client/build_client.dart:19).

`reviewWindowNotOpen` уже имеет типизированное исключение `1401`; expired — `1405`: [evaluation_exception.dart:16](/home/vader/MY_SRC/tentura/packages/client/lib/features/evaluation/domain/evaluation_exception.dart:16), [evaluation_exception.dart:54](/home/vader/MY_SRC/tentura/packages/client/lib/features/evaluation/domain/evaluation_exception.dart:54).

Главное: `_requireLiveReview` возвращает **одинаковый `reviewWindowNotOpen` и после reopen, и после окончательного закрытия**: [evaluation_case.dart:1072](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:1072). Это отдельно закреплено тестом закрытого окна: [evaluation_case_test.dart:1030](/home/vader/MY_SRC/tentura/packages/server/test/domain/evaluation/evaluation_case_test.dart:1030).

**Исправление:** после lifecycle-ошибки перечитывать авторитетное состояние окна/запроса. Нельзя напрямую маппить `1401 → paused`, `1407 → closed`. Добавить настоящий mapper и exception-файлы в Owns.

### A5 — P1. UNIT 11 неверно локализует точки изменения диалогов

Реальные точки:

- HUD close-confirm — [beacon_hud_author_confirm_sheets.dart:72](/home/vader/MY_SRC/tentura/packages/client/lib/features/beacon_view/ui/widget/beacon_hud_author_confirm_sheets.dart:72);
- reopen-confirm — [beacon_view_status_bottom_sheet.dart:296](/home/vader/MY_SRC/tentura/packages/client/lib/features/beacon_view/ui/widget/beacon_view_status_bottom_sheet.dart:296);
- close из status menu выполняется напрямую: [beacon_view_status_bottom_sheet.dart:292](/home/vader/MY_SRC/tentura/packages/client/lib/features/beacon_view/ui/widget/beacon_view_status_bottom_sheet.dart:292);
- close из My Work тоже выполняется напрямую: [my_work_cards.dart:395](/home/vader/MY_SRC/tentura/packages/client/lib/features/my_work/ui/widget/my_work_cards.dart:395).

**Исправление:** перечислить все входы и использовать общий confirm-контракт. Изменение только `beacon_view_app_bar_overflow.dart` не обеспечивает обещанные предупреждения.

### A6 — P2. Пропущен существующий legacy-статус `3`

Таблица допускает `3 = skipped`, а текущий finalize умеет переводить его в `2`; соответствующий тест существует: [beacon_review_statuses.dart:14](/home/vader/MY_SRC/tentura/packages/server/lib/data/database/table/beacon_review_statuses.dart:14), [evaluation_case_test.dart:930](/home/vader/MY_SRC/tentura/packages/server/test/domain/evaluation/evaluation_case_test.dart:930).

**Исправление:** явно определить UI-поведение или миграцию для `3`. Таблица `-1/0/1/2/4` не покрывает текущий wire-контракт.

### A7 — P2. Есть мелкие, но исполнительски значимые неточности

- UNIT 02 добавляет **шесть** полей, UNIT 07 говорит о «five new counters»: [план:348](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:348), [план:577](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:577). Нужен точный список: четыре счётчика целей, счётчик отправителей, boolean.
- `hasAnswer` отсутствует; есть `hasAnswered`: [evaluation_participant.dart:35](/home/vader/MY_SRC/tentura/packages/client/lib/features/evaluation/domain/entity/evaluation_participant.dart:35). План должен явно назначить создание нового getter, его смысл и всех потребителей.
- Ссылка на демоцию `evaluation_repository.dart:389` чуть смещена: SQL начинается на `392`. Это обычный drift, не самостоятельный блокер.

Проверенные baseline-факты верны: `formerCommitter = 3`, client `7.15.0`, bootstrap `7.15.0`, minimum `7.10.0`, reopen limit `1`, extensions `2`: [role:2](/home/vader/MY_SRC/tentura/packages/server/lib/domain/evaluation/evaluation_participant_role.dart:2), [pubspec:5](/home/vader/MY_SRC/tentura/packages/client/pubspec.yaml:5), [index:132](/home/vader/MY_SRC/tentura/packages/client/web/index.html:132), [env:67](/home/vader/MY_SRC/tentura/packages/server/lib/env.dart:67), [commitment_consts:2](/home/vader/MY_SRC/tentura/packages/server/lib/consts/commitment_consts.dart:2), [evaluation_case:146](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:146). Последняя зарегистрированная миграция — `m0175`: [_migrations.dart:363](/home/vader/MY_SRC/tentura/packages/server/lib/data/database/migration/_migrations.dart:363).

## B. Покрытие acceptance criteria

Критерии сверены непосредственно с GitHub.

| Критерий | Заявленная доставка | Результат проверки |
|---|---|---|
| [#162](https://github.com/Intersubjective/tentura/issues/162): “After a complete checklist, the button either submits (and stays submitted) or clearly says Edit review — it does not loop.” | UNIT 06–10 | **Не обеспечен полностью.** In-place success назначен UNIT 08, HUD — UNIT 10. Но ошибочная трактовка `1` ломает первый send; My Work остаётся за пределами изменений; восстановление closed/paused недоопределено. |
| [#180](https://github.com/Intersubjective/tentura/issues/180): “A request can close by consensus while a leaver has not reviewed and has not been reviewed, without error.” | UNIT 02 + существующий close gate + UNIT 07/08 | **Основная серверная идея правильная, доказательство неполное.** Собственный пакет former уже не блокирует close; UNIT 02 должен убрать обязательность оценки о нём. Нужен один сквозной тест: active packages sent, обе стороны former отсутствуют, explicit author close succeeds. |
| #180: “Those optional reviews can still be submitted later if the product allows it.” | Предположительно UNIT 01/08 | **Отдельной реализации и проверки нет.** В принятой модели «later» означает после required-пакетов, но до explicit close/deadline. Нужны тесты optional send и optional edit в этом интервале, затем отказ после закрытия. |

Существующий gate действительно исключает former: [evaluation_case.dart:591](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:591); соответствующая серверная проверка уже есть: [evaluation_case_test.dart:2765](/home/vader/MY_SRC/tentura/packages/server/test/domain/evaluation/evaluation_case_test.dart:2765). Проверка живого окна для submit остаётся обязательной: [evaluation_case.dart:1223](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:1223).

**P1 — отдельное недоставленное требование #180:** “Reviews owed by/to leavers are marked optional.”

Для **целей** это делает UNIT 08. Для **собственного пакета former** план только объявляет строку `evaluationOptionalOwnPackage`, но ни один UNIT не назначает её отображение: [план:139](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:139).

Из списка целей нельзя надёжно узнать роль самого evaluator: self-pairs исключаются [evaluation_visibility_rules.dart:36](/home/vader/MY_SRC/tentura/packages/server/lib/domain/evaluation/evaluation_visibility_rules.dart:36), а status DTO не содержит viewer role/optionality: [review_window_status_result.dart:6](/home/vader/MY_SRC/tentura/packages/server/lib/domain/entity/gql_public/review_window_status_result.dart:6).

**Исправление:** добавить явное `viewerPackageOptional` либо equivalent structured field, назначить banner и тесты для собственного необязательного пакета.

## C. Последствия удаления auto-close

### C1 — P1. «Ни одного close path внутри finalize» — неверный acceptance

UNIT 01 удаляет непосредственный auto-close, но `evaluationFinalize` сначала вызывает `_ensureExpiredClosed`: [evaluation_case.dart:1449](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:1449). Тот запускает deadline sweep: [evaluation_case.dart:148](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:148).

Следовательно, **вызов finalize после deadline может закрыть окно через sweep**, даже после удаления trailing block. Утверждение §4 «race now a non-test» также слишком сильное.

**Исправление:** acceptance сформулировать так:

> Успешная отправка до deadline сама по себе не закрывает окно. Deadline finalization сохраняется, включая sweep, запускаемый API-вызовом.

Раздельно проверить оба случая.

### C2 — P1. Не охвачены My Work и его повторный CTA

Помощнику выставляется `showReviewCta` просто по `reviewOpen`: [derive_my_work_cards.dart:171](/home/vader/MY_SRC/tentura/packages/client/lib/features/my_work/domain/derive_my_work_cards.dart:171). Fallback действительно отображает действие оценки: [my_work_obligation_block.dart:96](/home/vader/MY_SRC/tentura/packages/client/lib/features/my_work/ui/widget/my_work_obligation_block.dart:96).

Дополнительно общая phase-модель для `reviewOpen` предлагает `reviewContributions`: [derive_beacon_coordination_phase.dart:61](/home/vader/MY_SRC/tentura/packages/client/lib/domain/coordination/derive_beacon_coordination_phase.dart:61), и My Work использует это действие: [my_work_cards.dart:419](/home/vader/MY_SRC/tentura/packages/client/lib/features/my_work/ui/widget/my_work_cards.dart:419).

При этом batch-загрузка review status сейчас ограничена authored-карточками и `canCloseNow`: [my_work_case.dart:134](/home/vader/MY_SRC/tentura/packages/client/lib/features/my_work/domain/use_case/my_work_case.dart:134), [my_work_review_windows.graphql:1](/home/vader/MY_SRC/tentura/packages/client/lib/features/my_work/data/gql/my_work_review_windows.graphql:1).

**Исправление:** отдельный UNIT для My Work: package state для всех нужных viewer-карточек, подавление обоих повторных primary CTA, сохранение demoted «Изменить», обновление после send/edit/re-entry.

### C3 — P1. Nudge требует атомарности, а не только ключа по `openedAt`

Сейчас finalize отдельно записывает status, отдельно settles receipt и затем проверяет close: [evaluation_case.dart:1480](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:1480).

При добавлении UNIT 04 необходимо определить:

- транзакцию для status + completion decision + occurrence;
- поведение при сбое между записью статуса и уведомлением;
- одновременные последние send;
- повтор после изменения уже отправленного пакета.

Существующая attention-инфраструктура проверяет при повторе ключа **также actor и immutable payload**; другой payload вызывает ошибку: [attention_dispatch_repository.dart:40](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/attention_dispatch_repository.dart:40). Поэтому одинаковый ключ с разными last-sender actor/title snapshot недостаточен.

**Исправление:** описать конкретный atomic protocol через существующий transaction boundary: [transactional_attention_case.dart:14](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/transactional_attention_case.dart:14). `openedAt` допустим для idempotency события без введения generation id, но нужны стабильные actor/payload и точная схема ключа.

### C4 — P2. `_autoCloseReviewWindow` точно становится мёртвым

Его текущий вызов — trailing block finalize: [evaluation_case.dart:1493](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:1493). `closeNow` и sweep вызывают finalization напрямую: [evaluation_case.dart:543](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:543), [attention_expiry_sweep_case.dart:43](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/attention_expiry_sweep_case.dart:43).

**Исправление:** UNIT 01 должен прямо удалять helper и его устаревший комментарий. Формулировка «stays … if becomes unreferenced» оставляет ненужное решение исполнителю.

### C5 — P2. Отсутствующий автор означает ожидание deadline; UI описывает это неправильно

Окно первоначально длится семь дней; доступны два продления по семь дней: [evaluation_case.dart:144](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:144), [evaluation_repository.dart:617](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/evaluation_repository.dart:617). Worker проверяет expiry с минутным ограничением частоты: [task_worker_case.dart:191](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/task_worker_case.dart:191). Полученные оценки не выдаются до closed: [evaluation_case.dart:1093](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:1093).

Это допустимое следствие frozen-решения, но его надо доставить пользователю: «отправлено; публикация после закрытия автором либо срока».

В UNIT 10 автору при `sent && !canCloseNow` предлагается **«Ждём, пока автор закроет запрос»**: [план:744](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:744). Автор в этой ситуации ждёт остальные required-пакеты, а не себя.

**Исправление:** таблица copy по viewer role × package state × allRequiredSent. Для автора `!canCloseNow` оставить ожидание required reviewers; для остальных после allRequiredSent — ожидание автора/срока.

### C6 — P2. Старые callers/tests могут скрыть регрессию

E2E-helper явно допускает auto-close и принимает finished Archive как альтернативу explicit close: [e2e_test_helpers.dart:1015](/home/vader/MY_SRC/tentura/packages/client/integration_test/support/e2e_test_helpers.dart:1015). Такой тест может остаться зелёным при нарушении D2.

Есть и PG lifecycle-helper, который после двух finalize возвращает константное `finalizeStatus: closed`, не читая фактический результат: [beacon_hierarchy_child_independence_pg_test.dart:313](/home/vader/MY_SRC/tentura/packages/server/test/domain/use_case/beacon_hierarchy_child_independence_pg_test.dart:313).

**Исправление:** назначить обновление helpers/callers: после последнего send проверить `reviewOpen`, затем выполнить explicit close и проверить закрытие. Обновить актуальную документацию, всё ещё перечисляющую auto-close: [beacon-evaluation-principles.md:28](/home/vader/MY_SRC/tentura/docs/beacon-evaluation-principles.md:28).

## D. Optional-reviewer model

### D1 — P1. `formerCommitter` — конкретный predicate, не синоним любого «ушёл»

Фактическая классификация:

| Случай | Текущий результат |
|---|---|
| Был acknowledged, текущий stake acknowledged, offer active | `committer`, required |
| Был acknowledged, затем withdrawn/released/blocked либо softened | `formerCommitter`, optional по D6 |
| Withdraw в grace period без промежуточного события | Может вообще не попасть в ever-acknowledged graph |
| Удалён только из discussion | Само событие не меняет stake; может остаться `committer` |
| Только forwarder | Собственного пакета нет; как target остаётся отдельной ролью |

Основания: [graph_builder:43](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation/evaluation_participant_graph_builder.dart:43), [graph_builder:106](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation/evaluation_participant_graph_builder.dart:106), [commitment_state:14](/home/vader/MY_SRC/tentura/packages/server/lib/domain/commitment/commitment_state.dart:14), [commitment_state:32](/home/vader/MY_SRC/tentura/packages/server/lib/domain/commitment/commitment_state.dart:32), [visibility_rules:53](/home/vader/MY_SRC/tentura/packages/server/lib/domain/evaluation/evaluation_visibility_rules.dart:53).

Удаление из room действительно существует отдельно от release commitment: [coordination_case.dart:432](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/coordination_case.dart:432), [coordination_case.dart:483](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/coordination_case.dart:483).

**Вывод:** predicate достаточен для frozen D6, но план не вправе без уточнения объявлять его покрытием всех бытовых значений «left the request».

**Исправление:** зафиксировать эту таблицу и тесты. Не расширять optionality на room removal или forwarders без отдельного решения. Softened тоже требует теста: это former по текущему predicate, даже если человек физически остаётся в discussion.

### D2 — P1. Собственная optionality не доведена до attention/My Work

В review recipients включаются все участники, кроме forwarders: [evaluation_case.dart:304](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:304). `reviewOpened` получает `requiresAction = true`: [attention_policy.dart:265](/home/vader/MY_SRC/tentura/packages/server/lib/domain/attention/attention_policy.dart:265).

Таким образом, одной optional-секции чужих целей недостаточно: собственный пакет former продолжает поступать в инфраструктуру обязательств без признака optionality.

**Исправление:** определить отображение optional package в Activity/My Work, передать viewer optionality и проверить отсутствие ложного обещания «это нужно для закрытия». Если `requiresAction` сохраняется, план должен явно описать, чем необязательное действие визуально отличается от обязательства.

### D3 — P2. Пропуск optional targets не ломает trust/summary сам по себе

Здесь направление плана правильное:

- close удаляет строки **неотправленных пакетов**, а не строки optional targets: [evaluation_repository.dart:729](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/evaluation_repository.dart:729);
- trust pairs формируются из реально finalized rows: [review_finalization_case.dart:114](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation/review_finalization_case.dart:114);
- commitment evidence также строится по существующим строкам: [review_finalization_case.dart:130](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation/review_finalization_case.dart:130);
- received summary обрабатывает существующие полученные строки, включая пустой набор: [evaluation_case.dart:1103](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:1103).

**Исправление к проверкам:** PG-тест должен доказать одновременно:

1. отсутствующий optional target не создаёт фиктивную оценку;
2. имеющийся optional row отправленного пакета учитывается;
3. весь неотправленный optional package удаляется;
4. его ack-tags не остаются;
5. trust math не меняется.

UNIT 02 non-PG Verify этого не доказывает.

### D4 — P2. Счётчик в close-confirm измеряет не то

UNIT 11 использует `optionalTotal - optionalReviewed` для сообщения «необязательных оценок не получено». Но исходные review counters вычисляются по **видимости текущего evaluator и его собственным строкам**: [evaluation_case.dart:1033](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:1033).

Это не количество неотправленных пакетов former-reviewers. Автор мог оценить всех former, а они ничего не отправили; либо наоборот.

**Исправление:** разделить viewer progress и close-discard summary. Для предупреждения о чужих пакетах нужен отдельный `unsentOptionalPackageCount` с соответствующим текстом. Если предупреждение касается пропусков автора, так и назвать их.

## E. Миграция и structured context

### E1 — P1. SQL-shape допустим, но data plumbing неполон

Таблица действительно называется `beacon_evaluation_participant`: [beacon_evaluation_participants.dart:24](/home/vader/MY_SRC/tentura/packages/server/lib/data/database/table/beacon_evaluation_participants.dart:24). Механизм — `part of`, `Migration('0176', [...])`, регистрация в списке migrant: [m0175.dart:1](/home/vader/MY_SRC/tentura/packages/server/lib/data/database/migration/m0175.dart:1), [_migrations.dart:369](/home/vader/MY_SRC/tentura/packages/server/lib/data/database/migration/_migrations.dart:369).

Но Owns UNIT 03 пропускает обязательные звенья:

- `domain/port/evaluation_repository_port.dart`, `insertParticipant`: [строка 38](/home/vader/MY_SRC/tentura/packages/server/lib/domain/port/evaluation_repository_port.dart:38);
- `BeaconEvaluationParticipantRecord`: [beacon_evaluation_record.dart:31](/home/vader/MY_SRC/tentura/packages/server/lib/domain/entity/evaluation/beacon_evaluation_record.dart:31);
- `data/mapper/evaluation_mapper.dart`: [строка 19](/home/vader/MY_SRC/tentura/packages/server/lib/data/mapper/evaluation_mapper.dart:19);
- запись participant из `beaconClose`: [evaluation_case.dart:294](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:294);
- mock реализации порта и соответствующие test doubles.

**Исправление:** расписать весь round trip: graph draft → port → insert → Drift record → domain record → DTO → GraphQL. Добавить server codegen после изменения Drift table.

### E2 — P1. Draft endpoint требует тех же полей

`evaluationDraftParticipants` использует тот же public DTO, но строит его отдельным кодом из graph builder: [evaluation_case.dart:759](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:759), [evaluation_case.dart:810](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:810). Оба endpoints публикуют один GraphQL type: [query_evaluation.dart:25](/home/vader/MY_SRC/tentura/packages/server/lib/api/controllers/graphql/query/query_evaluation.dart:25).

**Исправление:** UNIT 02/03 должны явно заполнить новые поля в обоих constructors. Для draft определить `rowStatus` по используемой draft-строке; проверить локализацию, optional-role mapping и прежнее поведение draft «Готово».

### E3 — P1. Нет обновления входной GraphQL schema для codegen

Ferry читает локальный `lib/data/gql/schema.graphql`: [build.yaml:29](/home/vader/MY_SRC/tentura/packages/client/build.yaml:29). В текущей schema новых полей нет: [schema.graphql:7756](/home/vader/MY_SRC/tentura/packages/client/lib/data/gql/schema.graphql:7756), [schema.graphql:8028](/home/vader/MY_SRC/tentura/packages/client/lib/data/gql/schema.graphql:8028).

**Исправление:** включить schema в Owns, назначить её обновление до изменения queries/codegen. Документированный fetch — [DEVELOPMENT.md:197](/home/vader/MY_SRC/tentura/DEVELOPMENT.md:197). Сам `build_runner` серверные custom types в schema не переносит.

### E4 — P2. «Без backfill» оставляет существующие окна без контекста

Предлагаемые default/null значения означают, что уже материализованные participant rows не получат дату/offer/forwarder. При этом UNIT 08 требует форматировать дату, но не задаёт null-ветку: [план:393](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:393), [план:649](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:649).

**Исправление:** определить upgrade-policy: backfill из structured источников либо явно локализованный fallback без даты. Нужен migration test на существующем открытом окне. Возврат к raw English legacy summary нарушит D9.

### E5 — P2. `offerMessage` транспортируется, но его отображение потеряно

Сейчас текст offer входит в summary: [graph_builder.dart:182](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation/evaluation_participant_graph_builder.dart:182). Рецепт UNIT 08 перечисляет дату, forwarder и ended, но не `offerMessage`.

**Исправление:** определить отображение offer message и author context в общем presenter для списка и sheet; определить UTC → local date. Legacy-колонки можно пока сохранять, но формулировку «nothing reads them after this plan» заменить точным «новый UI их не читает».

## F. Недоопределённость для буквального исполнителя

### F1 — P1. Manifest не обеспечивает компилируемые промежуточные UNIT

Проблемы порядка:

- UNIT 07 удаляет getters, потребители меняются в UNIT 10: [план:577](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:577).
- UNIT 07 удаляет summary, список меняется в UNIT 08, sheet не назначен вообще — A3.
- UNIT 07 добавляет enum case, exhaustive switches sheet остаются — A3.
- UNIT 08–11 используют новые l10n API, которые добавляются только UNIT 12: [план:244](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:244).
- У server DTO новые required поля затрагивают draft constructor и fixtures в том же UNIT, не позже — E2.

**Исправление:** сначала additive DTO/schema/l10n, затем миграция потребителей, затем удаление legacy API. Каждое удаление — вместе с последним потребителем.

### F2 — P1. Невозможно вывести обещанный lifecycle из заданных входов

UNIT 06 одновременно говорит:

- `notEnrolled` — «или нет окна»;
- `!hasWindow → paused`;
- paused — «beacon left reviewOpen while viewer enrolled».

Но функция не получает ни beacon lifecycle, ни факт прежнего enrolment: [план:513](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:513). После reopen scaffolding, включая review statuses, удаляется: [evaluation_repository.dart:595](/home/vader/MY_SRC/tentura/packages/server/lib/data/repository/evaluation_repository.dart:595).

**Исправление:** определить авторитетный lifecycle discriminator и приоритет loading/notEnrolled/paused/closed. Новому посетителю запроса, ещё не имевшего окна, нельзя показывать «Автор вернул запрос в работу».

### F3 — P1. Closed read-only list не обеспечен серверным API

UNIT 09 обещает read-only list. Но participants endpoint требует live window: [evaluation_case.dart:613](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:613). Клиент грузит participants **до** window status: [evaluation_cubit.dart:109](/home/vader/MY_SRC/tentura/packages/client/lib/features/evaluation/ui/bloc/evaluation_cubit.dart:109).

**Исправление:** назначить способ чтения своего finalized package после close либо изменить endpoint с явными authorization/read-only правилами. Cached list недостаточен для reload; для `closedUnsent` нужно отдельное содержимое о реально удалённых строках.

### F4 — P1. Новые attention events не вписываются в перечисленный Owns

Типы задаются enum, а policy содержит exhaustive switches: [attention_models.dart:9](/home/vader/MY_SRC/tentura/packages/server/lib/domain/attention/attention_models.dart:9), [attention_policy.dart:53](/home/vader/MY_SRC/tentura/packages/server/lib/domain/attention/attention_policy.dart:53). Добавить константу в `beacon_activity_event_consts.dart` недостаточно.

**Исправление:** перечислить:

- enum cases и wire names;
- policy: category, suppression, access, destination, `requiresAction=false`, presentation key;
- intent builders и transaction producer;
- localized Updates copy;
- `docs/contracts/updates-event-contract.json` и contract tests.

Контракт проверяется как точный набор строк: [updates_event_contract_test.dart:148](/home/vader/MY_SRC/tentura/packages/server/test/architecture/updates_event_contract_test.dart:148).

### F5 — P1. Все опасные «по существующим соглашениям» нужно заменить контрактами

| Место плана | Что исполнитель может сделать неправильно | Конкретное уточнение |
|---|---|---|
| UNIT 02 «existing ready check» | Использовать необъявленный `partByUser`, разные predicates client/server | Назвать загрузку participants, readiness predicate и обработку отсутствующего target |
| UNIT 02 «equivalent read» | Посчитать все reviewers, включая former; смешать viewer и global counters | Формулы, scope и nullability каждого поля |
| UNIT 04 «sourceEventKey usual shape» | Случайный ключ, дубли; либо одинаковый ключ с разным payload | Точный deterministic key и atomic protocol — C3 |
| UNIT 09 «existing exception-mapping style» | Второй mapper в repository; `1401 → paused` | Настоящие файлы и refresh-based classification — A4 |
| UNIT 11 «existing Updates row conventions» | Generic/raw English row, неверная destination/action | Точные presentation keys, copy, action/destination и tests — F4 |
| UNIT 03 `test/.../…` | Создать другой тест вместо расширения существующих | Полные пути и названия сценариев |
| UNIT 14 «any narrow fix suites demand» | Отложить обязательную совместимость до closeout | Перенести известные изменения в соответствующие UNIT |

### F6 — P2. Не определены данные и действия для нескольких UI-обещаний

- **`sentAt` отсутствует в назначенном DTO.** Сейчас status endpoint получает только integer статуса и timestamps окна: [evaluation_case.dart:1029](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:1029). Нельзя подставлять `openedAt` или локальное время для «Оценки отправлены {date}». Нужен источник времени отправки либо убрать дату.
- **«Готово» и «К запросу» не имеют navigation contract.** Указать pop к существующему request route и fallback для deep link.
- **Paused без действия пользователя не доставлен.** Текущий cubit обновляется через load/mutation methods, а UNIT 09 описывает только catch: [evaluation_cubit.dart:92](/home/vader/MY_SRC/tentura/packages/client/lib/features/evaluation/ui/bloc/evaluation_cubit.dart:92). Нужен refresh/invalidation trigger либо честное ограничение acceptance «после следующего refresh/action».
- **Zero targets противоречат друг другу:** UNIT 06 даёт `readyToSend`, UNIT 07 `participants.isEmpty → false`: [план:536](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:536), [план:588](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:588).
- **`rowStatus >= 0` шире серверной readiness.** Сервер разрешает draft/submitted; enum также содержит final/responded: [evaluation_case.dart:1468](/home/vader/MY_SRC/tentura/packages/server/lib/domain/use_case/evaluation_case.dart:1468), [beacon_evaluation_row_status.dart:2](/home/vader/MY_SRC/tentura/packages/server/lib/domain/evaluation/beacon_evaluation_row_status.dart:2). Назвать допустимые состояния явно.
- **Sent-author CTA противоречив:** UNIT 10 разрешает `closeNow` поверх sent, затем требует «none in sent» для всех тестов: [план:725](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:725). Исправить на «нет primary *review* CTA; author close остаётся».

### F7 — P1. Verify-блоки не проверяют собственные acceptance

- **01/02/04/05:** неправильный путь теста — A2.
- **03:** `--exclude-tags pg` не проверяет применение миграции и DB round trip.
- **06:** pure enum tests не могут подтвердить отсутствие сравнений статусов во всём клиенте; acceptance зависит от UNIT 10.
- **07:** весь evaluation suite проверяется до совместимого обновления UI/l10n.
- **08/09/10:** нужны исправления порядка и lifecycle-контракта выше.
- **11:** меняет Updates, но Verify запускает только `test/features/beacon_view`.
- **12:** terminology script не доказывает компиляцию placeholders и правильность RU/EN copy.
- **13:** нет Verify version/bootstrap/minimum consistency.
- **14:** «full suites» исключают PG, хотя acceptance включает SQL deletion, migration и concurrency.

**Исправление:** для каждого UNIT дать проверку его собственного increment. SQL/concurrency — отдельные serial disposable-PG gates; UI continuity — конкретный integration test file с TestIds.

### F8 — P1. Shell-команды и generated-file policy неверны

В Verify UNIT 01/02/03/05/06/08/09/10/11 строки после `--` не везде продолжены `\`. При буквальном копировании wrapper запускается без команды, а следующая строка — отдельно. В UNIT 14 последовательные `cd packages/server`, затем `cd packages/client` также предполагают несуществующий относительный путь: [план:843](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:843).

**Исправление:** дать команды в одну строку либо корректные continuations/subshell с явно заданным cwd.

Указание коммитить `_g/**` противоречит правилам и ignore: [план:210](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:210), [.cursor/rules/codegen.mdc:165](/home/vader/MY_SRC/tentura/.cursor/rules/codegen.mdc:165), [client/.gitignore:51](/home/vader/MY_SRC/tentura/packages/client/.gitignore:51).

**Исправление:** генерировать локально, коммитить исходники schema/query/model/ARB; не применять `git add -f` к generated outputs.

## G. Scenario matrix

### G1 — P1. Несколько строк сейчас не имеют однозначного проверяемого oracle

| Строка §4 | Проблема | Исправление |
|---|---|---|
| Stable sent; «no primary review CTA anywhere» | Не определены поверхности; My Work пропущен | Перечислить checklist, HUD, banner, My Work; author close разрешён |
| Leaver’s own package «warned about discard» | Нет viewer optionality и UNIT отображения | Добавить поле, banner и named test |
| Close «optional gaps named» | Смешаны target gaps и unsent packages | Определить счётчик и copy — D4 |
| Reopen while reviewer on checklist | Нет события, которое обновляет бездействующий экран | Задать trigger и ожидаемую задержку |
| Second window: departed «optional or absent» | Два разных ожидаемых результата | Разбить по grace/everAcknowledged/current stake |
| Two simultaneous sends | В следующем абзаце объявлено «non-test» | Реальный concurrency test для единственного nudge и отсутствия early close |
| `-1 / 4` | Два разных lifecycle-состояния объединены | Отдельные fixtures и запрещённые действия |
| App restart | Нет механизма рестарта/восстановления в назначенном e2e | Назвать тест и способ сохранения той же session |

Основание — сама [матрица:866](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:866); несоответствия live code разобраны в A–F.

### G2 — P1/P2. Не хватает следующих сценариев

В порядке важности:

1. **Первое сохранение до первой отправки** — ловит A1.
2. **Legacy status `3`; loading/null status; never-enrolled deep link.**
3. **Успешный send, затем ошибка refresh** — пакет не должен выглядеть неотправленным только из-за второго запроса.
4. **Reload после explicit close и expiry**, отдельно sent и unsent.
5. **Deadline наступил между чтением окна и submit/finalize.**
6. **Author close одновременно с edit/re-send** — либо принятная правка блокирует close, либо закрытие побеждает и правка отклоняется; нужен DB oracle.
7. **Последним отправляет автор; повтор finalize; сбой записи nudge; два last send.**
8. **Nudge уже записан, затем required reviewer редактирует пакет:** close снова недоступен; историческое уведомление не должно обещать безусловное закрытие.
9. **Только optional targets; отдельно ноль targets.**
10. **Optional row уже сохранён, затем пользователь нажал локальное «Пропустить».** Скрытие не удаляет строку и не исключает её из пакета.
11. **Собственный optional package отправлен / не отправлен / изменён после отправки**, с проверкой close-time retention/deletion.
12. **Existing-window upgrade**, null date, empty offer, RU/EN, detail sheet.
13. **Draft route после добавления enum и structured fields.**
14. **Reopen и повторное окно:** новые required targets, старые допустимые drafts, выбывший в grace period — разные точные fixtures.

Для DB-проверок в репозитории уже используется отдельный `pg`-tag и disposable target: [evaluation_repository_submit_atomic_pg_test.dart:1](/home/vader/MY_SRC/tentura/packages/server/test/data/repository/evaluation_repository_submit_atomic_pg_test.dart:1). Их нельзя заменить non-PG mock-suite и назвать release acceptance выполненным.

Сценарии stale commands, пересекающих разные поколения окна, можно оставить #186. **Гонки внутри одного живого окна и идемпотентность новых уведомлений к этому исключению не относятся.**

## H. Избыточность и границы отдельного issue

### H1 — P2. Не нужно удалять старые wire counters в closeout

UNIT 14 предлагает убрать `reviewedCount/totalCount`, если они больше не нужны UNIT 07. Но их ещё читает status-menu snapshot: [beacon_view_status_bottom_sheet.dart:40](/home/vader/MY_SRC/tentura/packages/client/lib/features/beacon_view/ui/widget/beacon_view_status_bottom_sheet.dart:40).

**Исправление:** оставить additive compatibility либо назначить отдельный полный consumer migration. «Remove if unused» в финальном UNIT — лишняя развилка для малого исполнителя и дополнительная поверхность регрессии.

### H2 — P2. Запрет любых `< 2 / == 2` слишком широк

Цель — централизовать **package-state interpretation**, а не запретить числовые сравнения любых evaluation statuses. Row lifecycle — отдельная модель со своими кодами: [beacon_evaluation_row_status.dart:2](/home/vader/MY_SRC/tentura/packages/server/lib/domain/evaluation/beacon_evaluation_row_status.dart:2).

**Исправление:** ограничить acceptance сравнением `userReviewStatus` в UI decision-making. Не превращать задачу в общий рефакторинг всех statuses.

### H3 — P2. Не связывать cleanup context-колонок с #186

Удаление `contribution_summary/causal_hint` — миграционный cleanup локализации. Window generation identity — другая задача. Связь «#186 natural place to retire them» в [плане:403](/home/vader/MY_SRC/tentura/docs/plans/issue-162-180-review-package-state-plan.md:403) искусственна.

**Исправление:** оставить колонки совместимости сейчас; завести отдельный cleanup только при необходимости.

### H4. Что оставлять в этом плане

- Pure `ReviewPackageState` оправдан, после исправления входного контракта.
- Structured context и локальное «Пропустить» соответствуют frozen-решениям.
- Nudge после удаления auto-close нужен; его нельзя выносить, сохраняя обещание D13.
- Адаптация detail sheet к новой модели обязательна, но его редизайн остаётся #76.
- #184 и generation-aware stale-command handling остаются отдельно. In-place send не является доказательством исправления #184.

**Итоговый вердикт: нужна revision 2, не полный переписанный дизайн.** До исполнения обязательны: исправленный контракт статусов/lifecycle, полный список consumers и data plumbing, компилируемый порядок UNIT, атомарный контракт уведомлений и реальные PG/e2e acceptance gates.