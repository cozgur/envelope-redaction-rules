# Contributing

The rules in this repository decide what leaves a person's phone when they scan
a letter into Postklar. A change
here is a change to that, so every one lands with fixtures that prove both
directions.

**Read [the README](README.md#contributing-a-rule) first** — it says where each
kind of rule lives and what its fixtures have to show.

## The short version

1. `swift test` must pass before and after your change.
2. A new rule needs **positive and negative fixtures**. A rule that only ever
   fires is as broken as one that never does: over-redaction destroys the
   letter it was meant to protect.
3. A national identity format needs its country's real checksum, not just a
   digit-count pattern. Without one, ordinary invoice numbers get masked.
4. Say in the pull request which country or language you are adding and, if
   you can, cite the authority's published format.

## What will be turned down

- A rule with no negative fixture.
- A pattern that masks dates, amounts or postcodes. A letter whose numbers are
  gone cannot be explained at all, which is worse than the leak the rule was
  trying to prevent.
- Anything that adds a dependency. This package builds on Foundation alone so
  that a stranger can clone it and verify the claim in one command.
- Anything that sends data anywhere. There is no network code here, and there
  will not be.

## Reporting a gap rather than fixing it

If you have received an official letter this engine would not have masked
properly, an issue describing the **format** is welcome and useful. Please do
not paste the letter: describe the shape of what was missed
("Belgian national number, 11 digits, printed as NN.NN.NN-NNN.NN"), not your
own data.
