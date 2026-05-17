vim9script

# ── state ─────────────────────────────────────────────────────────────────────

var s = {
  files_winid:  -1,
  commit_winid: -1,
  files_bufnr:  -1,
  commit_bufnr: -1,
  git_root:     '',
  files:        [],   # list of {xy, staged, path, icon}
  diff_source:  '',
}

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
  s.files = ParseStatus(s.git_root)
  RenderFileList()
enddef

# ── open / close ──────────────────────────────────────────────────────────────

def IsOpen(): bool
  return s.files_winid != -1 && win_id2win(s.files_winid) != 0
enddef

def Open()
  var root = FindGitRoot()
  if root == ''
    echohl WarningMsg | echo 'git-changes: not inside a git repository' | echohl None
    return
  endif
  s.git_root = root

  # ── files panel (top-left vertical split) ────────────────────────────────
  noautocmd topleft vnew
  s.files_winid = win_getid()
  s.files_bufnr = bufnr()
  SetupFilesBuffer()
  execute 'vertical resize ' .. get(g:, 'git_changes_width', 42)

  # ── commit panel below files ──────────────────────────────────────────────
  noautocmd execute 'belowright ' .. get(g:, 'git_changes_commit_height', 8) .. 'new'
  s.commit_winid = win_getid()
  s.commit_bufnr = bufnr()
  SetupCommitBuffer()

  # populate & focus
  win_gotoid(s.files_winid)
  s.files = ParseStatus(root)
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
  for wid in [s.commit_winid, s.files_winid]
    if win_id2win(wid) != 0
      win_execute(wid, 'close')
    endif
  endfor
  s.files_winid  = -1
  s.commit_winid = -1
enddef

# ── buffer setup ──────────────────────────────────────────────────────────────

def SetupFilesBuffer()
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber signcolumn=no
  setlocal cursorline nowrap winfixwidth
  setlocal filetype=gitchangesfiles

  # mappings fire while cursor is in this buffer → line('.') is valid
  nnoremap <buffer><nowait> <CR>          <ScriptCmd>OpenSelectedDiff()<CR>
  nnoremap <buffer><nowait> <2-LeftMouse> <ScriptCmd>OpenSelectedDiff()<CR>
  nnoremap <buffer><nowait> s             <ScriptCmd>StageSelected()<CR>
  nnoremap <buffer><nowait> u             <ScriptCmd>UnstageSelected()<CR>
  nnoremap <buffer><nowait> r             <ScriptCmd>Refresh()<CR>
  nnoremap <buffer><nowait> cc            <ScriptCmd>FocusCommit()<CR>
  nnoremap <buffer><nowait> q             <ScriptCmd>Close()<CR>
  nnoremap <buffer><nowait> ?             <ScriptCmd>ShowHelp()<CR>
enddef

def SetupCommitBuffer()
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber signcolumn=no
  setlocal wrap winfixheight textwidth=72
  setlocal filetype=gitcommit
  setlocal statusline=\ COMMIT\ MESSAGE

  nnoremap <buffer><nowait> <C-CR> <ScriptCmd>DoCommit()<CR>
  inoremap <buffer><nowait> <C-CR> <Esc><ScriptCmd>DoCommit()<CR>
  nnoremap <buffer><nowait> <C-p>  <ScriptCmd>CopilotMessage()<CR>
  inoremap <buffer><nowait> <C-p>  <Esc><ScriptCmd>CopilotMessage()<CR>
  nnoremap <buffer><nowait> q      <ScriptCmd>win_gotoid(s.files_winid)<CR>
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
    # Renames: "old -> new" → keep the new name
    if stridx(path, ' -> ') != -1
      path = split(path, ' -> ')[1]
    endif
    var staged   = xy[0] != ' ' && xy[0] != '?'
    var unstaged = xy[1] != ' '
    var icon = StatusIcon(xy)
    if staged
      result->add({xy: xy, staged: 'staged',   path: path, icon: icon})
    endif
    if unstaged
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
  if win_id2win(s.files_winid) == 0
    return
  endif

  # copy() avoids mutating s.files with filter()
  var staged   = copy(s.files)->filter((_, f) => f.staged == 'staged')
  var unstaged = copy(s.files)->filter((_, f) => f.staged == 'unstaged')

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
  lines->add('  <CR> diff  s stage  u unstage  cc commit  ? help')

  # Temporarily allow writes to this nomodifiable buffer
  setbufvar(s.files_bufnr, '&modifiable', 1)
  setbufline(s.files_bufnr, 1, lines)
  deletebufline(s.files_bufnr, len(lines) + 1, '$')
  setbufvar(s.files_bufnr, '&modifiable', 0)
enddef

# ── actions ───────────────────────────────────────────────────────────────────

def FileAtCursor(): dict<string>
  var text = trim(getline('.'))
  for f in s.files
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
  # Find first window that isn't our panels
  var target = -1
  for wid in win_list()
    if wid != s.files_winid && wid != s.commit_winid
      target = wid
      break
    endif
  endfor

  if target == -1
    win_gotoid(s.files_winid)
    noautocmd rightbelow vnew
    target = win_getid()
  endif

  win_gotoid(target)

  # Prefer staged diff, then HEAD diff
  var cmd_staged = 'git -C ' .. shellescape(s.git_root) .. ' diff --cached -- ' .. shellescape(f.path) .. ' 2>/dev/null'
  var cmd_head   = 'git -C ' .. shellescape(s.git_root) .. ' diff HEAD -- '    .. shellescape(f.path) .. ' 2>/dev/null'
  var diff_output = systemlist(f.staged == 'staged' ? cmd_staged : cmd_head)
  if empty(diff_output)
    diff_output = systemlist(f.staged == 'staged' ? cmd_head : cmd_staged)
  endif

  # Reuse or create the diff buffer
  var bname = '__GitDiff__'
  var diff_buf = bufnr(bname)
  if diff_buf != -1 && bufwinnr(diff_buf) != -1
    execute 'buffer ' .. diff_buf
  else
    noautocmd enew
    execute 'silent! file ' .. bname
  endif

  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal filetype=diff
  setlocal modifiable noreadonly
  silent! %delete _
  setline(1, ['  Diff: ' .. f.path, ''])
  append('$', empty(diff_output) ? ['  (no diff — file may be untracked)'] : diff_output)
  setlocal nomodifiable
  normal! gg
  s.diff_source = f.path

  # Return focus to files panel
  win_gotoid(s.files_winid)
enddef

def StageSelected()
  var f = FileAtCursor()
  if empty(f)
    return
  endif
  call system('git -C ' .. shellescape(s.git_root) .. ' add -- ' .. shellescape(f.path))
  Refresh()
enddef

def UnstageSelected()
  var f = FileAtCursor()
  if empty(f)
    return
  endif
  call system('git -C ' .. shellescape(s.git_root) .. ' restore --staged -- ' .. shellescape(f.path))
  Refresh()
enddef

def FocusCommit()
  if win_id2win(s.commit_winid) != 0
    win_gotoid(s.commit_winid)
    startinsert!
  endif
enddef

def DoCommit()
  if win_id2win(s.commit_winid) == 0
    return
  endif
  var lines = getbufline(s.commit_bufnr, 1, '$')
    ->filter((_, l) => l !~ '^\s*#')  # strip comment lines

  while !empty(lines) && trim(lines[0])  == ''  | remove(lines, 0)  | endwhile
  while !empty(lines) && trim(lines[-1]) == ''  | remove(lines, -1) | endwhile

  if empty(lines)
    echohl WarningMsg | echo 'git-changes: commit message is empty' | echohl None
    return
  endif

  var tmp = tempname()
  writefile(lines, tmp)
  var out = system('git -C ' .. shellescape(s.git_root) .. ' commit -F ' .. shellescape(tmp))
  delete(tmp)

  if v:shell_error != 0
    echohl ErrorMsg | echo 'git-changes: commit failed — ' .. trim(out) | echohl None
    return
  endif

  echo 'git-changes: committed!'
  setbufline(s.commit_bufnr, 1, [''])
  deletebufline(s.commit_bufnr, 2, '$')
  Refresh()
enddef

# ── copilot commit message ────────────────────────────────────────────────────

def CopilotMessage()
  echo 'git-changes: generating commit message via Copilot...'

  var diff = system('git -C ' .. shellescape(s.git_root) .. ' diff --staged 2>/dev/null')
  if trim(diff) == ''
    diff = system('git -C ' .. shellescape(s.git_root) .. ' diff 2>/dev/null')
  endif
  if trim(diff) == ''
    echohl WarningMsg | echo 'git-changes: nothing to diff' | echohl None
    return
  endif

  var msg = TryCopilotAPI(diff)
  if msg == ''
    echohl WarningMsg | echo 'git-changes: Copilot unavailable (needs gh CLI + Copilot subscription)' | echohl None
    return
  endif

  if win_id2win(s.commit_winid) == 0
    return
  endif
  win_gotoid(s.commit_winid)
  setbufline(s.commit_bufnr, 1, split(msg, "\n"))
  startinsert!
enddef

def TryCopilotAPI(diff: string): string
  var token = trim(system('gh api copilot_internal/v2/token -q .token 2>/dev/null'))
  if v:shell_error != 0 || token == ''
    return ''
  endif

  var short_diff = split(diff, "\n")[: 300]->join("\n")
  var prompt = "Write a concise git commit message (imperative mood, max 72 chars subject line). Reply with ONLY the commit message, no explanation.\n\nDiff:\n" .. short_diff

  var payload = json_encode({
    model: 'gpt-4o',
    messages: [{role: 'user', content: prompt}],
    max_tokens: 100,
    temperature: 0.2,
  })

  var tmp = tempname()
  writefile([payload], tmp)
  var resp = system(
    'curl -sf -X POST https://api.githubcopilot.com/chat/completions'
    .. ' -H ' .. shellescape('Authorization: Bearer ' .. token)
    .. ' -H "Content-Type: application/json"'
    .. ' -H "Copilot-Integration-Id: vscode-chat"'
    .. ' -d @' .. shellescape(tmp)
  )
  delete(tmp)

  if v:shell_error != 0 || resp == ''
    return ''
  endif

  try
    var parsed = json_decode(resp)
    return trim(parsed.choices[0].message.content)
  catch
    return ''
  endtry
enddef

# ── help ──────────────────────────────────────────────────────────────────────

def ShowHelp()
  echo join([
    'git-changes keybindings',
    '────────────────────────',
    '<CR> / click   open diff',
    's              stage file',
    'u              unstage file',
    'r              refresh list',
    'cc             write commit message',
    'q              close panel',
    '',
    'Commit window:',
    '<C-CR>   commit',
    '<C-p>    Copilot suggest message',
    'q        back to file list',
  ], "\n")
enddef
