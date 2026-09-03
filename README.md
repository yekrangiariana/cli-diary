# termux-diary

A lightweight, distraction-free markdown journaling CLI built for Termux on Android.

## Features

- **Zero bloat**: Pure Bash, Neovim, and plain Markdown.
- **Auto-slug titles**: Title extraction and filename renaming on save.
- **Empty file cleanup**: Discards unmodified templates automatically.
- **Voice-to-text**: Integrated voice capture using `termux-api`.
- **Interactive search**: Search entries with an instant side-by-side preview via `fzf`.
- **Git sync**: Auto-rebase, commit, and push on save.

## Dependencies

The installer will configure these automatically, but for manual setups:
- `git`
- `neovim`
- `fzf`
- `termux-api` (package + Android app)
- `coreutils`, `findutils`, `gawk`, `sed`

## Quick Install (Termux)

```bash
pkg install -y curl
curl -fsSL [https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/install.sh](https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/install.sh) | bash
```

## Usage

```bash
diary              # Create a new note (default)
diary capture      # Fast scratchpad appended to today's note
diary voice        # Transcribe speech directly into today's note
diary search <txt> # Search entries interactively with preview
diary today        # Open today's latest note
diary random       # Open a random journal entry
diary stats        # Display word count, note count, and commits
diary update       # Force a manual pull, commit, and push
diary help         # Display all available commands
```

## Configuration

Settings are stored in `~/.config/diary/config`. 

To change your diary storage location, edit that file:

```bash
DIARY_DIR="/path/to/your/notes"
```