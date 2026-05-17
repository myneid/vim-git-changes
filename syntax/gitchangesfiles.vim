vim9script

if exists('b:current_syntax')
  finish
endif

syntax match GitChangesHeader    /^\s*GIT CHANGES/
syntax match GitChangesDivider   /^\s*─\+/
syntax match GitChangesSectionStaged   /^\s*STAGED\s*(.*)/
syntax match GitChangesSectionChanges  /^\s*CHANGES\s*(.*)/
syntax match GitChangesHint      /^\s*<.*$/

syntax match GitChangesStagedFile    /^\s*✓.*/ contains=GitChangesStatusAdd,GitChangesStatusMod,GitChangesStatusDel,GitChangesStatusRen
syntax match GitChangesUnstagedFile  /^\s*·.*/ contains=GitChangesStatusAdd,GitChangesStatusMod,GitChangesStatusDel,GitChangesStatusRen

syntax match GitChangesStatusAdd /\sA\s/ contained
syntax match GitChangesStatusMod /\sM\s/ contained
syntax match GitChangesStatusDel /\sD\s/ contained
syntax match GitChangesStatusRen /\sR\s/ contained
syntax match GitChangesStatusUnk /\s?\s/ contained

highlight default link GitChangesHeader    Title
highlight default link GitChangesDivider   Comment
highlight default link GitChangesSectionStaged   Keyword
highlight default link GitChangesSectionChanges  WarningMsg
highlight default link GitChangesHint      Comment
highlight default link GitChangesStagedFile    String
highlight default link GitChangesUnstagedFile  Normal
highlight default link GitChangesStatusAdd  DiffAdd
highlight default link GitChangesStatusMod  DiffChange
highlight default link GitChangesStatusDel  DiffDelete
highlight default link GitChangesStatusRen  Special
highlight default link GitChangesStatusUnk  Comment

b:current_syntax = 'gitchangesfiles'
