# Definitions
def reset:      "\u001b[0m";
def bold:       "\u001b[1m";

# Standard Colors
def black:      "\u001b[30m";
def red:        "\u001b[31m";
def green:      "\u001b[32m";
def yellow:     "\u001b[33m";
def blue:       "\u001b[34m";
def magenta:    "\u001b[35m";
def gray:       "\u001b[90m";

# Convert a non-negative integer to a "0x"-prefixed lowercase hex string.
def tohex:
  "0x" + (
    if . == 0 then "0"
    else
      [ recurse(if . >= 16 then ./16 | floor else empty end) | . % 16 ]
      | reverse
      | map(if . < 10 then . + 48 else . + 87 end)
      | implode
    end
  );

# High-Intensity / Bright
def bright_white:  "\u001b[97m";

# Color palette — generated from the 256-color 6×6×6 cube (indices 16–231).
# Each color is decomposed into r/g/b components (0–5); colors whose component
# sum falls outside [4, 11] are excluded to avoid near-black and near-white hues.
def colors:
  [
    range(16; 232) |
    . as $i |
    (($i - 16) / 36 | floor) as $r |
    ((($i - 16) % 36) / 6 | floor) as $g |
    (($i - 16) % 6) as $b |
    select(($r + $g + $b) >= 4 and ($r + $g + $b) <= 11) |
    "\u001b[38;5;\($i)m"
  ];

try (
  fromjson | 
  
  # Map log levels to colors
  (
    if .messageType == "Fault" then red
    elif .messageType == "Error" then yellow
    elif .messageType == "Default" then blue
    elif .messageType == "Info" then green
    elif .messageType == "Debug" then gray
    else reset end
  ) as $lvl_color |
  
  # Format the specific parts
  (gray + .timestamp[11:26] + reset) as $time |
  ($lvl_color + .messageType + reset) as $level |
  (.threadID as $t | (colors | .[$t % length]) + ($t | tohex) + reset) as $tid |
  (.processID as $p | (colors | .[$p % length]) + ($p | tostring) + reset) as $pid |
  
  # Map subsystem to clearer names
  (.subsystem | split(".") | .[-1] |
    if . == "SSHadow" then "AppUI"
    elif . == "Extension" then "FPExt"
    else . end
  ) as $subsystem |
  
  (bold + .category + reset) as $category |
  ($lvl_color + .eventMessage + reset) as $message |
  
  # Assemble
  "\($time) \($pid):\($tid) \($level)\t\($subsystem):\($category) \($message)"
) catch ("ERROR: " + .)
