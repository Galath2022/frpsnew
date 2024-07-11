#!/bin/sh
export KSROOT=/koolshare
source $KSROOT/scripts/base.sh

sh /koolshare/scripts/frpsnew_config.sh stop >/dev/null 2>&1

rm -f /koolshare/bin/frpsnew
find /koolshare/init.d/ -name "*frps*" | xargs rm -rf
rm -rf /koolshare/res/icon-frpsnew.png
rm -rf /koolshare/scripts/frpsnew_*.sh
rm -rf /koolshare/webs/Module_frpsnew.asp
rm -f /koolshare/scripts/uninstall_frpsnew.sh
rm -f /koolshare/configs/frpsnew.toml

values=$(dbus list frps | cut -d "=" -f 1)
for value in $values
do
	dbus remove $value
done