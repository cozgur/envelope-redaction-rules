# RedactionRules

The deterministic rules **Postklar** uses to remove personal data from a letter
**on the device**, before any text is sent anywhere. (The app's repository and
this package still carry its codename, Envelope.)

They are published so the claim can be checked rather than believed. No part of
this package talks to the network, and it depends on nothing but Foundation.

```
git clone https://github.com/cozgur/envelope-redaction-rules.git
cd envelope-redaction-rules
swift test
```

That runs every rule against every fixture in about a second. If it passes, the
rules in this repository do what the rest of this file says they do.

## What is masked

Each value is replaced by a typed, indexed placeholder — `[IBAN_1]`,
`[ID_NUMBER_2]` — and the mapping back to the original stays on the device. The
same value always gets the same placeholder within one letter, so a reference
quoted four times reads as one reference.

| Kind | How it is found |
|---|---|
| `idNumber` | Per-country patterns, each with the country's own checksum: NL *elfproef*, DE ISO 7064 MOD 11,10, FR NIR key, ES DNI/NIE control letter, PL PESEL, TR TCKN, US SSN structure, UK NINO prefixes. Plus any 8–12 digit run beside an identity keyword, valid or not. |
| `iban` | Mod-97. Plus an account-shaped token beside an IBAN keyword, valid or not. |
| `cardNumber` | Luhn, 13–19 digits. |
| `phone` | `NSDataDetector`, a grouped-digit pattern for the European formats it misses, and a keyword rule for short service numbers. |
| `email` | Pattern. |
| `address` | The recipient's address block, masked whole — see below. Plus `NSDataDetector` hits elsewhere. |
| `reference` | The *shape* official mail uses: a field line whose label ends in, or contains as a word, a reference stem (`nummer`, `référence`, `sprawy`, `esas`…). Not an enumerated list of labels. |
| `name` | The salutation, per language. |

## What is deliberately **not** masked

A letter whose numbers are gone cannot be explained at all, which is a worse
failure than a leak. These survive every rule:

- **dates** — in seven languages, written and numeric
- **amounts and percentages** — with or without a currency symbol
- **postcodes standing alone** — though a postcode inside a recipient block
  goes with the block
- **the sender's letterhead** — masking it deletes the one thing an
  explanation most needs: who wrote

## What the engine hands back

```swift
let result = RedactionEngine.redact(letter, countryHint: "NL")

result.redactedText   // the only form allowed to leave the device
result.map            // "[IBAN_1]" -> the real IBAN; never leaves the device
result.counts         // how many distinct values, by kind
result.spans          // every replacement, with the offsets it stands at
```

`spans` is the audit record. The map answers *what does `[IBAN_1]` stand for*;
`spans` answers *what stands at character 412*, which is the question an audit
actually asks — a value can be masked correctly in one place and wrongly in
another, and only position tells the two apart. Each span carries its
placeholder, the kind the engine decided on, its offsets in the original text
and its offsets in the redacted text.

The kind matters beyond bookkeeping. A masked value is masked whichever label
it got, but the app resolves placeholders by kind when it fills a reply header,
so an identity number labelled `[CARD_NUMBER_1]` produces a wrong letter rather
than a leak. The golden-set suite asserts the kind of the placeholder standing
at every known value's position, for exactly that reason.

## The numbers in the fixtures

The corpus is public, so a fixture that happened to carry a real person's
identity number would be exactly the harm this engine exists to prevent.
Wherever an issuing authority sets a range aside for test data, the fixtures
use it — those ranges exist because nothing in them can belong to anyone.

| | Source |
|---|---|
| **NL** BSN | RvIG's `999xxxxxx` test range, still passing the elfproef |
| **US** SSN | `987-65-4320`–`987-65-4329`, reserved by the SSA for advertising |
| **UK** NINO | the `QQ` prefix, which HMRC never issues |
| **DE** Steuer-IdNr | the BZSt's published example number |
| **ES** DNI/NIE | the canonical documentation examples |
| IBANs | the ISO 13616 registry's own example IBANs |

Every one is checked against the same checksum the engine validates with
before it reaches a letter, so a misremembered digit fails the generator rather
than shipping quietly.

Two of those ranges are admitted by the rules on purpose. An SSN in the 9xx
range and a NINO on a Q prefix are never issued, and the general rules reject
them for that reason — but redaction asks what *looks* identifying, not what an
authority actually issued. A letter printing `987-65-4320` is printing
something every reader and every scraper reads as an SSN, and masking a number
that can belong to nobody costs nothing.

### Where no reserved range exists

**France, Poland and Turkey publish neither a reserved range nor an example
number.** Those fixtures are fabricated: valid against their country's
checksum, which is what makes them useful, and generated from a fixed seed so
the corpus is reproducible.

They are not drawn from any register, but a checksum-valid number is by
definition one that *could* be issued, so a coincidental match with a real
number cannot be ruled out. If you believe one of these numbers is yours, open
an issue naming the country and the file — not the number — and it will be
rotated.

## Names, and the limit of doing this without a model

Names are caught in the two places official letters put them:

1. **The recipient address block.** Everything between the letterhead and the
   date line that looks like an address is masked as a single `[ADDRESS_n]`,
   name line included. The name is removed without ever being recognised as a
   name. `NSDataDetector` is treated as evidence rather than as the answer: it
   finds no address at all in Dutch or Polish blocks, and where it does hit it
   returns the street and postcode without the name line above them.
2. **The salutation.** Per-language patterns keep the honorific and mask the
   name: *Geachte mevrouw [NAME_1],*. Once the name is known, every other
   occurrence of it in the letter is masked too.

**A third party named in the body is not masked.** Finding those needs a model,
and a model that reads the letter is the thing this package exists to avoid.
That is a real gap, stated here rather than discovered later.

## One value, masked everywhere

Once a rule recognises a value, every other appearance of it in the letter is
masked too. Official mail repeats a reference three or four times and only the
first sits beside a label, so without this a letter leaks the reference it
just masked.

That spreading is guarded, because it is also the most destructive thing the
engine can do with a false positive. A value is **not** spread when it is:

- **shorter than four characters** — every identifier here is longer, and
  almost every function word is shorter;
- **a function word** in any of the seven languages — articles, prepositions
  and conjunctions, matched without regard to case or diacritics.

The guard exists because it has been needed. A reference pattern once returned
the Spanish article `de`, and the engine replaced every `de` in the letter.
Nothing about the result said which words had been ordinary, which is what
makes this failure worth guarding twice: the pattern was tightened *and* the
spread was bounded.

The cost is a surname of two or three letters — Li, Ng, Wu — whose
*recurrences* in the body are left alone. The salutation itself is still
masked, because that is a direct rule match rather than a repeat. A short name
surviving in one sentence is a smaller harm than every article in the letter
being replaced.

## Contributing a rule

Every rule lands with **positive and negative fixtures**. A rule that only ever
fires is as broken as one that never does — over-redaction destroys the letter.

- **A country's identity number** → one file in `Sources/RedactionRules/Countries/`,
  a `NationalIDFormat` with a pattern and a checksum, added to
  `NationalIDFormat.all`. Tests: valid numbers accepted, numbers that differ by
  one digit rejected.
- **A language's salutation** → one file in `Sources/RedactionRules/Salutations/`,
  a `SalutationTemplate` with a personal pattern and a generic one, added to
  `SalutationTemplate.all`. Tests: the personal form yields the name, and **at
  least two generic openings in that language yield nothing**.
- **Anything else** → a `RedactionRule` in `Sources/RedactionRules/Rules/`,
  one file per `PIIKind`.

Three things that have already cost a bug here, so they are worth knowing:

- **Bound your keywords.** An unbounded `al` matches inside *Estatal* and
  *Mahallesi*, and the house number beside it is then masked as a phone
  number. Use `KeywordPattern.alternation`.
- **Anchor on shape, not on a list.** Reference labels are invented fresh by
  every authority; their *shape* is not.
- **A protected span vetoes whatever overlaps it.** If a rule stops firing,
  check whether something it overlaps is protected before rewriting the rule.

## Where this comes from

This repository is a mirror. The rules are developed inside the Postklar app's
repository and pushed here whenever they change, by a script that refuses to
publish a tree whose tests do not pass. What is here is what ships.

Licensed under Apache 2.0. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Layout

```
Sources/RedactionRules/
  RedactionEngine.swift    rule order, placeholder assignment, restore
  RedactionResult.swift    the redacted text, the map, the counts, the spans
  LetterStructure.swift    letterhead, recipient block, salutation, body
  ProtectedSpans.swift     what must never be masked
  Rules/                   one file per PIIKind
  Countries/               one file per national identity format
  Salutations/             one file per language
  Validators/Checksums.swift
```
