#!/bin/sh

source /koolshare/scripts/base.sh
eval $(dbus export frpsnew_)
TOML_FILE=/koolshare/configs/frpsnew.toml
LOG_FILE=/tmp/upload/frpsnew_log.txt
LOCK_FILE=/var/lock/frpsnew.lock
alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y年%m月%d日\ %X)】:'
true > $LOG_FILE

set_lock() {
	exec 1000>"$LOCK_FILE"
	flock -x 1000
}

unset_lock() {
	flock -u 1000
	rm -rf "$LOCK_FILE"
}

sync_ntp(){
	# START_TIME=$(date +%Y/%m/%d-%X)
	echo_date "尝试从ntp服务器：ntp1.aliyun.com 同步时间..."
	ntpclient -h ntp1.aliyun.com -i3 -l -s >/tmp/ali_ntp.txt 2>&1
	SYNC_TIME=$(cat /tmp/ali_ntp.txt|grep -E "\[ntpclient\]"|grep -Eo "[0-9]+"|head -n1)
	if [ -n "${SYNC_TIME}" ];then
		SYNC_TIME=$(date +%Y/%m/%d-%X @${SYNC_TIME})
		echo_date "完成！时间同步为：${SYNC_TIME}"
	else
		echo_date "时间同步失败，跳过！"
	fi
}
fun_nat_start(){
	if [ "${frpsnew_enable}" == "1" ];then
		if [ ! -L "/koolshare/init.d/N95Frps.sh" ];then
			echo_date "添加nat-start触发..."
			ln -sf /koolshare/scripts/frpsnew_config.sh /koolshare/init.d/N95Frps.sh
		fi
	else
		if [ -L "/koolshare/init.d/N95Frps.sh" ];then
			echo_date "删除nat-start触发..."
			rm -rf /koolshare/init.d/N95Frps.sh >/dev/null 2>&1
		fi
	fi
}
onstart() {
	# 插件开启的时候同步一次时间
	if [ "${frpsnew_enable}" == "1" -a -n "$(which ntpclient)" ];then
		sync_ntp
	fi

	# 关闭frps进程
	if [ -n "$(pidof frpsnew)" ];then
		echo_date "关闭当前frps进程..."
		killall frpsnew >/dev/null 2>&1
	fi
	
	# 插件安装的时候移除frps_client_version，插件第一次运行的时候设置一次版本号即可
	if [ -z "${frpsnew_client_version}" ];then
		dbus set frpsnew_client_version=$(/koolshare/bin/frpsnew --version)
		frpsnew_client_version=$(/koolshare/bin/frpsnew --version)
	fi
	echo_date "当前插件frps主程序版本号：${frpsnew_client_version}"

	# frps配置文件
	echo_date "生成frps配置文件到 /koolshare/configs/frpsnew.toml"
	cat >${TOML_FILE} <<-EOF
	# [common] is integral section
	bindPort = ${frpsnew_bindPort}
	# QUIC 绑定的是 UDP 端口，可以和 bindPort 一样
	quicBindPort = ${frpsnew_bindPort}
	vhostHTTPPort = ${frpsnew_vhostHTTPPort}
	vhostHTTPSPort = ${frpsnew_vhostHTTPSPort}
	# console or real logFile path like ./frpsnew.log
	log.to = ${frpsnew_common_log_file}
	# debug, info, warn, error
	log.level = ${frpsnew_common_log_level}
	log.maxDays = ${frpsnew_common_log_max_days}
	# if you enable privilege mode, frpc can create a proxy without pre-configure in frps when privilege_token is correct
	auth.token = ${frpsnew_auth_token}
	# pool_count in each proxy will change to max_pool_count if they exceed the maximum value
	transport.maxPoolCount = ${frpsnew_transport_maxPoolCount}
	
	EOF

	# 定时任务
	if [ "${frpsnew_common_cron_time}" == "0" ]; then
		cru d frpsnew_monitor >/dev/null 2>&1
	else
		if [ "${frpsnew_common_cron_hour_min}" == "min" ]; then
			echo_date "设置定时任务：每隔${frpsnew_common_cron_time}分钟注册一次frps服务..."
			cru a frpsnew_monitor "*/"${frpsnew_common_cron_time}" * * * * /bin/sh /koolshare/scripts/frpsnew_config.sh"
		elif [ "${frpsnew_common_cron_hour_min}" == "hour" ]; then
			echo_date "设置定时任务：每隔${frpsnew_common_cron_time}小时注册一次frps服务..."
			cru a frpsnew_monitor "0 */"${frpsnew_common_cron_time}" * * * /bin/sh /koolshare/scripts/frpsnew_config.sh"
		fi
		echo_date "定时任务设置完成！"
	fi

	# 开启frps
	if [ "$frpsnew_enable" == "1" ]; then
		echo_date "启动frps主程序..."
		export GOGC=40
		start-stop-daemon -S -q -b -m -p /var/run/frpsnew.pid -x /koolshare/bin/frpsnew -- -c ${TOML_FILE}

		local FRPSPID
		local i=10
		until [ -n "$FRPSPID" ]; do
			i=$(($i - 1))
			FRPSPID=$(pidof frpsnew)
			if [ "$i" -lt 1 ]; then
				echo_date "frps进程启动失败！"
				echo_date "可能是内存不足造成的，建议使用虚拟内存后重试！"
				close_in_five
			fi
			usleep 250000
		done
		echo_date "frps启动成功，pid：${FRPSPID}"
		fun_nat_start
		open_port
	else
		stop
	fi
	echo_date "frps插件启动完毕，本窗口将在5s内自动关闭！"
}
check_port(){
	local prot=$1
	local port=$2
	local open=$(iptables -S -t filter | grep INPUT | grep dport | grep ${prot} | grep ${port})
	if [ -n "${open}" ];then
		echo 0
	else
		echo 1
	fi
}
open_port(){
	local t_port
	local u_port
	[ "$(check_port tcp ${frpsnew_vhostHTTPPort})" == "1" ] && iptables -I INPUT -p tcp --dport ${frpsnew_vhostHTTPPort} -j ACCEPT >/tmp/ali_ntp.txt 2>&1 && t_port="${frpsnew_vhostHTTPPort}"
	[ "$(check_port tcp ${frpsnew_vhostHTTPSPort})" == "1" ] && iptables -I INPUT -p tcp --dport ${frpsnew_vhostHTTPSPort} -j ACCEPT >/tmp/ali_ntp.txt 2>&1 && t_port="${t_port} ${frpsnew_vhostHTTPSPort}"
	[ "$(check_port tcp ${frpsnew_bindPort})" == "1" ] && iptables -I INPUT -p tcp --dport ${frpsnew_bindPort} -j ACCEPT >/tmp/ali_ntp.txt 2>&1 && t_port="${t_port} ${frpsnew_bindPort}"
	[ "$(check_port udp ${frpsnew_vhostHTTPPort})" == "1" ] && iptables -I INPUT -p udp --dport ${frpsnew_vhostHTTPPort} -j ACCEPT >/tmp/ali_ntp.txt 2>&1 && u_port="${frpsnew_vhostHTTPPort}"
	[ "$(check_port udp ${frpsnew_vhostHTTPSPort})" == "1" ] && iptables -I INPUT -p udp --dport ${frpsnew_vhostHTTPSPort} -j ACCEPT >/tmp/ali_ntp.txt 2>&1 && u_port="${u_port} ${frpsnew_vhostHTTPSPort}"
	[ "$(check_port udp ${frpsnew_bindPort})" == "1" ] && iptables -I INPUT -p udp --dport ${frpsnew_bindPort} -j ACCEPT >/tmp/ali_ntp.txt 2>&1 && u_port="${u_port} ${frpsnew_bindPort}"
	[ -n "${t_port}" ] && echo_date "开启TCP端口：${t_port}"
	[ -n "${u_port}" ] && echo_date "开启UDP端口：${u_port}"
}
close_port(){
	local t_port
	local u_port
	[ "$(check_port tcp ${frpsnew_vhostHTTPPort})" == "0" ] && iptables -D INPUT -p tcp --dport ${frpsnew_vhostHTTPPort} -j ACCEPT >/dev/null 2>&1 && t_port="${frpsnew_vhostHTTPPort}"
	[ "$(check_port tcp ${frpsnew_vhostHTTPSPort})" == "0" ] && iptables -D INPUT -p tcp --dport ${frpsnew_vhostHTTPSPort} -j ACCEPT >/dev/null 2>&1 && t_port="${t_port} ${frpsnew_vhostHTTPSPort}"
	[ "$(check_port tcp ${frpsnew_bindPort})" == "0" ] && iptables -D INPUT -p tcp --dport ${frpsnew_bindPort} -j ACCEPT >/dev/null 2>&1 && t_port="${t_port} ${frpsnew_bindPort}"
	[ "$(check_port udp ${frpsnew_vhostHTTPPort})" == "0" ] && iptables -D INPUT -p udp --dport ${frpsnew_vhostHTTPPort} -j ACCEPT >/dev/null 2>&1 && u_port="${frpsnew_vhostHTTPPort}"
	[ "$(check_port udp ${frpsnew_vhostHTTPSPort})" == "0" ] && iptables -D INPUT -p udp --dport ${frpsnew_vhostHTTPSPort} -j ACCEPT >/dev/null 2>&1 && u_port="${u_port} ${frpsnew_vhostHTTPSPort}"
	[ "$(check_port udp ${frpsnew_bindPort})" == "0" ] && iptables -D INPUT -p udp --dport ${frpsnew_bindPort} -j ACCEPT >/dev/null 2>&1 && u_port="${u_port} ${frpsnew_bindPort}"
	[ -n "${t_port}" ] && echo_date "关闭TCP端口：${t_port}"
	[ -n "${u_port}" ] && echo_date "关闭UDP端口：${u_port}"
}
close_in_five() {
	echo_date "插件将在5秒后自动关闭！！"
	local i=5
	while [ $i -ge 0 ]; do
		sleep 1
		echo_date $i
		let i--
	done
	dbus set ss_basic_enable="0"
	disable_ss >/dev/null
	echo_date "插件已关闭！！"
	unset_lock
	exit
}
stop() {
	# 关闭frps进程
	if [ -n "$(pidof frpsnew)" ];then
		echo_date "停止frps主进程，pid：$(pidof frpsnew)"
		killall frpsnew >/dev/null 2>&1
	fi

	if [ -n "$(cru l|grep frpsnew_monitor)" ];then
		echo_date "删除定时任务..."
		cru d frpsnew_monitor >/dev/null 2>&1
	fi

	if [ -L "/koolshare/init.d/N95Frps.sh" ];then
		echo_date "删除nat触发..."
   		rm -rf /koolshare/init.d/N95Frps.sh >/dev/null 2>&1
   	fi

    close_port
}

case $1 in
start)
	set_lock
	if [ "${frpsnew_enable}" == "1" ]; then
		logger "[软件中心]: 启动frps！"
		onstart
	fi
	unset_lock
	;;
restart)
	set_lock
	if [ "${frpsnew_enable}" == "1" ]; then
		stop
		onstart
	fi
	unset_lock
	;;
stop)
	set_lock
	stop
	unset_lock
	;;
start_nat)
	set_lock
	if [ "${frpsnew_enable}" == "1" ]; then
		onstart
	fi
	unset_lock
	;;
esac

case $2 in
web_submit)
	set_lock
	http_response "$1"
	if [ "${frpsnew_enable}" == "1" ]; then
		stop | tee -a $LOG_FILE
		onstart | tee -a $LOG_FILE
	else
		stop | tee -a $LOG_FILE
	fi
	echo XU6J03M6 | tee -a $LOG_FILE
	unset_lock
	;;
esac
