# RedactionRules

The deterministic rules Envelope uses to remove personal data from a letter
**on the device**, before any text is sent anywhere.

They are published so the claim can be checked rather than believed. No part of
this package talks to the network, and it depends on nothing but Foundation.

```
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

## Layout

```
Sources/RedactionRules/
  RedactionEngine.swift    rule order, placeholder assignment, restore
  LetterStructure.swift    letterhead, recipient block, salutation, body
  ProtectedSpans.swift     what must never be masked
  Rules/                   one file per PIIKind
  Countries/               one file per national identity format
  Salutations/             one file per language
  Validators/Checksums.swift
```
