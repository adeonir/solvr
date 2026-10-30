# Nume

Nume is a text calculator for the Mac. This glossary defines the words that the product, its documents, and its code use for the same concepts.

## Language

**Sheet**:
A saved, named page of text in Nume that holds expressions, variables, headings, comments, and text lines, in a format close to Markdown. Variables and earlier expressions in a sheet keep their meaning until someone deletes them.
_Avoid_: note, calculation, document, file

**Expression**:
One line of a sheet that Nume evaluates to a result.
_Avoid_: calculation, formula, line

**Variable**:
A name that an expression in a sheet gives a value, as in `price = 8`. Later expressions in the same sheet use the name in place of the value, and a name used before its first definition is an error.
_Avoid_: constant, field, parameter

**Heading**:
A line of a sheet that starts with one to six `#` markers and a space, and titles a part of the sheet. Nume does not evaluate it and gives it no result.
_Avoid_: title, section, header

**Comment**:
Text in a sheet that starts with `//`, either as a whole line or after an expression, and that Nume does not evaluate. A heading is not a comment.
_Avoid_: note, annotation

**Label**:
Words at the start of an expression, before its first number or known name, that Nume ignores when the rest of the line is a valid expression, as in `compras 2 + 3`.
_Avoid_: caption, tag, prefix

**Text line**:
A line of a sheet with no number, operator, `=`, or known name. Nume does not evaluate it, and it shows no result and no message.
_Avoid_: plain text, note

**Quantity**:
A number written with its unit in an expression, as in `10 ft` or `100 F`. Nume converts a quantity to another unit through `in`, as in `10 ft in m`, and shows the result beside the expression in the destination unit.
_Avoid_: measurement, amount

**Unit**:
The standard of measure that gives a quantity its meaning, such as the metre or the pixel. Each unit accepts exactly its standard abbreviation and its full name singular and plural, as in `ft`, `foot`, and `feet`; no other alias.
_Avoid_: measure, metric

**Pixel base**:
The shared value in pixels that a sheet's Settings give the `rem` and the `em`, initially 16 pixels. An expression-local override written with `at`, as in `16px in em at 20px`, replaces the base for that expression only.
_Avoid_: rem size, font size

**Pixel density**:
The shared value in pixels per inch that a sheet's Settings give the translation of points and physical lengths into pixels, initially 96 ppi. An expression-local override written with `at`, as in `2 inches in px at 72 ppi`, replaces the density for that expression only.
_Avoid_: resolution, DPI

**Folder**:
A named group of sheets. A sheet belongs to at most one folder, and a sheet can also belong to no folder.
_Avoid_: group, collection

**Recently Deleted**:
The place that holds deleted sheets until they are recovered or removed permanently.
_Avoid_: trash, bin, deleted items

**Mode**:
The light or dark appearance of Nume: Light, Dark, or Auto. Auto follows the appearance of macOS.
_Avoid_: appearance mode

**Theme**:
A named set of colors for the whole window of Nume. Each theme is light or dark, and only the themes that match the current mode are available.
_Avoid_: color scheme, palette, skin

**Telemetry**:
The data that Nume sends about its own operation: crash reports, errors, and usage data. The Telemetry option controls all of this data together.
_Avoid_: analytics, tracking, error tracker

**Anonymization**:
The replacement of each real name and each real number in sheet text by a false value of the same type and format, so the expression can still be calculated. Nume keeps no link between a false value and the real value.
_Avoid_: masking, redaction, pseudonymization
