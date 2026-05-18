# vim-git-changes

A VSCode-style git Source Control panel for **Vim 9** — written entirely in
Vim9script with no external dependencies beyond `git` itself.

```
┌─────────────────────┬──────────────────────────────────────┐
│  COMMIT MESSAGE     │                                      │
│  (write here…)      │         diff view                    │
│  <CR>/<C-s> commit  │         (filetype=diff)              │
├─────────────────────┤                                      │
│  GIT CHANGES        │                                      │
│  ────────────────── │                                      │
│  STAGED (1)         │                                      │
│  ✓ M  src/foo.js    │                                      │
│                     │                                      │
│  CHANGES (2)        │                                      │
│  · M  src/bar.js    │                                      │
│  · ?  src/new.js    │                                      │
│  ────────────────── │                                      │
│  s stage  S stg all │                                      │
│  u unstage  <Tab>   │                                      │
└─────────────────────┴──────────────────────────────────────┘
```

## Requirements

- **Vim 9.0+** (Vim9script — Neovim is not supported)
- `git` in `$PATH`
- *(optional)* `gh` CLI authenticated with `gh auth login`, for AI commit messages
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

After installation run `:helptags ALL` once so `:help git-changes` works.

## Usage

Toggle the panel from any buffer inside a git repo:

```vim
:GitChanges
" or the default mapping:
<leader>gs
```

The sidebar opens on the left with the commit message area on top and the
file list below. The diff view appears in your main editing area when you
open a file.

---

### Commit panel *(top of sidebar)*

Write your commit message here. Lines starting with `#` are stripped before
committing, matching the `COMMIT_EDITMSG` convention.

| Key | Mode | Action |
|-----|------|--------|
| `<CR>` | normal | Commit staged changes |
| `<C-s>` | normal / insert | Commit staged changes |
| `<C-p>` | normal / insert | Ask Copilot to draft the message |
| `<Tab>` / `q` | normal | Go back to the file list |

> **Auto-stage:** if nothing is staged when you commit, all changes are
> staged automatically (`git add -A`) before the commit runs. You can also
> stage selectively first using `S` or `s` in the file list.

---

### File list panel *(bottom of sidebar)*

| Key | Action |
|-----|--------|
| `<CR>` / double-click | Open diff for the file under the cursor |
| `s` | Stage file under cursor (`git add`) |
| `S` | Stage **all** changed files (`git add -A`) |
| `u` | Unstage file under cursor (`git restore --staged`) |
| `U` | Unstage **all** staged files |
| `<Tab>` / `cc` | Jump to the commit message panel |
| `r` | Refresh the list |
| `q` | Close the panel |
| `?` | Print keybinding reference |

---

## GitHub Copilot commit messages

`<C-p>` in the commit panel:

1. Collects `git diff --staged` (falls back to `git diff` if nothing is staged)
2. Gets your GitHub auth token via `gh auth token`
3. Sends the diff (first 300 lines) to `api.githubcopilot.com/chat/completions`
4. Pastes the suggested message into the commit buffer

**Requirements:** `gh auth login` + an active GitHub Copilot subscription.

If it fails, the exact error from `gh` or the Copilot API is echoed so you
can see what went wrong.

---

## Configuration

```vim
" sidebar width in columns (default 42)
let g:git_changes_width = 50

" commit panel height in lines (default 8)
let g:git_changes_commit_height = 10
```

### Custom toggle mapping

```vim
" suppress the default <leader>gs and use your own:
nmap <leader>gc <Plug>(GitChangesToggle)
```

### Colour overrides

The file list uses the `gitchangesfiles` filetype. Override any highlight group:

```vim
highlight GitChangesStagedFile   guifg=#98c379
highlight GitChangesUnstagedFile guifg=#e5c07b
highlight GitChangesStatusAdd    guifg=#98c379 gui=bold
highlight GitChangesStatusMod    guifg=#e5c07b gui=bold
highlight GitChangesStatusDel    guifg=#e06c75 gui=bold
```

Full list of groups: `:help git-changes-config`

---

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

---

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
