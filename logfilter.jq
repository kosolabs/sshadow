# Definitions
def reset:      "\u001b[0m";
def bold:       "\u001b[1m";

# Standard Colors
def red:        "\u001b[31m";
def green:      "\u001b[32m";
def yellow:     "\u001b[33m";
def gray:       "\u001b[90m";

# High-Intensity / Bright
def bright_white:  "\u001b[97m";

# Thread ID color palette — generated from the 256-color 6×6×6 cube (indices 16–231).
# Each color is decomposed into r/g/b components (0–5); colors whose component
# sum falls outside [4, 11] are excluded to avoid near-black and near-white hues.
def thread_colors:
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
    elif .messageType == "Default" then green
    elif .messageType == "Debug" then gray
    else reset end
  ) as $lvl_color |
  
  # Format the specific parts
  (gray + .timestamp[11:26] + reset) as $time |
  ($lvl_color + .messageType + reset) as $level |
  (.threadID as $tid | (thread_colors | .[$tid % length]) + ($tid | tostring) + reset) as $threadID |
  (.subsystem | split(".") | .[-1]) as $subsystem |
  (bold + .category + reset) as $category |
  ($lvl_color + .eventMessage + reset) as $message |
  
  # Assemble
  "\($time) \($threadID) \($level)\t\($subsystem):\($category) \($message)"
) catch ("ERROR: " + .)
