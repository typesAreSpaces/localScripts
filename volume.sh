#!/bin/bash

# You can call this script like this:
# $./volume.sh up
# $./volume.sh down
# $./volume.sh mute

base_dir='/usr/share/icons/Adwaita/32x32/status'
icon_high="$base_dir/audio-volume-high-symbolic.symbolic.png"
icon_medium="$base_dir/audio-volume-medium-symbolic.symbolic.png"
icon_low="$base_dir/audio-volume-low-symbolic.symbolic.png"
icon_muted="$base_dir/audio-volume-muted-symbolic.symbolic.png"
time_out=1000

function get_volume {
    pactl list sinks | grep '^[[:space:]]Volume:' | head -n $(( $SINK + 1 )) | tail -n  1 | sed -e 's,.* \([0-9][0-9]*\)%.*,\1,'

}

function is_mute {
  amixer get Master | grep '%' | grep -oE '[^ ]+$' | grep off > /dev/null
}

function send_notification {
  volume=`get_volume`
  # Make the bar with the special character ─ (it's not dash -)
  # https://en.wikipedia.org/wiki/Box-drawing_character
  bar=$(seq -s "─" $(($volume/3)) | sed 's/[0-9]//g')
  # Send the notification
  if (( $volume < 33 )); then
    dunstify -i $icon_low -t $time_out -r 2593 -u normal "$volume%   $bar"
  else
    if (( $volume > 66 )); then
      dunstify -i $icon_high -t $time_out -r 2593 -u normal "$volume%   $bar"
    else
      dunstify -i $icon_medium -t $time_out -r 2593 -u normal "$volume%   $bar"
    fi
  fi
}

case $1 in
  up)
    # Set the volume on (if it was muted)
    pactl set-sink-mute @DEFAULT_SINK@ 0
    # Increase volume (+ 5%)
    pactl set-sink-volume @DEFAULT_SINK@ +5%
    send_notification
    ;;
  down)
    pactl set-sink-mute @DEFAULT_SINK@ 0
    pactl set-sink-volume @DEFAULT_SINK@ -5%
    send_notification
    ;;
  mute)
    # Toggle mute
    pactl set-sink-mute @DEFAULT_SINK@ toggle
    if [[ "Mute: no" == $(pactl list sinks | grep '^[[:space:]]Mute:' | xargs) ]]; then
	echo 'haha';
      send_notification
    else
	echo 'hehe';
      dunstify -i $icon_muted -t $time_out -r 2593 -u normal "Mute"
    fi;
    ;;
esac

