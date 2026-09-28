# Naked strings

Naked strings (nakeds for short), are literal strings without quotes are an important features.
In rak they are supported in both modes, standard and shell.
We need to handle conflicts with other features of the language.
Raku has many kinds of quoted strings. Here we go on the opposite
direction.

We stated somether that nakeds must start with an alphanumeric.

## backslashing out of ambiguities

1
### redirections

Nakeds can't start with redirection first chars, `<` and `>`.
We must escape them. Syntax highlighting will help to see 
what is what.

### file path

To support nakeds as absolute path, match espressions 
must start with `m`. To support nakeds relative path starting 
with `m` we allow backslashing in naked strings including of 
spaces.

  - `m\/`  # `m/` path
  - m\:s # `m:s` path

