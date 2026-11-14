<!--
Purpose: The writing and formatting rules for these pages.
Type: Reference
Audience: contributors
Prerequisites: None.
-->
The **style guide** sets the writing and formatting rules for the pages of this wiki. Wikipedia's Manual of Style is the reference: concept and reference pages follow its article conventions, and how-to and tutorial pages follow its help pages, which are written as instructions. How the pages are built and checked is in [Contributing docs](Contributing-Docs).

## Page types

Every page is exactly one type, named in the comment at the top of its file.

| Type | Lead | Person and mood | Body | Ends with |
|---|---|---|---|---|
| Explanation | The first sentence defines the subject, with the subject in bold. The lead summarises the page and stands alone. | Third person, present tense. No "you". | Sections by subtopic; prose, with a table where facts compare | See also |
| How-to | One or two sentences: the goal, and who needs it. Links the matching explanation. | Second person, imperative steps | Before you start, numbered steps of one action each, then a way to check that it worked | See also |
| Reference | Defines the scope, what is included, and which tables are generated | Third person; fragments allowed in table cells | One table per group, one row per item; edge cases as a list under each table | See also |
| Tutorial | States the end result and the time it takes | Second person, never "we" | Numbered steps, each with a visible result; one path, no choices | Next steps |

## Writing

| Rule | How it applies |
|---|---|
| Lead first | The text before the first level-two heading is the lead, with no "Introduction" heading. One to three short paragraphs. |
| Subject in bold, once | On explanation and reference pages, the first sentence bolds the page's subject. |
| Neutral tone | No "powerful", "simply", "just", "easy" or "perfect". Say what a thing does. |
| Date changeable facts | State the fact plainly ("the game hides ..."), never "currently" or "recently"; the footer carries the version. |
| Link the first mention | Link another page at its first mention only, plus See also. |
| Define jargon on first use | For example: "An action priority list (APL), the text form of a priority". Developer pages define belief, band and facade, or link the [Glossary](Glossary). |
| See also | Lists only pages not already linked in the body, each with a few words when the name is not clear. |
| No first person | No "we", "our" or "I". The project is "Hekili Forever". |
| Verifiable | Every claim can be checked against the released code or a dated in-game measurement. A fact that cannot be checked gets an HTML comment starting `UNVERIFIED:`, not a guess. |
| Plain English | Short sentences, short paragraphs, active voice, one idea per paragraph. |

## Terminology

| Term | Rule | Example |
|---|---|---|
| Hekili Forever | The product, in prose. "Hekili" alone only in code identifiers and in "the original Hekili" or "retail Hekili". | "Unlike retail Hekili, ..." |
| Priority and APL | "Priority" on player pages, matching the **Priorities** panel. "APL" only on the Write priorities pages, defined at first use. Page names keep the APL- prefix. | "An action priority list (APL) is the text form of a priority." |
| UI labels | Bold, spelled exactly as in `src/Hekili/Locales/enUS.lua`. A path starts at /hekili and uses " > " between parts; a placeholder part is in italics. | See the example below |
| Expressions | Code style, written as a priority line writes them, with no spaces around operators. A placeholder is in angle brackets. | `mana.pct_lo<30`, `buff.<aura>.up` |
| Settings | Players see the label. Priority authors see the key in code with the label beside it. Internal option keys appear only on developer pages. | `settings.behind` |
| Spells and abilities | Plain text with the game's capitals. The ability key in code only where a line uses it. | Shred; the `shred` line |
| Hidden values | Player pages say "hidden" and "estimated". "Secret value" and "belief" appear only on developer pages. | "The game hides target health." |
| Commands | Code style, the full form first and the alias after | `/hekili snapshot` (alias `/hekili snap`) |
| Numbers | With their unit. Yards spelled out in prose, "s" for seconds in tables. Accuracy to three decimals. | 10 yards, 3600 s, 0.975 |
| Dates | ISO format | 2026-11-07 |

A UI label and an options path, as written in a page's source:

```text
Check **Count Nameplates Near You** in **/hekili > Priorities > *your specialization* > Targeting**.
```

## Formatting

The pages use portable GitHub Markdown only: standard links, no `[[...]]` wiki links and no HTML styling.

| Element | Rule |
|---|---|
| Headings | No level-one heading: GitHub shows the page name as the title. Level two for sections and level three below them, never level four. Sentence case, unique on the page, no trailing punctuation, no links or code. |
| Infobox | Only on a page about one thing, such as a setting, a command or a priority. A two-column table straight after the lead, the subject's name in the header row with an empty second cell, then three to six rows of facts. |
| Tables | For comparable facts only. Sentence-case headers, with units where they apply. The first column is the item. No cell longer than one sentence. Write "n/a" for an empty cell and state its meaning under the table. |
| Generated tables | An empty marker pair in the source, filled at publish time ([Contributing docs](Contributing-Docs#add-a-generated-table)). Never edited by hand. |
| Callouts | Two kinds, each with a bold lead-in, so that the text still reads if alerts do not render (see below) |
| Code | Always fenced with a language: `simc` or `text` for priority lines, `lua` for class files, `sh` for make targets, and `text` for chat commands. A line above names the source, such as "From Feral (wowsims.com):". Long generated lines are shortened with `...`. |
| Screenshots | Only where a picture replaces a paragraph. PNG at 1x UI scale, cropped to the subject, at most 800 pixels wide and 500 KB, in `images/` as `<Page-Name>-<n>.png`. Alt text says what is shown and its state. An HTML comment after the image records the version, class and place it was taken. |
| Planned screenshots | An HTML comment starting `TODO-SCREENSHOT:` and naming the subject, where the picture belongs |
| Links | Internal links name the page, with an optional heading anchor. Links to code are absolute links to the `forever` branch on GitHub. External links go only to wowsims.com, CurseForge and GitHub. |

The two callouts, as written in a page's source:

```text
> [!NOTE]
> **On Forever:** The game hides target health, so every time-to-die value reads 3600 seconds.

> [!WARNING]
> **Different from retail Hekili:** A priority does not need pool_resource to wait for energy.
```

"On Forever" marks a limit of the client. "Different from retail Hekili" marks the same name with different behaviour.

## Content that never goes in a page

`make wiki-check` fails a page that holds any of these, in its text or its comments:

- a local file path, such as a home directory or a Windows user folder, or a machine name;
- a hidden or debug switch, or a chat snippet that reaches into the addon's internals;
- an internal ledger, ruling or lane number;
- a link to a private artifact.

Also left out: personal details, links or contact details for the original project beyond the footer's credit, plans for unreleased versions, and version-history pages. The fork notice is in the footer and is not repeated on pages. The core is generic: class-specific facts are presented as belonging to the class packs.

## See also

- [Contributing docs](Contributing-Docs)
- [Contributing](Contributing)
