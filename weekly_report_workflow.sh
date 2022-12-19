#!/bin/zsh                                                                                                   
SESSIONNAME="weekly report"
NVS="nvim --listen localhost:12345 -S session"
PHD_THESIS_DOCS="$PHD_THESIS_DIR/Documents"
CURRENT_REPORT_DIR="$PHD_THESIS_DOCS/Write-Ups/weekly_reports/Fall-2021/doris_algorithm"

tmux has-session -t $SESSIONNAME &> /dev/null

if [ $? != 0 ] 
 then
    tmux new-session -s $SESSIONNAME -d

    WINDOW=1
    tmux rename-window -t $SESSIONNAME:$WINDOW 'todo'
    tmux send-keys -t $SESSIONNAME:$WINDOW "emacs -nw $PHD_THESIS_DIR/todolist.org" C-m

    WINDOW=2
    tmux new-window -t $SESSIONNAME:$WINDOW -n 'books'
    tmux send-keys -t $SESSIONNAME:$WINDOW "cd $PHD_THESIS_DOCS/Books" C-m

    WINDOW=3
    tmux new-window -t $SESSIONNAME:$WINDOW -n 'papers'
    tmux send-keys -t $SESSIONNAME:$WINDOW "cd $PHD_THESIS_DOCS/Papers" C-m

    WINDOW=4
    tmux new-window -t $SESSIONNAME:$WINDOW -n 'personal notes'
    tmux send-keys -t $SESSIONNAME:$WINDOW "cd $PHD_THESIS_DOCS/Write-Ups/personal_notes; $NVS" C-m

    WINDOW=5
    tmux new-window -t $SESSIONNAME:$WINDOW -n 'current report'
    tmux send-keys -t $SESSIONNAME:$WINDOW "cd $CURRENT_REPORT_DIR; $NVS" C-m

    WINDOW=6
    tmux new-window -t $SESSIONNAME:$WINDOW -n 'terminal'
fi

tmux attach -t $SESSIONNAME
