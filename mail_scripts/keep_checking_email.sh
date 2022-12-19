#!/bin/bash

# To enable mbsync write 'yes' on the file $ENABLE_MBSYNC
# To disable mbsync write anything but 'yes' on the file $ENABLE_MBSYNC

ENABLE_MBSYNC=/Users/typesarespaces/.enable_mbsync
FILE=/Users/typesarespaces/.unread_email
DIR=/Users/typesarespaces/Mail/unm/Inbox/new

while [ 1 ]; do
  # python ~/.local/scripts/UnseenMail/UnseenMail.py
  if [ "$(cat $ENABLE_MBSYNC | xargs)" = "yes" ]; then mbsync -a; fi
  echo ' '> $FILE
  ls $DIR | wc -l | xargs >> $FILE
  sleep 15;
done;
