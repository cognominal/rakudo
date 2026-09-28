# modes

rak supports two modes, standard and shell. We mostly describe the shell mode 
here because the standard mode is mostly raku with some changes.

## shell mode

Mode is autorecognized at the level of a statement or a parenthesized instruction.
Shell mode supports the classic shell features, starting by implicitely launching commands.
Builtins are raku/rak functions or are their something else. functions defined by rak itself ?
Naked strings, globbing and redirections are supported in both modes.


Shell mode occupy the place that was an error "two terms in a row."


### type builtin

we will support the type buildin. Below is an example of its use
in bash 

```
rak rak ❯ type ls
ls is aliased to `eza -lh --group-directories-first --icons=auto'

rak rak ❯ type eza
eza is /usr/bin/eza

rak rak ❯ type gp
gp is aliased to `glow -p'

rak rak ❯ type fgit
fgit is a function
fgit ()
{
    git -C "${1:-.}" log --reverse --format=%ai "${2:-HEAD}" | head -1
}

rak rak ❯ type type
type is a shell builtin
```
```
