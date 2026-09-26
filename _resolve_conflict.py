#!/usr/bin/env python3
import sys

with open('src/Raku/Grammar.nqp', 'r') as f:
    content = f.read()

old_start = "<<<<<<< HEAD\n    # CLAUDE.md \u00a74.2/\u00a75 Phase 1: `#` is also the int sigil now, so a bare"
# Find it without unicode chars
old_start = "<<<<<<< HEAD\n    # CLAUDE.md "
end_marker = ">>>>>>> onepass-compile\n"

si = content.find(old_start)
if si < 0:
    print("Could not find start marker", file=sys.stderr)
    sys.exit(1)
    
ei = content.find(end_marker, si)
if ei < 0:
    print("Could not find end marker", file=sys.stderr)
    sys.exit(1)

ei += len(end_marker)

print(f"Conflict region: {si}-{ei}")
print(f"Length: {ei-si}")

# Replacement without backslash-N sequences - use different approach
replacement_lines = [
    "    # CLAUDE.md \u00a74.2/\u00a75 Phase 1: `#` is also the int sigil now, so a bare",
    "    # `#` immediately followed by an identifier-start character (no space)",
    "    # is a `#`-sigiled variable, not a comment \u2014 `#foo` vs `# foo`. A twigil",
    "    # is also possible between the sigil and the name (`#.foo`, `#!foo`,",
    "    # etc. \u2014 see `token twigil`), so `#` followed by a twigil char *and then*",
    "    # an identifier-start char is excluded too (`#!/usr/bin/env raku` still",
    "    # reads as a comment: `/` right after `!` isn't a valid twigil-name",
    "    # start, matching `token twigil`'s own `<?before <alpha>>` requirement).",
    "    # Anything else after `#` (whitespace, EOL, or a character that can't",
    "    # start a `desigilname` either way, e.g. `#123`, `#----`) still reads as",
    "    # an ordinary comment.",
    "",
    "    token comment:sym<#COMPILER> {",
    "        '#COMPILER::'",
    "        [",
    "            || 'if' \\s+ $<condition>=[moar|'!moar'] \\N*",
    "                 [",
    "                     || <?{ $<condition> eq '!moar' }> \\n <skip-to-compiler-endif>",
    "                     || { $<condition> eq 'moar' }  # true condition, just consume the if line",
    "                 ]",
    "            || 'endif' \\N*",
    "            || 'line' \\s+ $<number>=[\\d+] [\\s+ $<filename>=[\\N+]]? \\N*",
    "        ]",
    "    }",
    "    ",
    "    # Skip lines until #COMPILER::endif (used when a compile-time condition is false)",
    "    token skip-to-compiler-endif {",
    "        :dba('skip to #COMPILER::endif')",
    "        [",
    "            || \\N* \\n",
    "        ]*",
    "        '#COMPILER::endif' \\N* [\\n | $]",
    "    }",
]

# Build the replacement with proper escaping
import codecs
replacement = "\n".join(replacement_lines)
# But the original has actual backslash sequences, not escape sequences
# Let me just write the file content that matches the original style

# OK, let me just read the actual conflict text and construct the replacement
# by reading the conflict region, extracting the onepass-compile additions

conflict_text = content[si:ei]
print("Conflict text:")
print(repr(conflict_text[:200]))

# Split by =======
parts = conflict_text.split("=======\n")
print(f"Number of parts: {len(parts)}")
if len(parts) == 2:
    # parts[0] is HEAD side, parts[1] is onepass-compile side (with >>>>>)
    head_side = parts[0].replace("<<<<<<< HEAD\n", "", 1)
    # Remove the leading newline from the HEAD comment
    onepass_side = parts[1]
    # Remove >>>>>>> onepass-compile from the end
    if onepass_side.endswith(">>>>>>> onepass-compile\n"):
        onepass_side = onepass_side[:-(len(">>>>>>> onepass-compile\n"))]
    elif onepass_side.endswith(">>>>>>> onepass-compile"):
        onepass_side = onepass_side[:-(len(">>>>>>> onepass-compile"))]
    
    print("HEAD side:")
    print(head_side[:100])
    print("onepass side:")
    print(onepass_side[:100])
    
    # Combine: keep head_side (the comment + token definition), insert onepass_side before the token
    # Actually, onepass_side has the #COMPILER token+skip-to-compiler-endif
    # and head_side has the comment + comment:sym<#>
    # We want: CLAUDE.md comment, then #COMPILER token+skip, then comment:sym<#>
    
    # Find where the token definition starts in head_side
    token_start = head_side.find("    token comment:sym<#>")
    if token_start >= 0:
        comment_part = head_side[:token_start].rstrip() + "\n\n"
        token_part = head_side[token_start:]
        result = comment_part + onepass_side + "\n\n" + token_part
        
        new_content = content[:si] + result + content[ei:]
        with open('src/Raku/Grammar.nqp', 'w') as f:
            f.write(new_content)
        print("Successfully resolved conflict")
    else:
        print("Could not find token:sym<#>, writing manually")
        # Just put it all together
        result = head_side + "\n" + onepass_side
        new_content = content[:si] + result + content[ei:]
        with open('src/Raku/Grammar.nqp', 'w') as f:
            f.write(new_content)
        print("Written manually")