#! /bin/sh

$HOME/.config/xmodmap/changeKBD $HOME/.current_binding
[ -f $HOME/.xsessionrc ] && source $HOME/.xsessionrc
[ "$(ps aux | grep 'bin.*keep_checking_email.sh' | wc -l | xargs)" = "1" ] \
  && $HOME/.local/scripts/mail_scripts/keep_checking_email.sh&
[ "$(ps aux | grep 'emacs' | wc -l | xargs)" = "1" ] \
  && emacs --with-profile=jose --daemon &
xset s off -dpms &

