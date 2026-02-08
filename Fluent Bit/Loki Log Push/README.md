# Fluent Bit → Loki Log Collection

This prototype demonstrates collecting logs from local files and pushing them to Grafana Loki using Fluent Bit.

## Configuration Overview

- **Input**: Tail plugin monitoring `/logs/*.txt` files
- **Output**: Loki (Grafana's log aggregation system)
- **Storage**: Persistent state tracking for incremental log collection

## Important: File Writing Behavior

### ✅ Correct Behavior (Append Operations)
When you **append** data to log files using commands like:
```bash
echo "new log line" >> ./logs/new.txt
```
- Fluent Bit **only sends the new data** added since the last read
- This is the expected behavior for production log collection
- The database tracks file offset and inode, so only new content is transmitted

### ⚠️ Important: VS Code Editor Behavior
When you **edit and save files in VS Code** (or most text editors):
```bash
# VS Code rewrite (NOT append)
# This causes the file to be rewritten completely
```
- VS Code and most editors **rewrite the entire file** when you save
- Fluent Bit sees this as a "new file" (inode change or full rewrite)
- **All content gets re-sent to Loki**, including duplicates of old logs
- This is **NOT a bug** — it's how Fluent Bit correctly detects file changes

### Testing Guidelines

**For testing tail behavior correctly:**
1. Use command-line tools to append logs:
   ```bash
   echo "test line 1" >> ./logs/new.txt
   echo "test line 2" >> ./logs/new.txt
   ```

2. Watch the Fluent Bit logs for each append:
   ```bash
   sudo docker logs -f fluent-bit
   ```

3. You should see **only one new entry** per append operation

**DO NOT test using VS Code editor** because:
- Editing in VS Code rewrites the entire file
- Fluent Bit will re-send all historical logs
- This creates false duplicates that are not indicative of a bug

## Configuration Details

### inputs.conf
- `DB /fluent-bit/state/tail_state.db` - Persistent database tracking file position
- `read_from_head False` - Don't read entire file on startup (only new data)
- `Refresh_Interval 5` - Check files every 5 seconds (prevents too-frequent reads)
- `DB.locking true` - Ensure safe concurrent access to database

### fluent-bit.conf (SERVICE section)
- `storage.path /fluent-bit/state` - Persistent storage backend
- `storage.sync normal` - Balance between safety and performance
- Enables `memory+filesystem` storage strategy for reliability

### Docker Setup
```yaml
volumes:
  - ./fluent-bit-state:/fluent-bit/state  # Persistent state tracking
  - ./logs:/logs:ro                        # Log files (read-only)
```

## How It Works

1. **First Read**: Fluent Bit reads the entire file and records its position (inode + offset)
2. **Subsequent Reads**: Only content after the stored offset is sent
3. **File Rotation**: If file size changes or inode changes, position is reset
4. **On Restart**: Database persists, so Fluent Bit resumes from last position

## Testing Results

✅ When appending logs via CLI → Only new lines sent
❌ When editing in VS Code → All content re-sent (expected behavior)

Use CLI append operations for accurate testing of the log collection pipeline.
