#!/data/data/com.termux/files/usr/bin/bash

# ==============================================================================
# CONFIGURATION & INITIALIZATION
# ==============================================================================

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/diary/config"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

DIR="${DIARY_DIR:-$HOME/storage/shared/ MyDocuments/Diary}"
mkdir -p "$DIR"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

sync_git() {
    cd "$DIR" || return 1

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "Warning: '$DIR' is not a Git repository. Skipping sync."
        return 0
    fi

    # Pull down remote changes first to prevent divergence
    git pull --rebase --autostash >/dev/null 2>&1

    git add -A
    if ! git diff --cached --quiet; then
        git commit -m "Diary $(date '+%Y-%m-%d %H:%M')" >/dev/null
        git push >/dev/null 2>&1
    fi 
}

edit_and_sync() {
    local file="$1"
    local is_new="${2:-false}"
    
    local initial_fingerprint=""
    if [ "$is_new" = true ]; then
        initial_fingerprint=$(md5sum "$file" | cut -d' ' -f1)
        # Position cursor directly at the end of the Title prompt
        nvim "+/^Title: /" "+normal! $" "$file"
    else
        nvim "$file"
    fi
    
    if [ "$is_new" = true ]; then
        local final_fingerprint
        final_fingerprint=$(md5sum "$file" | cut -d' ' -f1)
        
        # Discard unchanged templates
        if [ "$initial_fingerprint" = "$final_fingerprint" ]; then
            rm -f "$file"
            return 0
        fi
        
        local title_line
        title_line=$(awk -F 'Title:[ \t]*' 'NF>1 {print $2; exit}' "$file")
        
        if [ -n "$title_line" ]; then
            local safe_title
            safe_title=$(echo "$title_line" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-+|-+$//g')
            
            if [ -n "$safe_title" ]; then
                local new_file="$DIR/${safe_title}-$(date +%Y-%m-%d).md"
                
                if [ -f "$new_file" ]; then
                    new_file="$DIR/${safe_title}-$(date +%Y-%m-%d_%H-%M-%S).md"
                fi
                
                if [ "$file" != "$new_file" ]; then
                    mv "$file" "$new_file"
                fi
            fi
        fi
    fi
    
    sync_git 
}

# ==============================================================================
# CLI COMMANDS (Prefixed with cmd_)
# ==============================================================================

# DOC: Create a new note
cmd_new() {
    local file="$DIR/$(date +%Y-%m-%d_%H-%M-%S).md"

    cat > "$file" <<NOTE
# $(date '+%A %d %B %Y') at $(date '+%H:%M')

Title: 
Tags: 

NOTE

    edit_and_sync "$file" true 
}

# DOC: Quickly append text to today's note
cmd_capture() {
    local tmp_file
    tmp_file=$(mktemp --suffix=.md)

    nvim "$tmp_file"
    
    if [ -s "$tmp_file" ] && grep -q '[^[:space:]]' "$tmp_file"; then
        local today_file
        today_file=$(find "$DIR" -maxdepth 1 -name "*$(date +%F)*.md" | sort | tail -n1)
        
        if [ -z "$today_file" ]; then
            today_file="$DIR/$(date +%Y-%m-%d_%H-%M-%S).md"
            cat > "$today_file" <<NOTE
# $(date '+%A %d %B %Y') at $(date '+%H:%M')

Title: 
Tags: 

NOTE
        fi

        {
            echo ""
            echo "### Captured at $(date '+%H:%M')"
            echo ""
            cat "$tmp_file"
        } >> "$today_file"
        
        rm -f "$tmp_file"
        sync_git
    else
        rm -f "$tmp_file"
    fi 
}

# DOC: Capture an entry via speech-to-text
cmd_voice() {
    echo "Listening... Speak into your device."

    local tmp_file
    tmp_file=$(mktemp --suffix=.md)
    termux-speech-to-text > "$tmp_file"
    
    if [ -s "$tmp_file" ] && grep -q '[^[:space:]]' "$tmp_file"; then
        echo
        echo "Transcribed text:"
        echo "-----------------"
        cat "$tmp_file"
        echo "-----------------"
        echo
        printf "Append this to today's diary? (Y/n): "
        read -r answer
        
        case "$answer" in
            n|N)
                echo "Discarded."
                rm -f "$tmp_file"
                return 0
                ;;
            *)
                local today_file
                today_file=$(find "$DIR" -maxdepth 1 -name "*$(date +%F)*.md" | sort | tail -n1)
                
                if [ -z "$today_file" ]; then
                    today_file="$DIR/$(date +%Y-%m-%d_%H-%M-%S).md"
                    cat > "$today_file" <<NOTE
# $(date '+%A %d %B %Y') at $(date '+%H:%M')

Title: 
Tags: 

NOTE
                fi

                {
                    echo ""
                    echo "### Voice note at $(date '+%H:%M')"
                    echo ""
                    cat "$tmp_file"
                } >> "$today_file"
                
                rm -f "$tmp_file"
                echo "Appended to today's note."
                sync_git
                ;;
        esac
    else
        echo "No speech detected or transcription failed."
        rm -f "$tmp_file"
    fi 
}

# DOC: Open today's latest note
cmd_today() {
    local file
    file=$(find "$DIR" -maxdepth 1 -name "*$(date +%F)*.md" | sort | tail -n1)

    if [ -z "$file" ]; then
        echo "No note exists for today."
        exit 1
    fi
    
    edit_and_sync "$file" false 
}

# DOC: Open a random note
cmd_random() {
    local file
    file=$(find "$DIR" -maxdepth 1 -name "*.md" | shuf -n1)

    if [ -z "$file" ]; then
        echo "No notes found."
        exit 1
    fi
    
    edit_and_sync "$file" false 
}

# DOC: Search notes interactively with context preview
cmd_search() {
    shift
    local query="$*"

    local selection
    selection=$(grep -RniI --exclude-dir=".git" "$query" "$DIR" 2>/dev/null | fzf \
        --delimiter : \
        --with-nth 1,2,3.. \
        --preview 'file={1}; line={2}; head -n $((line + 10)) "$file" | tail -n 21' \
        --preview-window 'right:60%:wrap')

    if [ -n "$selection" ]; then
        local target_file target_line
        target_file=$(echo "$selection" | cut -d: -f1)
        target_line=$(echo "$selection" | cut -d: -f2)
        
        nvim "+$target_line" "$target_file"
        sync_git
    fi
}

# DOC: Edit this script
cmd_edit() {
    nvim "$0"
}

# DOC: Show diary statistics
cmd_stats() {
    local notes words first last commits
    notes=$(find "$DIR" -maxdepth 1 -name "*.md" | wc -l)
    words=$(find "$DIR" -maxdepth 1 -name "*.md" -exec cat {} + 2>/dev/null | wc -w)
    first=$(find "$DIR" -maxdepth 1 -name "*.md" 2>/dev/null | sort | head -n1 | xargs -r basename)
    last=$(find "$DIR" -maxdepth 1 -name "*.md" 2>/dev/null | sort | tail -n1 | xargs -r basename)
    commits=$(git -C "$DIR" rev-list --count HEAD 2>/dev/null || echo "0")

    echo "Notes    : $notes"
    echo "Words    : $words"
    echo "First    : $first"
    echo "Latest   : $last"
    echo "Commits  : $commits" 
}

# DOC: Force sync with Git remote
cmd_update() {
    cd "$DIR" || exit 1

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "Error: '$DIR' is not a Git repository."
        exit 1
    fi
    
    git pull --rebase --autostash >/dev/null 2>&1
    git add -A
    if git diff --cached --quiet; then
        echo "Already up to date."
        exit 0
    fi
    
    git commit -m "Manual update $(date '+%Y-%m-%d %H:%M')"
    git push 
}

# DOC: Display this help menu
cmd_help() {
    echo "Diary commands:"
    echo
    awk '/^# DOC:/ { doc=$0; sub(/^# DOC:[ \t]*/, "", doc) } /^cmd_[a-zA-Z0-9_]+[ \t]*\(\)/ { name=$1; sub(/^cmd_/, "", name); sub(/\(\).*/, "", name); printf "  %-20s %s\n", name, doc; doc="" }' "$0"
}

# ==============================================================================
# DYNAMIC DISPATCHER
# ==============================================================================

COMMAND="${1:-new}"

if [ "$COMMAND" = "-h" ] || [ "$COMMAND" = "--help" ]; then
    COMMAND="help"
fi

if command -v "cmd_$COMMAND" >/dev/null 2>&1; then
    "cmd_$COMMAND" "$@"
else
    echo "Unknown command: $COMMAND"
    echo
    cmd_help
    exit 1
fi