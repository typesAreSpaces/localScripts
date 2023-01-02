#!/bin/sh

SOURCE=$HOME/Documents/GithubProjects/phd-thesis/Software/Mathematica/Packages
TARGET=$HOME/Library/Mathematica/Applications

for PACKAGE_PATH in $SOURCE/*; do
  PACKAGE_NAME=$(basename $PACKAGE_PATH)
  rm -rf $TARGET/$PACKAGE_NAME.wl
  ln -s $SOURCE/$PACKAGE_NAME/$PACKAGE_NAME.wl $TARGET/$PACKAGE_NAME.wl
done
