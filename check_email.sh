#! /bin/sh

email="$(cat ~/.unread_email | xargs)"
if [ -z "$email" ]
then
  printf "%s" " X"
else
  printf "%s" "${email}"
fi
