# Server DB access & request concurrency — architecture review

Independent review by Astra (codex, gpt-6-astra, read-only), 2026-10-11, of the request pipeline write-up that followed the TENTURA-SERVER-V/W/X pool deadlock (fixed in 863b05198, f12acbed5). Tracking: epic `tentura-ev3z`, GitHub #275–#281. Links below point to local paths as the reviewer saw them; file:line refers to tree `f12acbed5`.

## Рекомендация

**Для Tentura я бы сохранил Drift как типизированный SQL-слой, но перестал разделять один Drift executor между независимыми запросами.** Владельцем pooled-соединения должна быть короткая DB-операция use case; все её репозитории используют это соединение до commit/rollback. Между операциями — настоящий pool, ограниченная очередь допуска и единый deadline.

Начальная конфигурация для 2 vCPU: **один web isolate, отдельный background isolate, небольшой pool и отдельное ограничение тяжёлых MeritRank-запросов**. Увеличивать число web isolates стоит после измерения загрузки Dart event loop.

Два принципиальных уточнения:

1. **Можно конструктивно устранить нынешний класс application deadlock — инверсию Drift lock ↔ connection lease.** Обещать отсутствие любых PostgreSQL deadlock при конкурентных транзакциях, триггерах и нескольких клиентах БД нельзя. Для них остаются порядок блокировок, короткие транзакции и ограниченные повторы.
2. **Вывод «#227 вообще не даёт параллелизма» неверен.** В установленном Drift этот spike уже позволяет параллельные транзакции. Последовательными остаются обычные запросы через корневой executor.

Проверял исходники приложения, установленный код зависимостей, историю `863b05198` / `0d3e7b849` и актуальные страницы пакетов. Во время обзора исправления рабочего дерева вошли в **`f12acbed5`**; ниже учитываю этот коммит. Файлы не менял, тесты и нагрузочные прогоны не запускал. Числа производительности из запроса не считаю заново измеренными.

## 1. Что в описании pipeline нужно исправить

### Ключевые расхождения

| Утверждение | Что показывает код |
|---|---|
| **Одна HTTP/2-сессия вкладки попадает на один web isolate** | **Не следует из конфигурации.** HTTP/2 завершается на Caddy. Дальше Caddy использует собственные upstream-соединения к Shelf; привязки вкладки к isolate нет. Конкретное upstream TCP-соединение обслуживается одним isolate, но параллельные запросы вкладки могут идти по разным соединениям. См. [Caddyfile:23](../../Caddyfile), [web_worker.dart:23](../../packages/server/lib/app/workers/web_worker.dart), [описание транспорта Caddy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#transports). |
| **У каждого isolate только одна DB lane + LISTEN** | Для основного `TenturaDb` при выключенном spike — да, но это неполный подсчёт. Есть отдельный `@Named('auth') TenturaDb`, используемый `SessionRepository`; также `TaskWorker` для `pg_job_queue` открывает собственное соединение. См. [modules.dart:11](../../packages/server/lib/app/modules.dart), [session_repository.dart:19](../../packages/server/lib/data/repository/session_repository.dart), [task_worker.dart:12](../../packages/server/lib/data/service/task_worker.dart). |
| **Refresh access token ждёт основную DB lane** | Уже исправлено коммитом `5e07a604d`: session lookup использует auth DB. Выпуск JWT после lookup не требует основной БД: [session_case.dart:40](../../packages/server/lib/domain/use_case/session_case.dart). Refresh всё ещё входит в клиентское ожидание запроса, но имеет отдельную DB lane. |
| **#227 всё сериализует из-за `isSequential: true`** | **Неверно для транзакций.** Подробнее ниже. |
| **RR mutation имеет общий бюджет 5 секунд** | **Нет строгого end-to-end ограничения.** В начале попытки задаётся `statement_timeout`, который применяется к каждому SQL отдельно. Первая попытка получает полные 5 секунд даже после ожидания соединения. Успешная цепочка коротких SQL может длиться существенно дольше. См. [tentura_db.dart:281](../../packages/server/lib/data/database/tentura_db.dart), [postgres_serialization_retry.dart:75](../../packages/server/lib/data/database/postgres_serialization_retry.dart). |
| **Pool acquisition timeout сейчас 15 секунд** | После `f12acbed5` по умолчанию **35 секунд**: `statement_timeout + 5 s`. Это исправляет конкретный конфликт таймаутов, но не ограничивает общее время запроса: [env.dart:821](../../packages/server/lib/env.dart). |
| **Один FULL на 5–7 секунд неизбежно просрочит очередь writes в 10 секунд** | Сам по себе — нет. Просрочка требует дополнительной очереди, другого ожидания или большей длительности FULL. Scheduler действительно непредвытесняющий: уже начавшийся FULL приоритетом записи не прерывается. [constellation_db_scheduler.dart:89](../../packages/server/lib/data/service/constellation_db_scheduler.dart). |
| **Каждое уведомление немедленно вызывает FULL refetch** | Слишком сильное утверждение. Уже есть серверное объединение global-field уведомлений, клиентское объединение/ограничение refresh и серверный single-flight одинаковых FULL. [websocket_path_entity_changes.dart:27](../../packages/server/lib/api/controllers/websocket/path_handler/websocket_path_entity_changes.dart), [constellation_field_store_case.dart:394](../../packages/client/lib/features/constellation/domain/use_case/constellation_field_store_case.dart), [constellation_field_case.dart:61](../../packages/server/lib/domain/use_case/constellation_field_case.dart). |
| **Visibility только memoized per transaction, m0222** | Уже есть **cross-request cache m0235**, привязанный к MR epoch и trust generation. Перед READ ONLY snapshot выполняется отдельный cache-fill запрос: [m0235.dart:68](../../packages/server/lib/data/database/migration/m0235.dart), [constellation_field_repository.dart:101](../../packages/server/lib/data/repository/constellation_field_repository.dart). |
| **~88 ms Nagle stall — текущая стоимость RPC** | Это исторический дефект. Репозиторий документирует его исправление и последующие замеры; текущий compose использует более новые образы. Нельзя использовать 88 ms для расчёта нынешней ёмкости без нового измерения. [measurements.md:9](../../docs/plans/issue-235-constellation-interactive-measurements.md), [compose.prod.yaml:127](../../compose.prod.yaml). |

### Что именно происходит в #227

В приложении действительно написано:

```dart
super(_TransactionPinnedDelegate(pool), isSequential: true)
```

Но этого недостаточно для вывода о транзакциях.

В **установленном Drift 2.34.3**:

- `SupportedTransactionDelegate.managesLockInternally` по умолчанию возвращает `true`;
- `_WrappingTransactionExecutor` при этом запускает транзакцию **без корневого `_db._synchronized`**;
- каждая транзакция получает собственный executor и делегат на leased `TxSession`.

Источники: delegates.dart:170 (pub-cache `drift-2.34.3/lib/src/runtime/executor/helpers/delegates.dart:170`), engines.dart:395 (pub-cache `drift-2.34.3/lib/src/runtime/executor/helpers/engines.dart:395`), [tentura_db.dart:569](../../packages/server/lib/data/database/tentura_db.dart).

**Итог для spike:**

| Работа | Параллелизм |
|---|---|
| Две независимые транзакции | Есть, при достаточном pool |
| Обычный запрос и независимая транзакция | Есть |
| Два обычных запроса через корневой executor | Сериализованы |
| SQL внутри одной транзакции | Последовательны; это нормально |

Тест уже содержит barrier, требующий одновременно открытых транзакций на разных backend PID. Он использует несколько логических `TenturaDb`, разделяющих **один executor и pool**: [transaction_pinned_pool_pg_test.dart:107](../../packages/server/test/data/database/transaction_pinned_pool_pg_test.dart).

Для rollout я дополнительно потребовал бы аналогичный тест через **один production `TenturaDb` и реальные use cases**. Но исходное утверждение «spike только меняет порядок захвата, параллелизма нет» уже опровергается кодом.

### Остальное описание в основном подтверждается, с оговорками

- Client link chain и `NoCache` соответствуют описанию. Однако есть **два** stream timeout — в link и над typed Ferry stack; три upload-операции исключены из обоих. `Stream.timeout` здесь добавляет ошибку, не отменяя HTTP-запрос. [build_client.dart:45](../../packages/client/lib/data/service/remote_api_client/build_client.dart), [remote_api_client_web.dart:126](../../packages/client/lib/data/service/remote_api_client/remote_api_client_web.dart).
- Boot действительно выполняет migrations, extension update, cutovers и загрузку графа до запуска workers. Но cutovers используют также отдельный boot DI graph, поэтому это не буквально одно соединение на всю фазу: [app.dart:23](../../packages/server/lib/app/app.dart).
- `WORKERS_COUNT` по умолчанию равен CPU count; **`DEBUG_MODE=true` принудительно оставляет один web isolate**: [env.dart:208](../../packages/server/lib/env.dart), [env.dart:585](../../packages/server/lib/env.dart).
- JWT middleware для V2 действительно проверяет JWT без DB lookup. Middleware может вернуть **401**, поэтому «всегда HTTP 200» относится к обработанным GraphQL/domain errors внутри controller, не ко всему endpoint. [auth_middleware.dart:51](../../packages/server/lib/api/middleware/auth_middleware.dart), [graphql_controller.dart:78](../../packages/server/lib/api/controllers/graphql_controller.dart).
- `graphql_server2` действительно ожидает поля selection set последовательно. Это сериализация **внутри исполнения одного GraphQL-документа**, не между HTTP-запросами: graphql_server2.dart:531 (pub-cache `graphql_server2-6.5.0/lib/graphql_server2.dart:531`).
- При выключенном spike основной Drift executor сериализует обычные SQL и целые транзакции; `TenturaDb.transaction` сначала делает `pin()`: [tentura_db.dart:204](../../packages/server/lib/data/database/tentura_db.dart). Класс инверсии ресурсов в исходном диагнозе определён правильно.
- LISTEN действительно выделен отдельно и имеет reconnect/recovery механизм: [pg_notification_service.dart:88](../../packages/server/lib/data/service/pg_notification_service.dart).
- Background worker последовательно обходит задачи. `TASK_DELAY` — пауза между проходами, поэтому реальная периодичность зависит ещё от длительности всех задач: [task_worker_case.dart:445](../../packages/server/lib/domain/use_case/task_worker_case.dart).
- Освобождение background от 30-секундного `statement_timeout` касается прямого соединения `TaskWorker`, **не всех запросов background isolate**: его обычные репозитории используют `TenturaDb` с теми же pool settings. Кроме того, у `postgres 3.5.12` есть собственный default `queryTimeout` 5 минут — «совсем без ограничений» тоже неточно: resolved_settings.dart:20 (pub-cache `postgres-3.5.12/lib/src/v3/resolved_settings.dart:20`).

**Исправленный вывод о текущей производительности:** при выключенном spike имеется одна основная DB lane на web isolate. Это создаёт head-of-line blocking. Но задержка открытия экрана не обязана равняться сумме времён всех запросов: часть идёт в Hasura, auth имеет отдельную lane, а V2-запросы могут распределяться между isolates.

## 2. Целевая архитектура DB-доступа

### Владение соединением важнее выбора ORM

Предлагаю такой порядок:

```text
HTTP request
  → RequestContext: actor, requestId, deadline, cancellation
  → use case
  → bounded admission, пока без DB-соединения
  → lease одного соединения
  → короткий DB scope:
       scoped repositories
       при необходимости BEGIN / SET LOCAL / SQL / COMMIT
  → подтверждённый rollback/commit, завершённая отмена
  → возврат соединения
  → response
```

**DB scope не равен всей HTTP-обработке.** Чтение upload body, S3, отправка email и CPU-обработка изображения находятся вне него. Несколько SQL, которым нужен общий snapshot, находятся внутри одной транзакции.

Обязательные инварианты:

1. Репозитории внутри scope получают одну и ту же session/DB handle.
2. Репозиторий внутри транзакции не может самостоятельно занять второе соединение.
3. Вложенный use case присоединяется к текущей транзакции либо использует savepoint на том же соединении.
4. Несовместимая вложенная изоляция отклоняется явно; «повысить до RR посреди транзакции» нельзя.
5. В scope нет `unawaited` DB-работы и ожидания результата фоновой задачи.
6. Actor и SQL session settings задаются transaction-local; request context не переносится между запросами.
7. Соединение не возвращается в pool, пока commit/rollback/cancel не завершены. При неизвестном protocol state оно закрывается.

Тогда независимые запросы не делят прикладной DB mutex. Один запрос не удерживает соединение, ожидая mutex другого запроса. **Именно рассматриваемый цикл ожидания исчезает.**

### Мой предпочтительный вариант: scoped Drift поверх leased Connection

Pool принадлежит инфраструктуре процесса. После admission он выдаёт `Connection`. На время DB scope создаётся обычный:

```dart
PgDatabase.opened(connection, enableMigrations: false)
```

и `TenturaDb`/репозитории, привязанные к нему.

Drift остаётся последовательным **внутри этого scope**, но другие scopes имеют другие executors и соединения. Поэтому параллелизм между запросами настоящий.

Здесь важна одна деталь реализации:

> Если транзакцией управляет Drift через обычный `PgDatabase`, соединение уже должно быть leased на всю её длительность. Не нужно оборачивать тот же блок в `postgres.runTx` и затем повторно вызывать `Drift.transaction`: это два владельца `BEGIN/COMMIT`.

Это позволяет удалить:

- `_PinnedPoolSession`;
- override `TenturaDb.transaction`, занимающий pool до Drift lock;
- `_TransactionPinnedPgDatabase` и savepoint delegate spike;
- singleton `TenturaDb`, общий для независимых запросов.

Останутся небольшие инфраструктурные компоненты: владелец pool, factory DB scopes, admission/deadline/cancellation. Это полезные обязанности приложения, которые библиотека сама не угадает.

Основная стоимость перехода — **изменение DI и способа передачи репозиториев в unit of work**. Не надо создавать целый `GetIt` graph для каждого SQL. Достаточно scoped набора data-репозиториев; domain ports и stateless use cases сохраняются. Уже существующий [MutatingUnitOfWorkPort](../../packages/server/lib/data/repository/mutating_unit_of_work.dart) — подходящая точка начала.

### Сравнение вариантов

| Вариант | Оценка |
|---|---|
| **Scoped Drift + leased Connection** | **Рекомендую как целевой вариант для нынешней команды.** Сохраняет типизированные запросы и raw SQL migrations, устраняет глобальный executor и custom pinning. Требует аккуратной переделки scope/DI. |
| **Доработать #227: non-sequential root + transaction delegate** | Самый короткий путь к измеримому улучшению. Транзакционный параллелизм уже есть; корневой executor можно сделать concurrent при корректном pooled delegate. Но остаётся собственный backend integration, его lifecycle, batch/savepoint/cancellation контракты. Хороший промежуточный релиз, не мой выбор для максимального упрощения. |
| **Drift `MultiExecutor.withReadPool`** | Реальная встроенная возможность, но плохое соответствие этой задаче. Все транзакции, включая READ ONLY snapshot, направляются в `write`; есть собственная очередь. Маршрутизация `SELECT` не понимает побочных эффектов функций Tentura. connection_pool.dart:17 (pub-cache `drift-2.34.3/lib/src/runtime/executor/connection_pool.dart:17`). |
| **Прямой `postgres`: Pool + `runTx` + typed repository methods** | Самая прозрачная модель session/transaction ownership, проще индивидуальные SQL timeout. Хороший выбор для новых SQL-heavy репозиториев. Полная миграция сейчас означает переписывание значительного typed query layer и маппинга без необходимости для устранения блокировки. |
| **Новый ORM/framework** | Не рекомендую связывать с этим исправлением. Нужно доказать его transaction/pool/cancel контракты; смена framework сама по себе их не обеспечивает. |

`DatabaseConnection` в Drift — контейнер executor и stream-query state, **не PostgreSQL connection pool**: connection.dart:3 (pub-cache `drift-2.34.3/lib/src/runtime/api/connection.dart:3`). `NativeDatabase.readPool` относится к SQLite; это тоже не готовое решение для `drift_postgres`.

### Пакеты и версии

| Компонент | Что я выбрал бы |
|---|---|
| PostgreSQL driver | **`postgres 3.5.20`**, отдельным обновлением и с фиксированным lockfile. Сейчас установлен 3.5.12. |
| Typed SQL на этапе перехода | Сохранить **`drift 2.34.3` + `drift_dev 2.34.5` + `drift_postgres 1.3.1`**, чтобы не смешивать изменения ownership и генератора. |
| Миграции | Оставить **`migrant 0.3.0`** и текущие raw SQL migrations. |
| HTTP server | Оставить **`shelf 1.4.2` / `shelf_plus 1.11.0`**; добавить явную интеграцию cancellation на границе транспорта. |
| Browser HTTP | Уже установлен **`http 1.6.0`**; использовать `AbortableRequest` / `AbortableMultipartRequest`. Дополнительный fetch package не нужен. |
| GraphQL execution | Пока оставить **`graphql_server2 6.5.0`**. Его замена — отдельное решение после устранения DB bottleneck. |

Почему обновление `postgres` имеет высокий приоритет: changelog после 3.5.12 содержит исправления hard timeout, transaction cleanup, pool lifecycle; в **3.5.19** отдельно исправлена гонка, когда timeout cancellation попадала в следующий запрос на переиспользованном соединении. Это непосредственно относится к предлагаемой модели. [Changelog postgres](https://pub.dev/packages/postgres/changelog).

На момент проверки опубликованный `drift_postgres` остаётся **1.3.1**; готового обновления, автоматически заменяющего весь ваш pooling workaround, я не нашёл. [Страница пакета](https://pub.dev/packages/drift_postgres).

Для SQL-first codegen проверил **`dsql 1.0.7`**: пакет сам обозначен experimental/under development и включает собственную миграционную модель. **Не стал бы делать его обязательной зависимостью этой миграции.** Прямой `postgres` с явными typed repository methods — более предсказуемый старт; `Sql.named` сам по себе не даёт compile-time проверки SQL. [dsql](https://pub.dev/packages/dsql).

Аналогично, **`leto 0.0.1-dev.2`** предлагает GraphQL executor, DataLoader и extensions, но опубликованная dev-версия не даёт основания считать его очевидной современной заменой с меньшим эксплуатационным риском. [leto](https://pub.dev/packages/leto).

## 3. Настоящий параллелизм, admission и размер pool

### Один web isolate сначала

Один Dart isolate способен одновременно ожидать несколько PostgreSQL соединений. Для этого не нужен isolate на каждое ядро.

На 2 vCPU я бы начал с:

| Потребитель | Начальный лимит |
|---|---:|
| Основные web DB scopes | **4 соединения** |
| Одновременно тяжёлые FULL/MR scopes внутри этих четырёх | **1** |
| Auth/session | **1 отдельное соединение/pool** |
| Background DB work | **1** |
| LISTEN | **1 выделенное соединение** |
| Cancellation control, если используется `pg_cancel_backend` | **1 выделенное соединение** |
| Hasura | Начальный явно заданный предел **4**, затем измерение |

Это **экспериментальная стартовая конфигурация**, не вычисленный optimum. Четыре соединения не означают четыре одновременно полезных CPU-heavy MR вычисления.

Background isolate я бы сохранил: там есть декодирование изображений и blurhash, способные занять Dart CPU. Второй web isolate добавлять, если при свободных DB slots наблюдается устойчивый event-loop lag/CPU bottleneck. При этом общий DB budget делится между isolates, а не умножается.

### Одна ожидающая очередь

Сейчас constellation scheduler ограничивает только часть работы, поверх другой очереди Drift. В целевой модели:

- admission охватывает все основные DB scopes;
- тяжёлая работа классифицируется по use case, а не по первому слову SQL;
- ожидающие requests ещё не держат соединений;
- scheduler выдаёт разрешение только при наличии соответствующей ёмкости;
- pool остаётся механизмом lease/lifecycle, а не основной длинной очередью;
- запрос, срок которого истёк в очереди, **удаляется**, а не запускается позднее.

Начал бы с общей очереди порядка **32 ожидающих scopes**, дополнительного per-user ограничения и короткого queue budget:

- interactive — до **250 ms**;
- FULL refresh — до **1 s**, с объединением одинаковой работы;
- при перегрузке — немедленный `retryLater`, `429` или `503` по выбранному контракту.

Конкретные пределы нужно подбирать по burst-тестам. Но **1000 ожидающих работ на двухъядерной машине** для операций длительностью в секунды — накопление просроченной работы, а не запас производительности.

Приоритет writes должен оставлять refresh гарантированную долю обслуживания, но не запускать refresh, который уже не успевает в deadline.

## 4. Deadline и cancellation должны стать сквозным контрактом

### Что считать бюджетом

Нужен один `RequestContext`, например:

```text
requestId
actor
deadline / remainingBudget
cancellation
operationClass
```

Его бюджет включает auth refresh на клиенте, admission, получение соединения, SQL, retry backoff и формирование ответа.

Начальная политика:

| Класс | Пример server budget |
|---|---:|
| Auth/session | 2 s |
| Interactive mutation | 5 s |
| FULL snapshot | 10–12 s |
| Upload | Отдельные upload и finalize budgets |
| Background batch | Отдельный job budget + предел каждого SQL |

Это не означает, что mutation должна штатно занимать 5 секунд: целевой p95 гораздо ниже. Бюджет — граница отказа.

На каждом SQL:

```text
statement budget = min(остаток request deadline, предел данного SQL)
lock budget      = min(остаток deadline, короткий предел ожидания lock)
```

Retry использует тот же deadline. После его истечения не начинается следующая попытка.

`statement_timeout` действует на statement, `lock_timeout` — на ожидание блокировки; ни один не заменяет общий request deadline. [Документация PostgreSQL](https://www.postgresql.org/docs/16/runtime-config-client.html).

### Browser → сервер

`http 1.6.0` уже поддерживает отмену через `AbortableRequest.abortTrigger`; `BrowserClient` преобразует её в `AbortController.abort()`. [Документация http](https://pub.dev/packages/http#aborting-requests).

Однако установленный `gql_http_link 1.2.0` создаёт обычные `http.Request` / `MultipartRequest`: link.dart:152 (pub-cache `gql_http_link-1.2.0/lib/src/link.dart:152`).

Нужно заменить транспортный link или добавить поддерживающий отмену transport adapter:

- timeout завершает abort trigger;
- отмена последнего подписчика отменяет fetch;
- ожидающий auth refresh request после отмены не отправляет GraphQL;
- общий token refresh не отменяется из-за ухода одного потребителя;
- shared FULL/Dedupe-запрос отменяется только тогда, когда не осталось заинтересованных потребителей.

**Одного AbortController недостаточно для отмены SQL.** Caddy может закрыть upstream, но Shelf handler уже исполняется.

Стандартный `shelf_io` передаёт в context connection info, но не готовый request cancellation token: shelf_io.dart:197 (pub-cache `shelf-1.4.2/lib/shelf_io.dart:197`). Поэтому понадобится:

1. IO adapter, связывающий доступные transport disconnect/error события с `RequestContext`;
2. проверка этого поведения через настоящий Caddy;
3. server deadline как обязательная граница, даже если disconnect не был своевременно обнаружен.

Если немедленная отмена при навигации действительно нужна, можно передавать `cancel(requestId)` через существующий WebSocket. Проверять владельца запроса обязательно. Это дополнительный best-effort сигнал; сетевой разрыв всё равно должен ограничиваться server deadline.

### Сервер → PostgreSQL

Предпочтительная последовательность:

1. Удалить ещё не запущенную работу из admission queue.
2. Запретить новые SQL в отменённом scope.
3. Ограничивать активный SQL через server `statement_timeout` и `postgres.execute(timeout: remaining)`.
4. Для немедленной отмены — `pg_cancel_backend(pid)` через отдельное control-соединение либо закрытие исключительно принадлежащего scope соединения.
5. Дождаться завершения query protocol и rollback; только потом вернуть соединение.

`Future.timeout`, `Zone` и `CancelableOperation` сами по себе не останавливают SQL. Zone полезна для передачи контекста; отмена требует участия драйвера/сервера.

**Особенно важно:** нельзя отпускать lease и затем отправлять запоздалый `pg_cancel_backend`. Он отменяет текущий запрос backend, которым к этому моменту уже может владеть другой request. Нужны состояние scope, блокировка дальнейшей выдачи SQL и завершение cancellation до reuse. `pg_cancel_backend` возвращает факт отправки сигнала, не подтверждение rollback. [Документация PostgreSQL](https://www.postgresql.org/docs/16/functions-admin.html#FUNCTIONS-ADMIN-SIGNAL).

Для mutations потеря HTTP-ответа не доказывает rollback. Нужны idempotency keys и повторное получение результата. У anchor operations уже есть `client_op_id`/op log — полезный существующий образец: [constellation_anchor_repository.dart:52](../../packages/server/lib/data/repository/constellation_anchor_repository.dart).

## 5. Hasura, MeritRank и realtime

### Hasura входит в тот же ресурсный бюджет

У Hasura свой pool, но PostgreSQL и MeritRank общие. Admission только в Dart не ограничивает SQL, пришедший через Hasura.

В текущем production compose нет явно заданного ограничения Hasura pool в показанном environment; подключение использует роль `postgres`: [compose.prod.yaml:66](../../compose.prod.yaml).

Я бы:

- явно задал Hasura pool limits и SQL timeouts через поддерживаемые настройки источника;
- разделил runtime-роли Hasura, API, worker и migration;
- измерял Hasura отдельно через `application_name`/роль и query fingerprints;
- перевёл тяжёлые интерактивные MR-backed операции в V2, чтобы у них был один admission/deadline контракт.

**Полностью удалять Hasura в этом же проекте миграции не нужно.** Обычные чтения могут остаться. Нельзя лишь считать четыре Dart slots общесистемным ограничением.

### RPC из SQL остаётся отдельным ограничителем

Пока SQL вызывает pgmer2, одновременно заняты:

- PostgreSQL backend;
- leased connection;
- MVCC snapshot и уже взятые locks;
- ресурс MeritRank.

Увеличение pool может только увеличить число ожидающих MR запросов.

Репозиторий документирует уже внедрённый connector deadline с `CHECK_FOR_INTERRUPTS` через интервалы до 50 ms: [measurements.md:120](../../docs/plans/issue-235-constellation-interactive-measurements.md). Compose задаёт `MERITRANK_RECV_TIMEOUT_MSEC=10000`: [compose.prod.yaml:117](../../compose.prod.yaml).

Это хорошая основа, но upstream-код расширения и реально запущенные образы в этом обзоре не проверялись. **Blackhole/trickle/cancel тест должен быть acceptance gate на конкретном deployed image.** Также отмена ожидания в PostgreSQL не обязательно прекращает уже начатое вычисление в Rust-сервисе.

Долгосрочно самый полезный перенос границы:

> PostgreSQL хранит авторитетное состояние и локальные правила доступа; MR предоставляет версионированные вычисления/проекции, которые не удерживают пользовательскую write transaction во время внешнего RPC.

Но перенос visibility из SQL в Dart нельзя делать механически: Hasura тоже использует эти правила. Нужно сохранять fail-closed поведение, block checks и соответствие версии результата состоянию графа. Уже существующий epoch/generation cache m0235 — база для такого развития.

### LISTEN/NOTIFY оставить

Это подходящий механизм invalidation для текущего масштаба:

- одно выделенное LISTEN-соединение на web-процесс/isolate;
- вне transaction pool;
- reconnect вызывает reconciliation;
- повторные hints объединяются;
- после потери соединения клиент обновляет authoritative state.

Нужно помнить: NOTIFY не является durable очередью. Для задания, которое обязано выполниться, нужен outbox/job row. NOTIFY может лишь разбудить worker после commit.

Существующий single-flight FULL сохранить, добавив независимые deadlines подписчиков. Уже реализованные lazy refresh/coalescing не следует заменять простым «refetch на каждый hint».

## 6. Что из независимого аудита остаётся отдельной задачей

| Пункт | Вердикт и необходимое действие |
|---|---|
| **1. 15 s pool timeout против 30 s statement** | Конкретное несоответствие исправлено в `f12acbed5`. 35 s не решают длинную очередь и abandoned work. Цель — короткое admission-ожидание и общий deadline. |
| **2. S3 внутри транзакции** | **Подтверждается для ветки `runAction`.** `persist` включает attachments, затем выполняются `ImageRepository.put` / `putObject`. Нужен staged upload вне DB transaction и короткий finalize с повторной проверкой доступа. [beacon_room_case.dart:470](../../packages/server/lib/domain/use_case/beacon_room_case.dart), [beacon_room_case.dart:549](../../packages/server/lib/domain/use_case/beacon_room_case.dart), [beacon_room_case.dart:1538](../../packages/server/lib/domain/use_case/beacon_room_case.dart). |
| **2. Задача переживает rollback / запускается до commit** | **Подтверждается архитектурой:** schedule идёт через собственное соединение `PgJobQueue`, не через transaction session. Нужен outbox INSERT в той же транзакции. Вызов `schedule` просто после commit оставит противоположное окно потери при crash. [tasks_repository.dart:49](../../packages/server/lib/data/repository/tasks_repository.dart). |
| **3. Trust publisher ack** | До четырёх запросов на строку × 200, затем `mr_sync()` и epoch update внутри transaction — подтверждается. Это прежде всего **background lane**, но locks и MR общие. Нужны set-based ack и отдельно проверенный протокол publish/epoch, а не простое удаление `mr_sync`. [trust_publish_repository.dart:99](../../packages/server/lib/data/repository/trust_publish_repository.dart). |
| **3. Attention clear/undo** | С уточнением: apply phase уже разбита на отдельные bounded transactions. **Capture** всё ещё построчный в одной transaction; undo тоже обрабатывает весь набор. [attention_sweep_repository.dart:79](../../packages/server/lib/data/repository/attention_sweep_repository.dart), [attention_sweep_repository.dart:120](../../packages/server/lib/data/repository/attention_sweep_repository.dart), [attention_sweep_repository.dart:956](../../packages/server/lib/data/repository/attention_sweep_repository.dart). |
| **3. User erasure / contact sweep** | Подтверждается. Erasure обходится одной внешней транзакцией; contact sweep ограничен 200, но ledger пишет строки по одной. Использовать set-based SQL; для действительно больших erasure — закрытие доступа и возобновляемые batches с явной семантикой удаления. [user_erasure_case.dart:48](../../packages/server/lib/domain/use_case/user_erasure_case.dart), [trust_ledger_repository.dart:22](../../packages/server/lib/data/repository/trust_ledger_repository.dart). |
| **4. Scheduler Zone** | **Подтверждается риск переноса контекста.** Callback не привязан к Zone постановщика; следующий `_pump` может запускаться из Zone предыдущей работы. Нужно сохранять caller Zone либо передавать контекст явно. Новый pool этого не исправит. [constellation_db_scheduler.dart:74](../../packages/server/lib/data/service/constellation_db_scheduler.dart), [constellation_db_scheduler.dart:130](../../packages/server/lib/data/service/constellation_db_scheduler.dart). |
| **5. Оставшийся await-gap** | Исправлен текущим `_route`, повторно принимающим решение после ожидания. [tentura_db.dart:388](../../packages/server/lib/data/database/tentura_db.dart). |
| **6. `prepare` / `batch`** | `prepare` теперь использует `_route`; утверждение о безусловном обходе pinning устарело. Но Drift `batch()` действительно начинает transaction непосредственно через executor, минуя override `TenturaDb.transaction`. Для default-пути латентная проблема остаётся. `.batch(` в `server/lib` не найдено. batch.dart:235 (pub-cache `drift-2.34.3/lib/src/runtime/api/batch.dart:235`). |
| **7. Постоянный pin под нагрузкой** | Возможен: `_pins` учитывает перекрывающиеся вызовы, поэтому соединение может не возвращаться в pool между транзакциями. Это не «никогда» безусловно, а starvation lifecycle при непрерывной нагрузке. Scoped lease устраняет причину. [tentura_db.dart:400](../../packages/server/lib/data/database/tentura_db.dart). |
| **8. Вложенный RR** | Подтверждается проблема контракта. В plain transaction попытка `SET TRANSACTION` может оказаться внутри savepoint/после SQL. Внутри `withMutatingUser` RR вообще присоединяется без повышения изоляции. Нужна явная проверка isolation compatibility. [tentura_db.dart:288](../../packages/server/lib/data/database/tentura_db.dart). |
| **9. Cross-process lock waits** | Останутся. Pool локализует ущерб одним leased connection, но не убирает SQL contention. Нужны `lock_timeout`, порядок блокировок и корректные whole-transaction retries. |

Два дополнительных замечания:

**Pool lifecycle сейчас неявный и, по показанному пути, незавершённый.** `TenturaDb.dispose()` вызывает `super.close()`, а `PgDatabase.opened` не закрывает underlying session. Spike тоже вызывает только `_root.close()`. В target pool должен иметь явного владельца и отдельный `close()` после drain scopes. [tentura_db.dart:357](../../packages/server/lib/data/database/tentura_db.dart), pg_database.dart:148 (pub-cache `drift_postgres-1.3.1/lib/src/pg_database.dart:148`).

**В m0235 есть общая строка `visibility_trust_generation`.** Триггеры trust/block изменений обновляют её. Это реальная точка сериализации и часть lock graph, которую увеличение pool не устранит: [m0235.dart:27](../../packages/server/lib/data/database/migration/m0235.dart). Перед расширением write concurrency её нужно включить в contention-тесты.

## 7. Переход небольшими релизами

| Шаг | Изменение | Что измерять / условие приёмки |
|---|---|---|
| **1. Зафиксировать наблюдаемость** | Spans: admission wait, pool acquire, transaction lifetime, SQL, retry backoff, cancellation drain. Теги operation, work class, isolate, backend PID. | Отделять queue time от SQL time; знать число ожидающих, running и abandoned requests. Снять baseline смешанной нагрузки. |
| **2. Обновить `postgres`** | 3.5.12 → 3.5.20 без изменения concurrency. Явное закрытие pool. | Ошибки SQL, timeout, rollback failure, backend termination, повторное использование после отмены, shutdown без оставшихся соединений. |
| **3. Исправить независимые дефекты** | Zone scheduler, RR nesting contract, transactional outbox. Staged attachments отдельным релизом. | Два разных actor/context в очереди не смешиваются. Rollback не оставляет job. Crash после commit не теряет job. S3 latency не увеличивает transaction lifetime. |
| **4. Пилотировать scoped DB access** | Перевести целиком одну transaction boundary со всеми участвующими репозиториями. Остальной код временно остаётся на старом пути; общий connection budget ограничен. | `pg_sleep`/barrier доказывают параллельные backend PID. Actor/GUC не протекают. Nested savepoint, batch и rollback корректны. Внутри transaction нет второго lease. |
| **5. Перевести основные V2 scopes** | Удалить pin shim и spike после ухода последнего caller. Один bounded admission вместо constellation-only очереди и глобального Drift lock. | FULL выполняется одновременно с короткой mutation; auth latency остаётся стабильной. Перегрузка даёт быстрый отказ, очередь и RSS ограничены. |
| **6. Ввести сквозную отмену** | Request deadline, browser abort, server cancellation context, SQL cancellation и drain. | Через Caddy: отмена до admission, в очереди, во время SQL, на lock wait, во время MR RPC, около commit. Никакая отмена не попадает в следующий request. |
| **7. Сократить SQL/transaction cost** | Set-based publisher ack, attention capture/undo, ledger inserts; ограниченные background batches. | Число SQL на операцию, lock-held time, p95/p99, rollback cost. Проверить прежнюю атомарность и idempotency. |
| **8. Настроить общую ёмкость** | Сравнить 1 и 2 web isolates при одинаковом суммарном pool; согласовать Hasura/MR limits. | Максимальная устойчивая throughput при заданном p95, а не максимальное число in-flight запросов. |

Для шага 4 мигрировать нужно **use case целиком**, а не произвольный отдельный repository method: иначе одна бизнес-транзакция незаметно расколется между старой и новой DB session.

Нагрузочная матрица должна включать:

- одного и нескольких пользователей;
- одинаковые и разные viewers для FULL;
- warm/cold visibility cache и публикацию нового MR epoch;
- FULL + anchor writes + auth refresh + Hasura reads + publisher;
- внешний row lock;
- медленный/недоступный MR;
- client abort и потерю соединения;
- истечение возраста connection и shutdown под нагрузкой.

Основные acceptance gates:

- отсутствует общий DB mutex между независимыми scopes;
- истёкшая queued работа не стартует;
- нет actor/GUC leakage, `25P01` и неопределённого transaction ownership;
- cancellation не отменяет чужой SQL;
- число соединений и длина очереди ограничены;
- при перегрузке latency не растёт бесконечно;
- SQL deadlock/serialization retries укладываются в общий deadline;
- background работа не лишает interactive и auth запросы обслуживания.

Проверки PostgreSQL и MR проводить через проектный cleanup wrapper, последовательно; MR-прогоны не запускать параллельно из-за общего сервиса.

**Полную замену Drift я бы не ставил условием успеха.** Сначала нужно исправить владение session и границы работы. Это даст параллелизм, отмену и предсказуемую перегрузку, сохранив уже написанные typed repositories. После этого отдельные SQL-heavy участки можно переводить на прямой `postgres`, когда это действительно уменьшает код и упрощает проверку транзакционного контракта.