Measured on perf DB `tentura_test_lane_hold_perf`. Samples: `docs/performance/lane-hold-transactions.json`. Source SHA-1 before `df3a45d54108938fda423293056af204630b436c`, after `7ef23a5d704ef2897e87475f7360dcd555f5bc52` (frozen source trees, not new commits).

| Path | Rows | Before worst lane hold (ms) | After worst lane hold (ms) |
| --- | --- | --- | --- |
| trust_publish_ack | 200 | 1007.75 | 29.399 |
| attention_capture | 1201 | 432.076 | 47.001 |
| attention_apply | 200 | 63.614 | 29.152 |
| attention_undo | 1201 | 3112.124 | 44.576 |
| user_erasure_published | 1201 | 5569.405 | 1682.228 |
| user_erasure_drafts | 1201 | 2213.326 | 173.879 |
| contact_resolution | 200 | 1496.415 | 1422.579 |
