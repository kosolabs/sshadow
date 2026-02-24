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

# Thread ID color palette (cycled by threadID % length)
def thread_colors: [
  "\u001b[32m",   # green
  "\u001b[33m",   # yellow
  "\u001b[34m",   # blue
  "\u001b[35m",   # magenta
  "\u001b[36m",   # cyan
  "\u001b[92m",   # bright green
  "\u001b[93m",   # bright yellow
  "\u001b[94m",   # bright blue
  "\u001b[95m",   # bright magenta
  "\u001b[96m"    # bright cyan
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
  "\($time) \($threadID) \($level) \($subsystem):\($category) \($message)"
) catch ("ERROR: " + .)
