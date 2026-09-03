#!/usr/bin/env bash

# ==============================================================================
# CONFIGURATION & INITIALIZATION
# ==============================================================================

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/diary/config"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Detect default diary directory based on OS / environment
if [ -z "$DIARY_DIR" ]; then
    if [ -d "/data/data/com.termux" ] || [ -n "$TERMUX_VERSION" ]; then
        DIR="$HOME/storage/shared/Documents/Diary"
    else
        DIR="$HOME/Documents/Diary"
    fi
else
    DIR="$DIARY_DIR"
fi

mkdir -p "$DIR" 2>/dev/null || true

# Preferred editor
EDITOR_BIN="${DIARY_EDITOR:-${EDITOR:-nano}}"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

get_file_hash() {
    local file="$1"
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$file" | cut -d' ' -f1
    elif command -v md5 >/dev/null 2>&1; then
        md5 -q "$file"
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        cksum "$file" | cut -d' ' -f1
    fi
}

create_temp_md() {
    local tmp_dir="${TMPDIR:-${PREFIX:-}/tmp}"
    [ -d "$tmp_dir" ] || tmp_dir="/tmp"
    
    # Try standard GNU --suffix first; fall back to template
    mktemp --suffix=.md "$tmp_dir/diary_tmp.XXXXXX" 2>/dev/null || \
    mktemp "$tmp_dir/diary_tmp.XXXXXX"
}

browse_notes_fzf() {
    local query="$1"

    if ! command -v fzf >/dev/null 2>&1; then
        echo "Error: fzf is required for interactive search."
        return 1
    fi

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
        
        if [ -n "$target_line" ] && { [[ "$EDITOR_BIN" == *"nvim"* ]] || [[ "$EDITOR_BIN" == *"vim"* ]]; }; then
            "$EDITOR_BIN" "+$target_line" "$target_file"
        else
            "$EDITOR_BIN" "$target_file"
        fi
        sync_git
    fi
}

get_all_tags() {
    {
        # Match hashtags like #ideas, #reading
        grep -rohI --exclude-dir=".git" -E '#[a-zA-Z0-9_-]+' "$DIR" 2>/dev/null
        
        # Match YAML frontmatter tags like tags: [ideas, reading]
        grep -rhI --exclude-dir=".git" -E '^[ \t]*tags:[ \t]*' "$DIR" 2>/dev/null | \
            sed -E 's/^[ \t]*tags:[ \t]*//' | tr -d '[]' | tr ',' '\n' | \
            sed -E 's/^[ \t]*//;s/[ \t]*$//' | grep -v '^$' | sed 's/^/#/'
    } | sort | uniq -c | sort -nr
}

open_editor() {
    local file="$1"
    local is_new="${2:-false}"

    if [ "$is_new" = true ] && { [[ "$EDITOR_BIN" == *"nvim"* ]] || [[ "$EDITOR_BIN" == *"vim"* ]]; }; then
        "$EDITOR_BIN" "+/^title: /" "+normal! $i" "$file"
    else
        "$EDITOR_BIN" "$file"
    fi
}

sync_git() {
    cd "$DIR" || return 1

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    fi

    # On Termux / Android shared storage, prevent git fileMode permissions tracking bugs
    if [ -d "/data/data/com.termux" ] || [ -n "$TERMUX_VERSION" ]; then
        git config core.fileMode false >/dev/null 2>&1 || true
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
        initial_fingerprint=$(get_file_hash "$file")
        open_editor "$file" true
    else
        open_editor "$file" false
    fi
    
    if [ "$is_new" = true ]; then
        local final_fingerprint
        final_fingerprint=$(get_file_hash "$file")
        
        # Discard unchanged templates
        if [ "$initial_fingerprint" = "$final_fingerprint" ]; then
            rm -f "$file"
            return 0
        fi
        
        local title_line
        title_line=$(awk -F '^[ \t]*[tT][iI][tT][lL][eE]:[ \t]*' 'NF>1 {print $2; exit}' "$file")
        
        if [ -n "$title_line" ]; then
            local safe_title
            safe_title=$(echo "$title_line" | tr -d '\r"' | sed -E "s/^['\"]+|['\"]+$//g" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-zA-Z0-9]+/-/g' | sed -E 's/^-+|-+$//g')
            
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
---
title: ""
date: $(date '+%Y-%m-%d %H:%M:%S')
tags: []
---

# $(date '+%A %d %B %Y') at $(date '+%H:%M')

NOTE

    edit_and_sync "$file" true 
}

# DOC: Quickly append text to today's note
cmd_capture() {
    local tmp_file
    tmp_file=$(create_temp_md)

    open_editor "$tmp_file" false
    
    if [ -s "$tmp_file" ] && grep -q '[^[:space:]]' "$tmp_file"; then
        local today_file
        today_file=$(find "$DIR" -maxdepth 1 -name "*$(date +%F)*.md" 2>/dev/null | sort | tail -n1)
        
        if [ -z "$today_file" ]; then
            today_file="$DIR/$(date +%Y-%m-%d_%H-%M-%S).md"
            cat > "$today_file" <<NOTE
---
title: ""
date: $(date '+%Y-%m-%d %H:%M:%S')
tags: []
---

# $(date '+%A %d %B %Y') at $(date '+%H:%M')

NOTE
        fi

        # Ensure today_file ends with a newline before appending header
        if [ -s "$today_file" ] && [ "$(tail -c 1 "$today_file")" != $'\n' ]; then
            echo "" >> "$today_file"
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

# DOC: Capture an entry via speech-to-text (Termux)
cmd_voice() {
    if ! command -v termux-speech-to-text >/dev/null 2>&1; then
        echo "Error: Voice capture requires termux-speech-to-text (Termux API on Android)."
        return 1
    fi

    echo "Listening... Speak into your device."

    local tmp_file
    tmp_file=$(create_temp_md)
    
    if termux-speech-to-text > "$tmp_file" 2>/dev/null && [ -s "$tmp_file" ] && grep -q '[^[:space:]]' "$tmp_file"; then
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
                today_file=$(find "$DIR" -maxdepth 1 -name "*$(date +%F)*.md" 2>/dev/null | sort | tail -n1)
                
                if [ -z "$today_file" ]; then
                    today_file="$DIR/$(date +%Y-%m-%d_%H-%M-%S).md"
                    cat > "$today_file" <<NOTE
---
title: ""
date: $(date '+%Y-%m-%d %H:%M:%S')
tags: []
---

# $(date '+%A %d %B %Y') at $(date '+%H:%M')

NOTE
                fi

                # Ensure today_file ends with a newline before appending header
                if [ -s "$today_file" ] && [ "$(tail -c 1 "$today_file")" != $'\n' ]; then
                    echo "" >> "$today_file"
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

# DOC: Open the latest note
cmd_latest() {
    local file
    file=$(find "$DIR" -maxdepth 1 -name "*$(date +%F)*.md" 2>/dev/null | sort | tail -n1)

    if [ -z "$file" ]; then
        file=$(find "$DIR" -maxdepth 1 -name "*.md" 2>/dev/null | sort | tail -n1)
    fi

    if [ -z "$file" ]; then
        echo "No notes found."
        exit 1
    fi
    
    edit_and_sync "$file" false 
}

# DOC: Open a random note
cmd_random() {
    local file
    if command -v shuf >/dev/null 2>&1; then
        file=$(find "$DIR" -maxdepth 1 -name "*.md" 2>/dev/null | shuf -n1)
    elif command -v gshuf >/dev/null 2>&1; then
        file=$(find "$DIR" -maxdepth 1 -name "*.md" 2>/dev/null | gshuf -n1)
    else
        file=$(find "$DIR" -maxdepth 1 -name "*.md" 2>/dev/null | awk 'BEGIN{srand()} {print rand() "\t" $0}' | sort -n | cut -f2- | head -n1)
    fi

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
    browse_notes_fzf "$query"
}

# DOC: Display ranked list of all tags and counts
cmd_tags() {
    local tag_list
    tag_list=$(get_all_tags)
    if [ -z "$tag_list" ]; then
        echo "No tags found."
        return 0
    fi
    echo "$tag_list"
}

# DOC: Browse notes filtered by tag
cmd_tag() {
    shift
    local tag="$1"
    
    if [ -z "$tag" ]; then
        local tag_list
        tag_list=$(get_all_tags)
        if [ -z "$tag_list" ]; then
            echo "No tags found."
            return 0
        fi
        
        local selected_line
        selected_line=$(echo "$tag_list" | fzf --prompt="Select tag > ")
        tag=$(echo "$selected_line" | awk '{print $2}')
    fi

    if [ -n "$tag" ]; then
        browse_notes_fzf "$tag"
    fi
}

# DOC: Open the CLI Diary script source code in editor
cmd_source() {
    "$EDITOR_BIN" "$0"
}

# DOC: Show diary statistics
cmd_stats() {
    local notes words first_file last_file first_date last_date commits week_notes read_time top_tags_str
    
    notes=$(find "$DIR" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    notes=${notes:-0}
    
    words=$(find "$DIR" -maxdepth 1 -name "*.md" -exec cat {} + 2>/dev/null | wc -w | tr -d ' ')
    words=${words:-0}
    
    read_time=$(( (words + 249) / 250 ))
    
    if [ "$notes" -gt 0 ]; then
        week_notes=$(find "$DIR" -maxdepth 1 -name "*.md" -mtime -7 2>/dev/null | wc -l | tr -d ' ')
    else
        week_notes=0
    fi
    
    first_file=$(find "$DIR" -maxdepth 1 -name "*.md" 2>/dev/null | sort | head -n1)
    last_file=$(find "$DIR" -maxdepth 1 -name "*.md" 2>/dev/null | sort | tail -n1)
    
    first_date="${first_file:+$(basename "$first_file" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n1)}"
    last_date="${last_file:+$(basename "$last_file" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n1)}"
    
    first_date="${first_date:-None}"
    last_date="${last_date:-None}"
    
    commits=$(git -C "$DIR" rev-list --count HEAD 2>/dev/null || echo "0")
    
    top_tags_str=$(get_all_tags | head -n 3 | awk '{printf "%s (%s)  ", $2, $1}')
    top_tags_str="${top_tags_str:-None}"

    local BOLD="\033[1m"
    local CYAN="\033[36m"
    local GREEN="\033[32m"
    local RESET="\033[0m"

    echo -e "${CYAN}${BOLD}── CLI DIARY METRICS ──────────────────────────${RESET}"
    echo -e "  ${BOLD}Notes${RESET}        : ${GREEN}${notes}${RESET} entries (${week_notes} this week)"
    echo -e "  ${BOLD}Words${RESET}        : ${words} words (~${read_time} mins read)"
    echo -e "  ${BOLD}Top Tags${RESET}     : ${top_tags_str}"
    echo -e "  ${BOLD}First Entry${RESET}  : ${first_date}"
    echo -e "  ${BOLD}Latest Entry${RESET} : ${last_date}"
    echo -e "  ${BOLD}Git Commits${RESET}  : ${commits} commits"
    echo -e "  ${BOLD}Storage Path${RESET} : ${DIR}"
    echo -e "${CYAN}${BOLD}───────────────────────────────────────────────${RESET}"
}

# DOC: Change terminal location to diary directory
cmd_dir() {
    cd "$DIR" || exit 1
    if [ -t 1 ]; then
        echo "Entering diary directory: $DIR"
        echo "(Type 'exit' when done to return)"
        echo
        ${SHELL:-bash}
    else
        echo "$DIR"
    fi
}

# DOC: Open configuration file in editor
cmd_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    open_editor "$CONFIG_FILE" false
}

# DOC: Self-update CLI Diary script from GitHub
cmd_upgrade() {
    local target_bin
    target_bin=$(command -v diary 2>/dev/null || echo "$0")
    local tmp_update
    tmp_update=$(create_temp_md)

    echo "Checking for updates..."
    
    # Use cache-buster timestamp parameter to bypass GitHub CDN 5-minute caching
    if curl -sSL "https://raw.githubusercontent.com/yekrangiariana/cli-diary/main/diary.sh?v=$(date +%s)" -o "$tmp_update"; then
        if [ ! -s "$tmp_update" ]; then
            rm -f "$tmp_update"
            echo "Error: Downloaded update file is empty."
            return 1
        fi

        if cmp -s "$target_bin" "$tmp_update"; then
            rm -f "$tmp_update"
            echo "Already up to date."
            return 0
        fi

        if mv "$tmp_update" "$target_bin" 2>/dev/null; then
            chmod +x "$target_bin" 2>/dev/null || true
            echo "Updated to latest version."
        else
            rm -f "$tmp_update"
            echo "Error: Cannot write to $target_bin (permission denied)."
            return 1
        fi
    else
        rm -f "$tmp_update"
        echo "Error: Could not connect to GitHub."
        return 1
    fi
}

# DOC: Display this help menu
cmd_help() {
    echo "CLI Diary commands:"
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