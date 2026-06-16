vim9script

# ── state (typed module-level vars so Vim9 can compile all def functions) ─────

var files_winid:   number = -1
var commit_winid:  number = -1
var files_bufnr:   number = -1
var commit_bufnr:  number = -1
var git_root:      string = ''
var changed_files: list<dict<string>> = []
var diff_source:   string = ''

var pr_create_winid: number = -1
var pr_create_bufnr: number = -1
var pr_panel_winid:  number = -1
var pr_panel_bufnr:  number = -1
var pr_url_store:    string = ''

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

export def PullRequest()
  OpenPRCreate()
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
  setlocal statusline=\ COMMIT\ MESSAGE\ \ \ <CR>/<C-s>\ commit\ \ <C-p>\ copilot

  # <CR> in normal mode and <C-s> in both modes — <C-CR> doesn't survive terminals
  nnoremap <buffer><nowait> <CR>   <ScriptCmd>DoCommit()<CR>
  nnoremap <buffer><nowait> <C-s>  <ScriptCmd>DoCommit()<CR>
  inoremap <buffer><nowait> <C-s>  <Esc><ScriptCmd>DoCommit()<CR>
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
  nnoremap <buffer><nowait> S             <ScriptCmd>StageAll()<CR>
  nnoremap <buffer><nowait> u             <ScriptCmd>UnstageSelected()<CR>
  nnoremap <buffer><nowait> U             <ScriptCmd>UnstageAll()<CR>
  nnoremap <buffer><nowait> r             <ScriptCmd>Refresh()<CR>
  nnoremap <buffer><nowait> cc            <ScriptCmd>FocusCommit()<CR>
  nnoremap <buffer><nowait> <Tab>         <ScriptCmd>FocusCommit()<CR>
  nnoremap <buffer><nowait> P             <ScriptCmd>OpenPRCreate()<CR>
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
  lines->add('  s  stage file    S  stage all')
  lines->add('  u  unstage file  U  unstage all')
  lines->add('  r  refresh       q  close')
  lines->add('  <Tab>  commit    P  pull request')
  lines->add('  ?  help')

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

  # Auto-stage everything if nothing is staged yet
  var has_staged = trim(system(
    'git -C ' .. shellescape(git_root) .. ' diff --cached --name-only 2>/dev/null'
  )) != ''
  if !has_staged
    system('git -C ' .. shellescape(git_root) .. ' add -A')
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
  Close()
enddef

def StageAll()
  system('git -C ' .. shellescape(git_root) .. ' add -A')
  Refresh()
enddef

def UnstageAll()
  system('git -C ' .. shellescape(git_root) .. ' restore --staged -- .')
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
    '  s              stage file',
    '  S              stage ALL files',
    '  u              unstage file',
    '  U              unstage ALL files',
    '  r              refresh list',
    '  <Tab>          go to commit message',
    '  P              create pull request',
    '  q              close panel',
    '  ?              this help',
    '',
    'Commit panel:',
    '  <CR>           commit  (normal mode)',
    '  <C-s>          commit  (normal or insert mode)',
    '  <C-p>          Copilot: generate message',
    '  <Tab> / q      back to file list',
    '',
    'Pull request panel:',
    '  <CR> / m       merge PR',
    '  <C-p>          Copilot: suggest conflict fixes',
    '  q              close panel',
    '',
    'Note: if nothing is staged, commit auto-stages',
    'all changes before committing.',
  ], "\n")
enddef

# ── PR create ─────────────────────────────────────────────────────────────────

def PRBaseBranch(root: string): string
  var base = trim(system('gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null'))
  if base == '' || v:shell_error != 0
    base = trim(system('git -C ' .. shellescape(root)
      .. ' symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null'))
    base = substitute(base, '^origin/', '', '')
  endif
  return base != '' ? base : 'main'
enddef

def OpenPRCreate()
  var root = git_root != '' ? git_root : FindGitRoot()
  if root == ''
    echohl WarningMsg | echo 'git-changes: not inside a git repository' | echohl None
    return
  endif
  git_root = root

  var base   = PRBaseBranch(root)
  var branch = trim(system('git -C ' .. shellescape(root) .. ' rev-parse --abbrev-ref HEAD 2>/dev/null'))

  # title: first commit subject between base and HEAD
  var title = trim(system(
    'git -C ' .. shellescape(root)
    .. ' log origin/' .. shellescape(base) .. '..' .. shellescape(branch)
    .. ' --reverse --pretty=format:%s 2>/dev/null | head -1'
  ))
  if title == ''
    title = substitute(branch, '[_/-]', ' ', 'g')
  endif

  # body: one bullet per commit subject (single-quoted format to avoid glob expansion)
  var commit_lines = systemlist(
    'git -C ' .. shellescape(root)
    .. ' log origin/' .. shellescape(base) .. '..' .. shellescape(branch)
    .. " --reverse '--pretty=tformat:- %s' 2>/dev/null"
  )

  # files changed between base and HEAD (shown as read-only info)
  var file_lines = systemlist(
    'git -C ' .. shellescape(root)
    .. ' diff --name-status origin/' .. shellescape(base) .. '..' .. shellescape(branch)
    .. ' 2>/dev/null'
  )
  if empty(file_lines)
    # fallback: uncommitted changes vs local base
    file_lines = systemlist(
      'git -C ' .. shellescape(root)
      .. ' diff --name-status ' .. shellescape(base) .. ' 2>/dev/null'
    )
  endif

  # assemble buffer content
  var content: list<string> = [title, '']
  if !empty(commit_lines)
    content->extend(commit_lines)
    content->add('')
  endif
  content->add('# ──── FILES IN THIS PR (read-only below this line) ──────────────────────────')
  if empty(file_lines)
    content->add('#   (no file changes detected between ' .. base .. ' and ' .. branch .. ')')
  else
    for fl in file_lines
      content->add('#   ' .. fl)
    endfor
  endif

  # open buffer at the bottom
  if win_id2win(pr_create_winid) != 0
    win_execute(pr_create_winid, 'close')
  endif
  noautocmd botright new
  var panel_h = get(g:, 'git_changes_pr_height', 18)
  execute 'resize ' .. panel_h
  pr_create_winid = win_getid()
  pr_create_bufnr = bufnr()
  SetupPRCreateBuffer(content)
enddef

def SetupPRCreateBuffer(content: list<string>)
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber signcolumn=no
  setlocal wrap winfixheight textwidth=72
  setlocal filetype=markdown
  setlocal statusline=\ PR\ TITLE+BODY\ \ \ <CR>/<C-s>\ create\ PR\ \ q\ cancel

  nnoremap <buffer><nowait> <CR>   <ScriptCmd>DoCreatePR()<CR>
  nnoremap <buffer><nowait> <C-s>  <ScriptCmd>DoCreatePR()<CR>
  inoremap <buffer><nowait> <C-s>  <Esc><ScriptCmd>DoCreatePR()<CR>
  nnoremap <buffer><nowait> q      <ScriptCmd>ClosePRCreate()<CR>

  setbufline(pr_create_bufnr, 1, content)
  deletebufline(pr_create_bufnr, len(content) + 1, '$')
  normal! gg
  startinsert!
enddef

def ClosePRCreate()
  if win_id2win(pr_create_winid) != 0
    win_execute(pr_create_winid, 'close')
  endif
  pr_create_winid = -1
enddef

def DoCreatePR()
  if win_id2win(pr_create_winid) == 0
    return
  endif

  # collect editable lines — everything above the separator comment
  var all_lines = getbufline(pr_create_bufnr, 1, '$')
  var editable: list<string> = []
  for ln in all_lines
    if ln =~# '^# ────'
      break
    endif
    editable->add(ln)
  endfor

  while !empty(editable) && trim(editable[0])  == '' | remove(editable, 0)  | endwhile
  while !empty(editable) && trim(editable[-1]) == '' | remove(editable, -1) | endwhile

  if empty(editable)
    echohl WarningMsg | echo 'git-changes: PR title cannot be empty' | echohl None
    return
  endif

  var title      = editable[0]
  var body_lines = editable[1 : ]
  while !empty(body_lines) && trim(body_lines[0]) == '' | remove(body_lines, 0) | endwhile
  var body = join(body_lines, "\n")

  redraw | echo 'git-changes: creating PR...'

  var tmp_body = tempname()
  writefile(split(body, "\n"), tmp_body)
  var out = trim(system(
    'gh pr create'
    .. ' --title ' .. shellescape(title)
    .. ' --body-file ' .. shellescape(tmp_body)
    .. ' 2>&1'
  ))
  delete(tmp_body)

  if v:shell_error != 0
    # PR may already exist — grab its URL and continue
    if out =~# 'already exists'
      var existing = trim(system('gh pr view --json url --jq .url 2>/dev/null'))
      if existing != ''
        ClosePRCreate()
        echo 'git-changes: PR already exists'
        OpenPRPanel(existing)
        return
      endif
    endif
    echohl ErrorMsg | echo 'git-changes: gh pr create failed — ' .. out | echohl None
    return
  endif

  # gh pr create prints the URL as its last line
  var url = ''
  for ln in reverse(split(out, "\n"))
    if ln =~# '^https://'
      url = ln
      break
    endif
  endfor

  ClosePRCreate()
  echo 'git-changes: PR created! ' .. url
  if url != ''
    OpenPRPanel(url)
  endif
enddef

# ── PR panel ──────────────────────────────────────────────────────────────────

def OpenPRPanel(url: string)
  if win_id2win(pr_panel_winid) != 0
    win_execute(pr_panel_winid, 'close')
  endif

  pr_url_store = url

  noautocmd botright new
  execute 'resize 14'
  pr_panel_winid = win_getid()
  pr_panel_bufnr = bufnr()

  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber signcolumn=no
  setlocal nowrap winfixheight
  setlocal statusline=\ PULL\ REQUEST

  nnoremap <buffer><nowait> <CR>   <ScriptCmd>DoMergePR()<CR>
  nnoremap <buffer><nowait> m      <ScriptCmd>DoMergePR()<CR>
  nnoremap <buffer><nowait> <C-p>  <ScriptCmd>CopilotPRFix()<CR>
  nnoremap <buffer><nowait> q      <ScriptCmd>ClosePRPanel()<CR>

  RenderPRPanel(url, 'Checking merge status...')

  # query merge state and re-render
  var info = trim(system(
    'gh pr view ' .. shellescape(url)
    .. ' --json mergeable,mergeStateStatus,title'
    .. ' --jq "[.mergeable,.mergeStateStatus,.title]|join(\"|\")"'
    .. ' 2>/dev/null'
  ))

  var mergeable = 'UNKNOWN'
  var state     = ''
  var pr_title  = ''
  if info != ''
    var parts = split(info, '|')
    if len(parts) >= 1 | mergeable = parts[0] | endif
    if len(parts) >= 2 | state     = parts[1] | endif
    if len(parts) >= 3 | pr_title  = join(parts[2 :], '|') | endif
  endif

  RenderPRPanel(url, '', mergeable, state, pr_title)
enddef

def RenderPRPanel(url: string, status_msg: string,
    mergeable: string = '', state: string = '', pr_title: string = '')
  if win_id2win(pr_panel_winid) == 0
    return
  endif

  var lines: list<string> = []
  lines->add('  PULL REQUEST')
  lines->add('')
  if pr_title != ''
    lines->add('  ' .. pr_title)
    lines->add('')
  endif
  lines->add('  URL: ' .. url)
  lines->add('')
  lines->add('  ' .. repeat('─', 38))

  if status_msg != ''
    lines->add('  ' .. status_msg)
  elseif mergeable == 'MERGEABLE'
    lines->add('  Status: ready to merge')
    lines->add('')
    lines->add('  <CR> / m  merge PR')
  elseif mergeable == 'CONFLICTING'
    lines->add('  Status: has conflicts — cannot auto-merge')
    lines->add('')
    lines->add('  <C-p>  ask Copilot how to fix conflicts')
  else
    var display = state != '' ? state : mergeable
    lines->add('  Status: ' .. tolower(display))
    lines->add('')
    lines->add('  <CR> / m  attempt merge')
  endif

  lines->add('')
  lines->add('  q  close this panel')

  setbufvar(pr_panel_bufnr, '&modifiable', 1)
  setbufline(pr_panel_bufnr, 1, lines)
  deletebufline(pr_panel_bufnr, len(lines) + 1, '$')
  setbufvar(pr_panel_bufnr, '&modifiable', 0)
enddef

def ClosePRPanel()
  if win_id2win(pr_panel_winid) != 0
    win_execute(pr_panel_winid, 'close')
  endif
  pr_panel_winid = -1
enddef

def DoMergePR()
  var url = pr_url_store
  if url == ''
    return
  endif
  redraw | echo 'git-changes: merging PR...'
  var out = trim(system('gh pr merge ' .. shellescape(url) .. ' --merge 2>&1'))
  if v:shell_error != 0
    echohl ErrorMsg | echo 'git-changes: merge failed — ' .. out | echohl None
    return
  endif
  echo 'git-changes: merged! ' .. url
  ClosePRPanel()
enddef

def CopilotPRFix()
  var url = pr_url_store
  if url == ''
    return
  endif

  redraw | echo 'git-changes: asking Copilot about conflicts...'

  var token = trim(system('gh auth token 2>&1'))
  if v:shell_error != 0
    echohl ErrorMsg | echo 'git-changes (copilot): ' .. token | echohl None
    return
  endif

  # extract PR number from URL for context
  var pr_num = matchstr(url, '/pull/\zs\d\+')
  var prompt =
    'I have merge conflicts in GitHub PR ' .. pr_num .. ' (' .. url .. '). '
    .. 'Give me step-by-step instructions to resolve them locally using git. '
    .. 'Be concise and use git commands.'

  var payload = json_encode({
    model: 'gpt-4o',
    messages: [{role: 'user', content: prompt}],
    max_tokens: 400,
    temperature: 0.2,
  })

  var tmp = tempname()
  writefile([payload], tmp)
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
    echohl ErrorMsg | echo 'git-changes (copilot): no response' | echohl None
    return
  endif

  try
    var parsed = json_decode(resp)
    if type(parsed) == v:t_dict && has_key(parsed, 'message')
      echohl ErrorMsg | echo 'git-changes (copilot): ' .. parsed.message | echohl None
      return
    endif
    var suggestion = trim(parsed.choices[0].message.content)
    if suggestion == ''
      echohl WarningMsg | echo 'git-changes (copilot): empty response' | echohl None
      return
    endif
    ClosePRPanel()
    OpenCopilotAdviceBuffer(suggestion, url)
  catch
    echohl ErrorMsg | echo 'git-changes (copilot): ' .. resp[: 200] | echohl None
  endtry
enddef

def OpenCopilotAdviceBuffer(advice: string, url: string)
  noautocmd botright new
  execute 'resize 20'

  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber signcolumn=no
  setlocal wrap
  setlocal filetype=markdown
  setlocal statusline=\ COPILOT\ CONFLICT\ ADVICE\ \ \ q\ close

  nnoremap <buffer><nowait> q  <ScriptCmd>close<CR>

  var lines: list<string> = ['  CONFLICT RESOLUTION ADVICE', '', '  PR: ' .. url, '']
  for ln in split(advice, "\n")
    lines->add('  ' .. ln)
  endfor
  lines->add('')
  lines->add('  q  close')

  setline(1, lines)
  deletebufline(bufnr(), len(lines) + 1, line('$'))
  setlocal nomodifiable
  normal! gg
enddef
