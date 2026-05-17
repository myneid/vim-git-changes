# vim-git-changes

A VSCode-style git Source Control panel for **Vim 9** — written entirely in
Vim9script with no external dependencies beyond `git` itself.

```
┌─────────────────────┬──────────────────────────────────────┐
│  GIT CHANGES        │                                      │
│  ────────────────── │                                      │
│  STAGED (1)         │                                      │
│  ✓ M  src/foo.js    │         diff view                    │
│                     │         (filetype=diff)              │
│  CHANGES (2)        │                                      │
│  · M  src/bar.js    │                                      │
│  · ?  src/new.js    │                                      │
│  ────────────────── │                                      │
│  <CR> diff  s stage │                                      │
├─────────────────────┤                                      │
│  commit message     │                                      │
│  (write here…)      │                                      │
└─────────────────────┴──────────────────────────────────────┘
```

## Requirements

- **Vim 9.0+** (Vim9script — Neovim is not supported)
- `git` in `$PATH`
- *(optional)* `gh` CLI + Copilot subscription for AI commit messages
- *(optional)* `curl` for the Copilot API call

## Installation

**Native packages** (recommended):
```sh
mkdir -p ~/.vim/pack/plugins/start
git clone https://github.com/yourname/vim-git-changes \
    ~/.vim/pack/plugins/start/vim-git-changes
vim -u NONE -c 'helptags ~/.vim/pack/plugins/start/vim-git-changes/doc' -c q
```

**vim-plug:**
```vim
Plug 'yourname/vim-git-changes'
```

**Local path:**
```vim
Plug '~/Dropbox/Documents/0x7a69/vim-git-changes'
```

After installation run `:helptags ALL` once so `:help git-changes` works.

## Usage

Toggle the panel from any buffer inside a git repo:

```vim
:GitChanges
" or the default mapping:
<leader>gs
```

### File panel

| Key | Action |
|-----|--------|
| `<CR>` / double-click | Open diff for the file under the cursor |
| `s` | Stage file (`git add`) |
| `u` | Unstage file (`git restore --staged`) |
| `r` | Refresh the list |
| `cc` | Jump to the commit message panel (insert mode) |
| `q` | Close the panel |
| `?` | Print keybinding reference |

### Commit panel

| Key | Action |
|-----|--------|
| `<C-CR>` | Commit with the current message (normal or insert mode) |
| `<C-p>` | Ask GitHub Copilot to draft the commit message |
| `q` | Return focus to the file list |

Lines starting with `#` are stripped (same convention as `COMMIT_EDITMSG`).

## GitHub Copilot commit messages

`<C-p>` in the commit panel:

1. Collects `git diff --staged` (falls back to `git diff`)
2. Gets an ephemeral token via `gh api copilot_internal/v2/token`
3. Sends the diff (first 300 lines) to `api.githubcopilot.com/chat/completions`
4. Pastes the suggested message into the commit buffer

**Requirements:** `gh auth login` + an active Copilot subscription.

Check it works manually:
```sh
gh api copilot_internal/v2/token -q .token
```
If that prints a token, Copilot integration is ready.

## Configuration

```vim
" sidebar width in columns (default 42)
let g:git_changes_width = 50

" commit panel height in lines (default 8)
let g:git_changes_commit_height = 10
```

### Colour overrides

```vim
highlight GitChangesStagedFile   guifg=#98c379
highlight GitChangesUnstagedFile guifg=#e5c07b
highlight GitChangesStatusAdd    guifg=#98c379 gui=bold
highlight GitChangesStatusMod    guifg=#e5c07b gui=bold
highlight GitChangesStatusDel    guifg=#e06c75 gui=bold
```

Full list of highlight groups: `:help git-changes-config`

### Custom toggle mapping

```vim
" Before the plugin loads, or in after/plugin:
nmap <leader>gc <Plug>(GitChangesToggle)
```

## Status icons

| Icon | Meaning |
|------|---------|
| `M` | Modified |
| `A` | Added |
| `D` | Deleted |
| `R` | Renamed |
| `C` | Copied |
| `!` | Unmerged (conflict) |
| `?` | Untracked |

A file can appear under both STAGED and CHANGES if it has mixed staged/unstaged hunks.

## Commands

| Command | Description |
|---------|-------------|
| `:GitChanges` | Toggle the panel |
| `:GitChangesRefresh` | Re-run `git status` and redraw |

The panel auto-refreshes on `BufWritePost` and `ShellCmdPost` while open.

## Full documentation

```vim
:help git-changes
```

## License

[The Unlicense](LICENSE) — public domain. Do whatever you want.
