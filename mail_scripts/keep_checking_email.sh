#!/bin/bash

# To enable mbsync write 'yes' on the file $ENABLE_MBSYNC
# To disable mbsync write anything but 'yes' on the file $ENABLE_MBSYNC

ENABLE_MBSYNC=/home/jose/.enable_mbsync
FILE=/home/jose/.unread_email
DIR=/home/jose/Mail/unm/Inbox/new

while [ 1 ]; do
  # python ~/.local/scripts/UnseenMail/UnseenMail.py
  if [ "$(cat .enable_mbsync | xargs)" = "yes" ]; then mbsync -a; fi
  echo ' '> $FILE
  ls $DIR | wc -l | xargs >> $FILE
  sleep 15;
done;
