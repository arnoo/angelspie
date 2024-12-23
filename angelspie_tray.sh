#!/bin/bash
## ALLTRAY
#kitty --class=angelspie_kitty bash -c "cd /home/arno/dev/angelspie && pipenv run hy angelspie.hy -v; read" &
#sleep 2
#wmctrl -l -x
#WID=`wmctrl -l -x | grep angelspie_kitty | cut -d\  -f1`
#xseticon -id $WID /usr/share/icons/gnome/32x32/apps/preferences-desktop-remote-desktop.png
#echo $WID
#alltray -C -p $!

kdocker -i /usr/share/icons/hicolor/32x32/apps/org.xfce.xfdesktop.png kitty bash -c "cd /home/arno/dev/angelspie && pipenv run hy angelspie.hy -v; while true; do pipenv run hy angelspie.hy -v --delay 5; done; read"
