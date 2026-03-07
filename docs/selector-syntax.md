# Selector Syntax

This document contains the full selector syntax reference for `osx query`.

## Quick Examples

```bash
# All buttons under any window
osx query --app TextEdit "AXWindow AXButton"

# Direct child text field
osx query --app TextEdit "AXGroup > AXTextField"

# Attribute contains
osx query --app TextEdit "AXButton[AXTitle*=\"Save\"]"

# Match by computed name alias (CPName)
osx query --app TextEdit "*[CPName*=\"Save\"]"

# Parent that has a direct child text field
osx query --app TextEdit "AXGroup:has(> AXTextField)"

# Exclude matches
osx query --app TextEdit "AXTextArea:not([AXValue*=\"draft\"])"

# Disjunction
osx query --app TextEdit "AXTextArea, AXTextField, AXComboBox"
```

## Grammar (Practical)

```text
selector_list      := selector ("," selector)*
selector           := compound (combinator compound)*
combinator         := ">" | descendant_whitespace
compound           := type? attribute_group? pseudo*
                   | attribute_group pseudo*
                   | pseudo+
type               := "*" | identifier
attribute_group    := "[" attribute ("," attribute)* "]"
attribute          := identifier operator quoted_string
operator           := "=" | "*=" | "^=" | "$="
pseudo             := ":has(" has_arg ")" | ":not(" selector_list ")"
has_arg            := relative_selector_list
relative_selector  := combinator? selector
```

## Supported Operators

- `=` exact string match
- `*=` contains
- `^=` starts with
- `$=` ends with

Important details:

- Attribute values must be quoted.
- Matching is case-sensitive for `=`, `^=`, and `$=`.
- `*=` fuzzy contains matching is case-insensitive.
- `*=""` matches any element with that attribute present.
- `*` is wildcard type selector.
- Whitespace between compounds is treated as descendant combinator.
- Results are de-duplicated across comma-separated selector groups and returned in traversal order.
- Parser constraints: one attribute group per compound, and only `:has(...)` / `:not(...)` pseudo-classes.

## Supported Pseudo-classes

- `:has(...)` supports selector lists and relative selectors like `:has(> AXTextField)`.
- `:not(...)` supports selector lists.

## Attribute Alias Mapping

These aliases are normalized before lookup:

- `role` -> `AXRole`
- `subrole` -> `AXSubrole`
- `title` -> `AXTitle`
- `value` -> `AXValue`
- `identifier` / `id` -> `AXIdentifier`
- `domid` -> `AXDOMIdentifier`
- `domclass` -> `AXDOMClassList`
- `help` -> `AXHelp`
- `description` -> `AXDescription`
- `placeholder` -> `AXPlaceholderValue`
- `enabled` -> `AXEnabled`
- `focused` -> `AXFocused`
- `cpname` -> `ComputedName`
