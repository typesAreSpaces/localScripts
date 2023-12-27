#!/usr/bin/env bash

USERNAME='jose.castellanosjoo'
DOMAIN='cs.unm.edu'

rsync -avz --delete ~/.config/jose-emacs $USERNAME@moons.$DOMAIN:~/Documents/jose-emacs
