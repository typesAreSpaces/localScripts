alias config='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
branch_name=$(config rev-parse --abbrev-ref HEAD)
config checkout master
config pull
config checkout $branch_name
config merge master -m "Update $branch_name"
