# peek-action-diff.tape — VHS tape for the README hero demo.
#
# Renders a ~12s GIF of:
#   peek action ... --verify diff
# pressing "7" in Calculator and surfacing the JSON diff that captures
# the display flipping from 0 → 7.
#
# Uses the local debug binary (.build/debug/peek) aliased to `peek` so the
# recording matches what users will see with the installed CLI.
#
# Requirements:
#   brew install vhs jq
#   swift build  (so .build/debug/peek exists)
#   Calculator.app present (it is, on every Mac)
#   Accessibility permission granted to the shell vhs invokes
#
# Render:
#   vhs docs/demos/peek-action-diff.tape
# Output:
#   docs/demos/peek-action-diff.gif

Output docs/demos/peek-action-diff.gif

Set Shell         "zsh"
Set FontSize      18
Set Width         1400
Set Height        720
Set Padding       30
Set Theme         "TokyoNight"
Set TypingSpeed   55ms
Set PlaybackSpeed 1.0

# macOS terminal chrome: rounded window with traffic-light title bar.
Set BorderRadius  22
Set WindowBar     "Colorful"
Set WindowBarSize 40
Set Margin        20
Set MarginFill    "#1a1b26"

# --- Off-camera setup --------------------------------------------------------
# Alias `peek` to the local debug build, launch Calculator, and clear it so
# the demo always starts from a known "0" display.
Hide
Type "setopt interactivecomments"
Enter
Type "alias peek=$PWD/.build/debug/peek"
Enter
Type "peek launch --name Calculator --wait-for-window > /dev/null && peek key --key escape --app Calculator > /dev/null && clear"
Enter
Sleep 1.8s
Show

# --- The shot ----------------------------------------------------------------
Sleep 400ms

Type "# Press a Calculator button and see exactly what changed — in one call."
Enter
Sleep 1.4s

Type "peek action --app Calculator --role Button --title 7 --do Press --verify diff --format json | jq '.diff | del(.. | .frame?, .identity?)'"
Sleep 400ms
Enter

Sleep 3s

Type "# And while we're here — snap the window."
Enter
Sleep 1.2s

Type "peek capture --app Calculator --output /tmp/calculator.png"
Sleep 400ms
Enter

Sleep 2.5s

# --- Cleanup -----------------------------------------------------------------
# No trailing `Show` — recording ends on the last visible frame (the screenshot
# confirmation), and Calculator is quit silently in the hidden tail.
Hide
Type "peek quit --name Calculator --force > /dev/null"
Enter
