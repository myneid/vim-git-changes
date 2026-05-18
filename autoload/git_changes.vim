vim9script

# ── state (typed module-level vars so Vim9 can compile all def functions) ─────

var files_winid:   number = -1
var commit_winid:  number = -1
var files_bufnr:   number = -1
var commit_bufnr:  number = -1
var git_root:      string = ''
var changed_files: list<dict<string>> = []
var diff_source:   string = ''

# ── public API ────────────────────────────────────────────────────────────────

export def Toggle()
  if IsOpen()
    Close()
  else
    Open()
  endif
enddef

export def Refresh()
  if !IsOpen()
    return
  endif
  changed_files = ParseStatus(git_root)
  RenderFileList()
enddef

# ── open / close ──────────────────────────────────────────────────────────────

def IsOpen(): bool
  return files_winid != -1 && win_id2win(files_winid) != 0
enddef

def Open()
  var root = FindGitRoot()
  if root == ''
    echohl WarningMsg | echo 'git-changes: not inside a git repository' | echohl None
    return
  endif
  git_root = root

  var sidebar_w = get(g:, 'git_changes_width', 42)
  var commit_h  = get(g:, 'git_changes_commit_height', 8)

  # ── file list: full-height left column ───────────────────────────────────
  # Create files panel first so the vertical resize only affects column width.
  noautocmd topleft vnew
  execute 'vertical resize ' .. sidebar_w
  files_winid = win_getid()
  files_bufnr = bufnr()
  SetupFilesBuffer()

  # ── commit panel: horizontal split above files ────────────────────────────
  # aboveleft new splits within the left column only — no global height change.
  noautocmd aboveleft new
  execute 'resize ' .. commit_h
  commit_winid = win_getid()
  commit_bufnr = bufnr()
  SetupCommitBuffer()

  win_gotoid(files_winid)
  changed_files = ParseStatus(root)
  RenderFileList()

  augroup GitChangesAuto
    autocmd!
    autocmd BufWritePost,ShellCmdPost * git_changes#Refresh()
  augroup END
enddef

def Close()
  augroup GitChangesAuto
    autocmd!
  augroup END
  for wid in [commit_winid, files_winid]
    if win_id2win(wid) != 0
      win_execute(wid, 'close')
    endif
  endfor
  files_winid  = -1
  commit_winid = -1
enddef

# ── buffer setup ──────────────────────────────────────────────────────────────

def SetupCommitBuffer()
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber signcolumn=no
  setlocal wrap winfixwidth winfixheight textwidth=72
  setlocal filetype=gitcommit
  setlocal statusline=\ COMMIT\ MESSAGE\ \ \ <C-CR>\ commit\ \ <C-p>\ copilot

  nnoremap <buffer><nowait> <C-CR> <ScriptCmd>DoCommit()<CR>
  inoremap <buffer><nowait> <C-CR> <Esc><ScriptCmd>DoCommit()<CR>
  nnoremap <buffer><nowait> <C-p>  <ScriptCmd>CopilotMessage()<CR>
  inoremap <buffer><nowait> <C-p>  <Esc><ScriptCmd>CopilotMessage()<CR>
  nnoremap <buffer><nowait> <Tab>  <ScriptCmd>win_gotoid(files_winid)<CR>
  nnoremap <buffer><nowait> q      <ScriptCmd>win_gotoid(files_winid)<CR>
enddef

def SetupFilesBuffer()
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber signcolumn=no
  setlocal cursorline nowrap winfixwidth
  setlocal filetype=gitchangesfiles

  nnoremap <buffer><nowait> <CR>          <ScriptCmd>OpenSelectedDiff()<CR>
  nnoremap <buffer><nowait> <2-LeftMouse> <ScriptCmd>OpenSelectedDiff()<CR>
  nnoremap <buffer><nowait> s             <ScriptCmd>StageSelected()<CR>
  nnoremap <buffer><nowait> u             <ScriptCmd>UnstageSelected()<CR>
  nnoremap <buffer><nowait> r             <ScriptCmd>Refresh()<CR>
  nnoremap <buffer><nowait> cc            <ScriptCmd>FocusCommit()<CR>
  nnoremap <buffer><nowait> <Tab>         <ScriptCmd>FocusCommit()<CR>
  nnoremap <buffer><nowait> q             <ScriptCmd>Close()<CR>
  nnoremap <buffer><nowait> ?             <ScriptCmd>ShowHelp()<CR>
enddef

# ── git helpers ───────────────────────────────────────────────────────────────

def FindGitRoot(): string
  var dir = expand('%:p:h')
  if dir == '' || dir == '.'
    dir = getcwd()
  endif
  var result = trim(system('git -C ' .. shellescape(dir) .. ' rev-parse --show-toplevel 2>/dev/null'))
  return v:shell_error == 0 ? result : ''
enddef

def ParseStatus(root: string): list<dict<string>>
  var raw = systemlist('git -C ' .. shellescape(root) .. ' status --porcelain=v1 2>/dev/null')
  var result: list<dict<string>> = []
  for ln in raw
    if len(ln) < 4
      continue
    endif
    var xy   = ln[0 : 1]
    var path = ln[3 : ]
    if stridx(path, ' -> ') != -1
      path = split(path, ' -> ')[1]
    endif
    var icon = StatusIcon(xy)
    if xy[0] != ' ' && xy[0] != '?'
      result->add({xy: xy, staged: 'staged',   path: path, icon: icon})
    endif
    if xy[1] != ' '
      result->add({xy: xy, staged: 'unstaged', path: path, icon: icon})
    endif
  endfor
  return result
enddef

def StatusIcon(xy: string): string
  var tbl = {M: 'M', A: 'A', D: 'D', R: 'R', C: 'C', U: '!', '?': '?'}
  var ch = xy[0] != ' ' && xy[0] != '?' ? xy[0] : xy[1]
  return get(tbl, ch, '·')
enddef

# ── rendering ─────────────────────────────────────────────────────────────────

def RenderFileList()
  if win_id2win(files_winid) == 0
    return
  endif

  var staged   = copy(changed_files)->filter((_, f) => f.staged == 'staged')
  var unstaged = copy(changed_files)->filter((_, f) => f.staged == 'unstaged')

  var lines: list<string> = []
  lines->add('  GIT CHANGES')
  lines->add('  ' .. repeat('─', 36))

  lines->add(printf('  STAGED (%d)', len(staged)))
  if empty(staged)
    lines->add('    (none)')
  else
    for f in staged
      lines->add(printf('  ✓ %s  %s', f.icon, f.path))
    endfor
  endif
  lines->add('')

  lines->add(printf('  CHANGES (%d)', len(unstaged)))
  if empty(unstaged)
    lines->add('    (none)')
  else
    for f in unstaged
      lines->add(printf('  · %s  %s', f.icon, f.path))
    endfor
  endif

  lines->add('')
  lines->add('  ' .. repeat('─', 36))
  lines->add('  <CR>  open diff')
  lines->add('  s     stage       u  unstage')
  lines->add('  r     refresh     q  close')
  lines->add('  <Tab> commit msg  ?  help')

  setbufvar(files_bufnr, '&modifiable', 1)
  setbufline(files_bufnr, 1, lines)
  deletebufline(files_bufnr, len(lines) + 1, '$')
  setbufvar(files_bufnr, '&modifiable', 0)
enddef

# ── actions ───────────────────────────────────────────────────────────────────

def FileAtCursor(): dict<string>
  var text = trim(getline('.'))
  for f in changed_files
    if stridx(text, f.path) != -1
      return f
    endif
  endfor
  return {}
enddef

def OpenSelectedDiff()
  var f = FileAtCursor()
  if empty(f)
    return
  endif
  ShowDiff(f)
enddef

def ShowDiff(f: dict<string>)
  # find first window that isn't one of our panel windows
  var target: number = -1
  for info in getwininfo()
    var wid: number = info.winid
    if wid != files_winid && wid != commit_winid
      target = wid
      break
    endif
  endfor

  if target == -1
    win_gotoid(files_winid)
    noautocmd rightbelow vnew
    target = win_getid()
  endif

  win_gotoid(target)

  # staged file → show cached diff first; unstaged → HEAD diff first
  var cmd_cached = 'git -C ' .. shellescape(git_root) .. ' diff --cached -- ' .. shellescape(f.path) .. ' 2>/dev/null'
  var cmd_head   = 'git -C ' .. shellescape(git_root) .. ' diff HEAD -- '     .. shellescape(f.path) .. ' 2>/dev/null'
  var diff_out: list<string> = []
  if f.staged == 'staged'
    diff_out = systemlist(cmd_cached)
    if empty(diff_out)
      diff_out = systemlist(cmd_head)
    endif
  else
    diff_out = systemlist(cmd_head)
    if empty(diff_out)
      diff_out = systemlist(cmd_cached)
    endif
  endif

  # reuse an existing __GitDiff__ window, or create a fresh buffer
  var bname    = '__GitDiff__'
  var diff_buf = bufnr(bname)
  if diff_buf != -1 && bufwinnr(diff_buf) != -1
    execute 'buffer ' .. diff_buf
  else
    noautocmd enew
    execute 'silent! file ' .. bname
  endif

  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal filetype=diff modifiable noreadonly

  # build content list then write it in one shot
  var content: list<string> = ['  Diff: ' .. f.path, '']
  if empty(diff_out)
    content->add('  (no diff — file may be untracked or already clean)')
  else
    content->extend(diff_out)
  endif
  setline(1, content)
  deletebufline(bufnr(), len(content) + 1, line('$'))

  setlocal nomodifiable
  normal! gg
  diff_source = f.path

  win_gotoid(files_winid)
enddef

def StageSelected()
  var f = FileAtCursor()
  if empty(f)
    return
  endif
  system('git -C ' .. shellescape(git_root) .. ' add -- ' .. shellescape(f.path))
  Refresh()
enddef

def UnstageSelected()
  var f = FileAtCursor()
  if empty(f)
    return
  endif
  system('git -C ' .. shellescape(git_root) .. ' restore --staged -- ' .. shellescape(f.path))
  Refresh()
enddef

def FocusCommit()
  if win_id2win(commit_winid) != 0
    win_gotoid(commit_winid)
    startinsert!
  endif
enddef

def DoCommit()
  if win_id2win(commit_winid) == 0
    return
  endif
  var lines = getbufline(commit_bufnr, 1, '$')
    ->filter((_, l) => l !~ '^\s*#')

  while !empty(lines) && trim(lines[0])  == '' | remove(lines, 0)  | endwhile
  while !empty(lines) && trim(lines[-1]) == '' | remove(lines, -1) | endwhile

  if empty(lines)
    echohl WarningMsg | echo 'git-changes: commit message is empty' | echohl None
    return
  endif

  var tmp = tempname()
  writefile(lines, tmp)
  var out = system('git -C ' .. shellescape(git_root) .. ' commit -F ' .. shellescape(tmp))
  delete(tmp)

  if v:shell_error != 0
    echohl ErrorMsg | echo 'git-changes: commit failed — ' .. trim(out) | echohl None
    return
  endif

  echo 'git-changes: committed!'
  setbufline(commit_bufnr, 1, [''])
  deletebufline(commit_bufnr, 2, '$')
  Refresh()
enddef

# ── copilot commit message ────────────────────────────────────────────────────

def CopilotMessage()
  var diff = system('git -C ' .. shellescape(git_root) .. ' diff --staged 2>/dev/null')
  if trim(diff) == ''
    diff = system('git -C ' .. shellescape(git_root) .. ' diff 2>/dev/null')
  endif
  if trim(diff) == ''
    echohl WarningMsg | echo 'git-changes (copilot): nothing to diff' | echohl None
    return
  endif

  redraw | echo 'git-changes: asking Copilot...'

  # Step 1 — get the gh auth token (works for all account types)
  var token = trim(system('gh auth token 2>&1'))
  if v:shell_error != 0
    echohl ErrorMsg | echo 'git-changes (copilot): ' .. token | echohl None
    return
  endif

  # Step 2 — call the Copilot chat completions endpoint
  var short_diff = split(diff, "\n")[: 300]->join("\n")
  var payload = json_encode({
    model: 'gpt-4o',
    messages: [{role: 'user', content:
      "Write a concise git commit message (imperative mood, max 72 chars subject line)."
      .. " Reply with ONLY the commit message, no explanation.\n\nDiff:\n" .. short_diff}],
    max_tokens: 100,
    temperature: 0.2,
  })

  var tmp = tempname()
  writefile([payload], tmp)
  # Use copilot-cli integration headers so the request is treated as a CLI call
  var resp = system(
    'curl -s -X POST https://api.githubcopilot.com/chat/completions'
    .. ' -H ' .. shellescape('Authorization: Bearer ' .. token)
    .. ' -H "Content-Type: application/json"'
    .. ' -H "Copilot-Integration-Id: copilot-cli"'
    .. ' -H "editor-version: gh-copilot/1.0.0"'
    .. ' -d @' .. shellescape(tmp)
  )
  delete(tmp)

  if trim(resp) == ''
    echohl ErrorMsg | echo 'git-changes (copilot): no response — check network' | echohl None
    return
  endif

  # Step 3 — parse and paste the message; surface any API-level error
  try
    var parsed = json_decode(resp)
    if type(parsed) == v:t_dict && has_key(parsed, 'message')
      echohl ErrorMsg | echo 'git-changes (copilot): ' .. parsed.message | echohl None
      return
    endif
    var msg = trim(parsed.choices[0].message.content)
    if msg == ''
      echohl WarningMsg | echo 'git-changes (copilot): empty response' | echohl None
      return
    endif
    if win_id2win(commit_winid) == 0
      return
    endif
    win_gotoid(commit_winid)
    setbufline(commit_bufnr, 1, split(msg, "\n"))
    startinsert!
  catch
    echohl ErrorMsg | echo 'git-changes (copilot): ' .. resp[: 200] | echohl None
  endtry
enddef

# ── help ──────────────────────────────────────────────────────────────────────

def ShowHelp()
  echo join([
    'git-changes keybindings',
    '─────────────────────────────────────────',
    'File list:',
    '  <CR> / click   open diff for file',
    '  s              stage file (git add)',
    '  u              unstage file',
    '  r              refresh list',
    '  <Tab> / cc     jump to commit message',
    '  q              close panel',
    '  ?              this help',
    '',
    'Commit panel:',
    '  <C-p>          generate message via Copilot',
    '  <C-CR>         commit staged changes',
    '  <Tab> / q      back to file list',
  ], "\n")
enddef
