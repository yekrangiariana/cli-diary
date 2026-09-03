# cli-diary

A lightweight bash script for markdown journaling in your terminal. Works on Android (Termux), macOS, and Linux.

## Features

- **Pure Bash**: Works with your choice of text editor (`nano`, `nvim`, `vim`, `micro`, etc.) and plain `.md` files.
- **Auto-naming**: Sets filenames automatically based on the title line.
- **Interactive Search**: Search notes with a live preview via `fzf`.
- **Auto Git Sync**: Commits and pushes changes automatically when you save.
- **Voice Notes (Android/Termux)**: Transcribe speech straight into your daily note.

## Install

Run the installer:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/yekrangiariana/cli-diary/main/install.sh)"
```

The script asks for your note directory, checks dependencies (`git`, `fzf`), prompts for your preferred editor, and places `diary` in your PATH.

## Uninstall

To remove `cli-diary` and its configuration:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/yekrangiariana/cli-diary/main/uninstall.sh)"
```

## Commands

```bash
diary              # Create a new note
diary capture      # Quick scratchpad entry appended to today's note
diary voice        # Speech-to-text entry (Android/Termux)
diary search <txt> # Interactive search with preview
diary today        # Open today's note
diary random       # Open a random note
diary dir          # Print diary storage directory path
diary settings     # Open configuration file in editor
diary stats        # Show word counts and stats
diary update       # Manual git pull, commit, and push
diary help         # Show command list
```

## Config

Config is saved at `~/.config/diary/config` (open anytime with `diary settings`):

```bash
DIARY_DIR="$HOME/Documents/Diary"
DIARY_EDITOR="nano"
```

## Android (Termux) Notes

- **Storage**: Run `termux-setup-storage` if saving to shared phone storage (`~/storage/shared/...`).
- **Voice Input**: `diary voice` requires the `termux-api` package (`pkg install termux-api`) and the **Termux:API** app from F-Droid.