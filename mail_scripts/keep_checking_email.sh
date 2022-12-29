#!/bin/bash

# To enable mbsync write 'yes' on the file $ENABLE_MBSYNC
# To disable mbsync write anything but 'yes' on the file $ENABLE_MBSYNC

ENABLE_MBSYNC="$HOME/.enable_mbsync"
FILE="$HOME/.unread_email"
DIR="$HOME/Mail/unm/Inbox/new"

while [ 1 ]; do
  if [ "$(cat .enable_mbsync | xargs)" = "yes" ]; then mbsync -a; fi
  echo ' '> $FILE
  ls $DIR | wc -l | xargs >> $FILE
  sleep 15;
done;
