<!--
Purpose: Take a snapshot, capture Lua errors, and open a useful issue.
Type: How-to
Audience: players with a problem
Prerequisites: None.
-->
This page shows how to report a problem with Hekili Forever so that it can be fixed: take a snapshot while the problem is on screen, capture any Lua error, and open an issue on GitHub. Check [Troubleshooting and FAQ](Troubleshooting-And-FAQ) first; the problem may have a known fix.

Hekili Forever problems go to the Hekili Forever issue tracker only, never to the original Hekili project.

## Take a snapshot

A snapshot records how Hekili Forever chose the recommendations on screen at that moment: your talents, settings and toggles, the enemies counted, your buffs and debuffs, and each line of the priority it tested. It is the most useful part of a report about a wrong recommendation. [Reading a snapshot](Reading-A-Snapshot) explains what it contains.

1. Wait until the problem is on screen, for example the wrong ability in the first icon. A snapshot from before the pull does not show a problem that happens twenty seconds into a fight.
2. Take the snapshot in one of these ways:
   - press the **Snapshot** key, ALT-SHIFT-[ by default;
   - press the **Pause** key, ALT-SHIFT-P by default, which also freezes the displays (press it again to resume);
   - type `/hekili snapshot`, or `/hek snap`, for example from a macro.
3. Open **/hekili > Snapshots (Troubleshooting)**.
4. Choose the snapshot in **Select a Snapshot**. Each entry starts with the time it was taken and the display it describes.
5. Click the text box that appears, press Ctrl+A to select all of it, then Ctrl+C to copy it. A snapshot is hundreds of lines long.
6. Paste it into a text file and save it, to attach to the issue.

With **Take Screenshot** checked, Hekili Forever also takes a game screenshot when you take a snapshot. A screenshot of the displays at that moment helps too.

<!-- TODO-SCREENSHOT: the Snapshots tab with a snapshot selected -->

## Capture Lua errors

A Lua error is a message about a fault in an addon's code. Capture its full text:

- with an error-catching addon such as BugSack with BugGrabber: reproduce the error, open BugSack and copy its text; or
- with the game's own error display: type `/console scriptErrors 1`, then reproduce the error and copy the text from the error window. <!-- UNVERIFIED: the client UI source gives the error window an edit box (ScriptErrorsFrameMixin:GetEditBox), so its text is selectable; not clicked in game. -->

Hekili Forever also keeps its own list of problems it noticed while running, on **/hekili > Warnings**, and copies it into each snapshot under "Warnings".

## Open an issue

Open a new issue at [github.com/zmsl/hekili/issues](https://github.com/zmsl/hekili/issues). Include:

- the Hekili Forever version (the first lines of a snapshot give it), your class, specialization and level;
- what you expected to see, and what Hekili Forever showed instead;
- the snapshot, attached as a text file or pasted into the issue;
- the full text of any Lua error.

One issue per problem makes each one easier to follow.

## See also

- [Accuracy](Accuracy): known differences from the wowsims.com rotations
