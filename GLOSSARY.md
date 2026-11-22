# Glossary

A text calculator for the Mac. This glossary defines the words that the product, its documents, and its code use for the same concepts.

## Language

**Sheet**:
A saved, named page of text that holds expressions, variables, headings, comments, and text lines, in a format close to Markdown. Variables and earlier expressions in a sheet keep their meaning until someone deletes them.
_Avoid_: note, calculation, document, file

**Expression**:
One line of a sheet that evaluates to a result.
_Avoid_: calculation, formula, line

**Variable**:
A name that an expression in a sheet gives a value, as in `price = 8`. Later expressions in the same sheet use the name in place of the value, and a name used before its first definition is an error.
_Avoid_: constant, field, parameter

**Reserved name**:
A name kept for the language that a variable cannot take, such as `min`, `pi`, `and`, a unit or a currency. Assigning to one is an error.
_Avoid_: keyword, reserved word, protected name

**Heading**:
A line of a sheet that starts with one to six `#` markers and a space, and titles a part of the sheet. It is not evaluated and gives no result.
_Avoid_: title, section, header

**Comment**:
Text in a sheet that starts with `//`, either as a whole line or after an expression, and that is not evaluated. A heading is not a comment.
_Avoid_: note, annotation

**Label**:
Words at the start of an expression, before its first number or known name, that are ignored when the rest of the line is a valid expression, as in `compras 2 + 3`.
_Avoid_: caption, tag, prefix

**Text line**:
A line of a sheet with no number, operator, `=`, or known name. It is not evaluated, and it shows no result and no message.
_Avoid_: plain text, note

**Quantity**:
A number written with its unit in an expression, as in `10 ft` or `100 F`. A quantity converts to another unit through `in`, as in `10 ft in m`, and shows the result beside the expression in the destination unit.
_Avoid_: measurement, amount

**Unit**:
The standard of measure that gives a quantity its meaning, such as the metre or the pixel. Each unit accepts exactly its standard abbreviation and its full name singular and plural, as in `ft`, `foot`, and `feet`; no other alias.
_Avoid_: measure, metric

**Monetary value**:
A number written with a currency in an expression, as in `$10`, `5 EUR`, or `1 BTC`. A monetary value converts to another currency through `in`, as in `10 USD in BRL`.
_Avoid_: price

**Currency**:
A unit of value that an expression names by its code or its symbol, as in `USD`, `BRL`, `BTC`, or `$`. A currency is either fiat or crypto.
_Avoid_: money

**Fiat**:
A currency that a government issues, such as the US dollar or the Brazilian real, named by its code or its symbol, as in `USD`, `BRL`, or `$`.

**Crypto**:
A currency that exists as a digital asset, such as Bitcoin or Ethereum, named by its code or its symbol, as in `BTC`, `ETH`, or `₿`.
_Avoid_: coin, token

**Exchange rate**:
The value of one currency in another, as in the reais that one dollar buys. It converts a monetary value into another currency.
_Avoid_: quote, price, cotação

**Duration**:
A quantity of time, as in `15 min`, whose value counts in seconds and stays independent of any reference date, so a date-free month counts 30 days. A duration converts to another unit through `in`, as in `1500 mins in days`, shown in the destination unit on the sheet's display precision.
_Avoid_: elapsed time, time span

**Timespan**:
The composed form of a duration that `to timespan` shows, as in `145 mins to timespan` showing `2 hours 25 min`, with one sign over the whole duration and preserved fractions. It remains convertible to a numeric unit quantity through `in`.
_Avoid_: duration, period

**Time-of-day**:
A clock reading with no date, such as `11am`, `5pm`, or `2:30 pm`, that converts to the clock of another time zone through `in`, as in `11am PST in London`, and shows only as `HH:mm`. A reading that names no time zone is read in the place the conversion names, and the macOS system time zone is the destination.
_Avoid_: time, hour

**Time zone**:
The regional clock rules named by an abbreviation or a city, as in `PST` or `London`. An abbreviation follows the daylight-saving rules of the region that keeps it, so `PST` covers Pacific daylight saving time; a city resolves through the external city data source and the local cache, and an unknown, ambiguous, or uncached city is an error.
_Avoid_: offset, UTC offset

**Place**:
A name an expression writes for a time zone: an abbreviation such as `PST`, or a city such as `London` or `sf`. A time-of-day conversion reads the time in one place and shows it in another, and a conversion that names a single place reads it there and shows the macOS system time zone.
_Avoid_: location, region, zone name

**City**:
A place resolved to a time zone by its name or by a known alias, as `London` for `ldn` and `San Francisco` for `sf`. A name that several cities share is ambiguous, and neither converts.
_Avoid_: town, municipality, geocoding result

**Pixel base**:
The shared value in pixels that a sheet's Settings give the `rem` and the `em`, initially 16 pixels. An expression-local override written with `at`, as in `16px in em at 20px`, replaces the base for that expression only.
_Avoid_: rem size, font size

**Pixel density**:
The shared value in pixels per inch that a sheet's Settings give the translation of points and physical lengths into pixels, initially 96 ppi. An expression-local override written with `at`, as in `2 inches in px at 72 ppi`, replaces the density for that expression only.
_Avoid_: resolution, DPI

**Calendar date**:
A written day with its month and an optional year, as in `31 Mar` or `31 Mar 2027`, that resolves in the sheet's clock and time zone. Without a year the current year holds it, and a day the year lacks goes to the next year that carries the day, as in `29 Feb`.
_Avoid_: date value, day entry

**Calendar-day difference**:
The whole days from the calendar's today to a date, independent of the hours and of daylight-saving shifts, as `days until 31 Mar` shows in `152 days`. Today counts as zero, and a passed date takes its next yearly occurrence.
_Avoid_: countdown, date diff

**Calendar-month shift**:
A date plus whole calendar months with the month ends resolved, so `31 Jan + 1 month` reaches `28 February` in a common year and `29 February` in a leap year.
_Avoid_: month addition over month end

**Unix timestamp**:
The whole seconds after the Unix epoch that `fromunix` converts into the exact instant it represents, shown in the sheet's time zone.
_Avoid_: epoch time, unix time

**Date-dependent result**:
A visible result whose value follows the sheet's date and changes as that date changes, such as a calendar-day difference. An edit alone does not bring it current, so it keeps reevaluation triggers.
_Avoid_: time-sensitive result

**Reevaluation trigger**:
An application event that asks a sheet's results to recalculate: an edit, local midnight in the system time zone, the sheet opening, returning to the app, and the next daylight-saving transition of a time zone a result uses.
_Avoid_: refresh request, invalidation

**Folder**:
A named group of sheets. A sheet belongs to at most one folder, and a sheet can also belong to no folder.
_Avoid_: group, collection

**Recently Deleted**:
The place that holds deleted sheets until they are recovered or removed permanently.
_Avoid_: trash, bin, deleted items

**Appearance**:
The light or dark look of the app: Light, Dark, or Auto. Auto follows the appearance of macOS.
_Avoid_: mode, appearance mode

**Theme**:
A named set of colors for the whole window. Each theme is light or dark, and only the themes that match the current appearance are available.
_Avoid_: color scheme, palette, skin

**Typography**:
The font family, the size in pixels, and the line-height multiplier that the Appearance settings give every sheet.
_Avoid_: font settings, typeface, font style

**Telemetry**:
The data sent about the app's own operation: crash reports, errors, and usage data. The Telemetry option controls all of this data together.
_Avoid_: analytics, tracking, error tracker

**Anonymization**:
The replacement of each real name and each real number in sheet text by a false value of the same type and format, so the expression can still be calculated. No link is kept between a false value and the real value.
_Avoid_: masking, redaction, pseudonymization
