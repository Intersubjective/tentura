# Tentura beacon evaluation: principles, failure modes, and hard no-go rules

## Purpose

Post-beacon evaluation exists only to leave a local trace of how a concrete cooperation path worked.
It is not a public reputation ritual, not a morality scoreboard, and not a performance review system.

## Core principles

* Evaluate contribution to this beacon, not the person in general.
* Keep evaluation local, subjective, contextual, and tied to a concrete episode.
* Treat authoring, committing, and forwarding as different kinds of contribution.
* Optimize for future routing quality, not visible status.
* Preserve honest signal while minimizing retaliation, politeness inflation, and clique gaming.
* Keep raw evaluations private by default.
* Give users legibility about outcomes without turning evaluation into interpersonal combat.
* Allow “no basis to judge” as a first-class option.
* Make strong judgments require a reason.
* Keep single-beacon effects bounded; no one beacon should define a person.

## What evaluation is for

* remembering which paths worked
* remembering which commitments were reliable
* remembering which forwarding was useful or noisy
* improving future routing and trust calibration

## What evaluation is not for

* public social ranking
* leaderboards
* rewarding popularity or fluency
* making authors sovereign judges of everyone else
* building a visible caste system

## Main social failure modes

### 1. Retaliation

People punish negative evaluators or pre-emptively avoid honest negatives.

### 2. Politeness inflation

Everyone gives mild positives to avoid friction, making the signal meaningless.

### 3. Reciprocity trading

People exchange positive ratings regardless of actual contribution.

### 4. Clique capture

Friends inflate each other and downgrade outsiders.

### 5. Halo effect

One visible or likable action contaminates the whole judgment.

### 6. Role flattening

Author, committer, and forwarder get judged on one generic scale despite doing different things.

### 7. Attribution error

People punish character instead of judging the actual contribution under actual constraints.

### 8. Visibility bias

Legible, on-app, verbal, or central contributions get over-credited; invisible work gets ignored.

### 9. Author sovereignty

If the author closes the beacon and effectively controls judgment, hidden hierarchy appears.

### 10. Hidden punishment

If evaluations silently affect future routing with no visible explanation, the system feels arbitrary.

### 11. Forced-opinion noise

If users must rate people they did not really observe, the dataset becomes junk.

### 12. One-beacon stain

A single conflict or failed beacon disproportionately harms future trust.

## Hard no-go rules

Never do any of the following:

* never show public cumulative evaluation scores for people
* never show leaderboards or “top contributors” based on these evaluations
* never reveal raw named submissions by default
* never let everyone see “Alice rated Bob -2” as normal UI
* never force users to rate people they did not directly observe
* never use one generic prompt like “rate this person”
* never collapse all roles into one undifferentiated rubric
* never make negative ratings frictionless
* never let a single author become the uncontestable judge of the beacon
* never apply heavy MR consequences from one beacon without safeguards
* never show live mutual evaluations while the review window is open
* never conflate “neutral” with “no basis to judge”
* never turn evaluation into a chat thread or debate arena
* never reward verbosity, visibility, or social fluency more than actual closure contribution
* never expose these evaluations outside people involved in the beacon

## Required safeguards

* include “No basis” as an explicit option
* use role-specific evaluation prompts for author / committer / forwarder
* require a reason tag for strong positive and negative ratings
* keep raw submissions private; show only beacon-local summaries to the evaluated person
* keep evaluation bounded to a review window after closure
* support contesting unfair closure or obviously unfair evaluation later
* keep effects local, decayed, and aggregated over time

## Recommended framing in product language

Use:

* Close the loop
* Acknowledge contributions
* How did this contribution affect this beacon?

Avoid:

* 360 review
* Rate this person
* Reputation score
* Contributor ranking

## Minimal product posture

Evaluation should feel like a quiet accounting trace left after cooperation, not like a ritual of judgment.
If users experience it as HR, politics, or public status competition, the feature has failed.
