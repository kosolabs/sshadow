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
  (.subsystem | split(".") | .[-1]) as $subsystem |
  (bold + .category + reset) as $category |
  ($lvl_color + .eventMessage + reset) as $message |
  
  # Assemble
  "\($time) \($level) [\($subsystem):\($category)] \($message)"
) catch empty
