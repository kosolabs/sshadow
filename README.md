# SSHadow

## Tailing Logs

Tail logs using the following command:

```bash
log stream --predicate 'subsystem beginswith "com.kosolabs.SSHadow"' --style ndjson --level debug | jq -R -r --unbuffered -f logfilter.jq
```
