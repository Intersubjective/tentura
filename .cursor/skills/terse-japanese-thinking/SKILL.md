---
name: terse-japanese-thinking
description: Use impolite, maximally terse Japanese (タメ口/ぞんざい語) in thinking blocks and subagent prompts to conserve tokens. User-facing output—including any direct questions to the user—must be in the user's native language or English, never Japanese. Use proactively on every response that involves internal reasoning or subagent delegation.
---

# Terse Japanese Thinking & Subagent Communication

## Rule

All `<thinking>` block content and all Task tool `prompt` values MUST be in raw, blunt Japanese. User-facing text stays in the user's language.

**Questions to the user:** Anything you ask the user directly (clarifications, choices, confirmations) MUST be written in **their native language** or **English**—never Japanese. Japanese is only for internal thinking and subagent prompts.

## Style

- **タメ口 only.** No です/ます. No 敬語. No丁寧語.
- **Omit particles** when meaning is obvious: 「ファイル読む」not「ファイルを読む」
- **Omit subjects/pronouns.** Context makes them redundant.
- **Use short forms:** 「やる」「見る」「直す」「要らん」「ダメ」「おk」
- **Abbreviate freely:** 「それ無理」「先にgrep」「型合わん」「ここバグ」
- **Mix in English** for code identifiers, tool names, file paths — don't transliterate them.
- **No filler.** No「えーと」「そうですね」「～と思います」. State conclusions directly.
- **Lists over prose.** Bullet raw observations, skip narrative.

## Thinking Examples

Bad (wasteful):

```
Let me think about this. The user wants to add a new endpoint.
I should first check the existing router configuration to understand
the current patterns being used. Then I'll need to create the handler
function and register the route. Let me also consider error handling...
```

Good (terse Japanese):

```
新エンドポイント追加。
- router設定確認する
- handler作る
- ルート登録
- エラー処理要る
先にrouter.dart読む
```

Bad (polite Japanese — token waste):

```
ユーザーさんが新しいエンドポイントを追加したいとおっしゃっています。
まず、既存のルーター設定を確認させていただきたいと思います。
```

Good:

```
endpoint追加。router見る。
```

## Subagent Prompt Examples

Bad (verbose English prompt to Task tool):

```
Please search the codebase for all files that define a repository class
extending RemoteRepository. I need to understand how they handle error
cases and what patterns they follow for retry logic. Return a summary
of each repository found with its file path and key methods.
```

Good (terse Japanese prompt to Task tool):

```
RemoteRepository継承してるrepositoryクラス全部探せ。
- ファイルパス
- エラー処理パターン
- retry有無
まとめて返せ。
```

Bad (polite Japanese prompt — token waste):

```
リポジトリクラスを検索していただけますか。
RemoteRepositoryを継承しているものを探していただきたいです。
```

Good:

```
RemoteRepository継承クラス全探索。パス・エラー処理・retry有無返せ。
```

## Boundaries

- Thinking blocks: Japanese.
- Subagent prompts (Task tool `prompt` field): Japanese.
- Task tool `description` field: English (short, 3-5 words as required by tool).
- User-facing messages, code, comments, commit messages: user's language (or English if unclear).
- **Direct questions to the user:** user's native language **or** English only—**not** Japanese (even if your internal monologue is Japanese).
- Tool call parameters (except Task `prompt`): always English (tool names, file paths, commands).
