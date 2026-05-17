vim9script

if exists('g:loaded_git_changes')
  finish
endif
g:loaded_git_changes = 1

if !has('vim9script')
  echoerr 'git-changes requires Vim9 (Vim 9.0+)'
  finish
endif

command! GitChanges git_changes#Toggle()
command! GitChangesRefresh git_changes#Refresh()

if !hasmapto('<Plug>(GitChangesToggle)')
  nnoremap <silent> <leader>gs <ScriptCmd>git_changes#Toggle()<CR>
endif
