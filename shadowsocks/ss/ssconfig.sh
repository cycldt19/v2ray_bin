#!/bin/sh

# shadowsocks script for AM380 merlin firmware
# by sadog (sadoneli@gmail.com) from koolshare.cn

eval `dbus export ss`
source /koolshare/scripts/base.sh
source helper.sh
# Variable definitions
alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y年%m月%d日\ %X)】:'
dbus set ss_basic_version_local=`cat /koolshare/ss/version`
LOG_FILE=/tmp/syslog.log
CONFIG_FILE=/koolshare/ss/ss.json
V2RAY_CONFIG_FILE_TMP="/tmp/v2ray_tmp.json"
V2RAY_CONFIG_FILE="/koolshare/ss/v2ray.json"
TROJANGO_CONFIG_FILE="/koolshare/ss/trojango.json"
TROJANGO2_CONFIG_FILE="/koolshare/ss/trojango2.json"
LOCK_FILE=/var/lock/koolss.lock
DNSF_PORT=7913
DNSC_PORT=53
ISP_DNS1=$(nvram get wan0_dns|sed 's/ /\n/g'|grep -v 0.0.0.0|grep -v 127.0.0.1|sed -n 1p)
ISP_DNS2=$(nvram get wan0_dns|sed 's/ /\n/g'|grep -v 0.0.0.0|grep -v 127.0.0.1|sed -n 2p)
IFIP_DNS1=`echo $ISP_DNS1|grep -E "([0-9]{1,3}[\.]){3}[0-9]{1,3}|:"`
IFIP_DNS2=`echo $ISP_DNS2|grep -E "([0-9]{1,3}[\.]){3}[0-9]{1,3}|:"`
gfw_on=`dbus list ss_acl_mode_|cut -d "=" -f 2 | grep -E "1"`
chn_on=`dbus list ss_acl_mode_|cut -d "=" -f 2 | grep -E "2|3|4"`
all_on=`dbus list ss_acl_mode_|cut -d "=" -f 2 | grep -E "5"`
lan_ipaddr=$(nvram get lan_ipaddr)
ip_prefix_hex=`nvram get lan_ipaddr | awk -F "." '{printf ("0x%02x", $1)} {printf ("%02x", $2)} {printf ("%02x", $3)} {printf ("00/0xffffff00\n")}'`
[ "$ss_basic_mode" == "4" ] && ss_basic_mode=3
game_on=`dbus list ss_acl_mode|cut -d "=" -f 2 | grep 3`
[ -n "$game_on" ] || [ "$ss_basic_mode" == "3" ] && mangle=1
ss_basic_password=`echo $ss_basic_password|base64_decode`
ARG_V2RAY_PLUGIN=""

# 兼容3.8.9及其以下
[ -z "$ss_basic_type" ] && {
	if [ -n "$ss_basic_rss_protocol" ];then
		ss_basic_type="1"
	else
		if [ -n "$ss_basic_koolgame_udp" ];then
			ss_basic_type="2"
		else
			if [ -n "$ss_basic_v2ray_use_json" ];then
				ss_basic_type="3"
			else
				ss_basic_type="0"
			fi
		fi
	fi
}

get_lan_cidr(){
	netmask=`nvram get lan_netmask`
	local x=${netmask##*255.}
	set -- 0^^^128^192^224^240^248^252^254^ $(( (${#netmask} - ${#x})*2 )) ${x%%.*}
	x=${1%%$3*}
	suffix=$(( $2 + (${#x}/4) ))
	#prefix=`nvram get lan_ipaddr | cut -d "." -f1,2,3`
	echo $lan_ipaddr/$suffix
}

get_wan0_cidr(){
	netmask=`nvram get wan0_netmask`
	local x=${netmask##*255.}
	set -- 0^^^128^192^224^240^248^252^254^ $(( (${#netmask} - ${#x})*2 )) ${x%%.*}
	x=${1%%$3*}
	suffix=$(( $2 + (${#x}/4) ))
	prefix=`nvram get wan0_ipaddr`
	if [ -n "$prefix" -a -n "$netmask" ];then
		echo $prefix/$suffix
	else
		echo ""
	fi
}

get_server_resolver(){
	if [ "$ss_basic_server_resolver" == "1" ];then
		if [ -n "$IFIP_DNS1" ];then
			RESOLVER="$ISP_DNS1"
		else
			RESOLVER="114.114.114.114"
		fi
	fi
	[ "$ss_basic_server_resolver" == "2" ] && RESOLVER="223.5.5.5"
	[ "$ss_basic_server_resolver" == "3" ] && RESOLVER="223.6.6.6"
	[ "$ss_basic_server_resolver" == "4" ] && RESOLVER="114.114.114.114"
	[ "$ss_basic_server_resolver" == "5" ] && RESOLVER="114.114.115.115"
	[ "$ss_basic_server_resolver" == "6" ] && RESOLVER="1.2.4.8"
	[ "$ss_basic_server_resolver" == "7" ] && RESOLVER="210.2.4.8"
	[ "$ss_basic_server_resolver" == "8" ] && RESOLVER="117.50.11.11"
	[ "$ss_basic_server_resolver" == "9" ] && RESOLVER="117.50.22.22"
	[ "$ss_basic_server_resolver" == "10" ] && RESOLVER="180.76.76.76"
	[ "$ss_basic_server_resolver" == "11" ] && RESOLVER="119.29.29.29"
	[ "$ss_basic_server_resolver" == "13" ] && RESOLVER="8.8.8.8"
	[ "$ss_basic_server_resolver" == "12" ] && {
		[ -n "$ss_basic_server_resolver_user" ] && RESOLVER="$ss_basic_server_resolver_user" || RESOLVER="114.114.114.114"
	}
	echo $RESOLVER
}

set_lock(){
	exec 1000>"$LOCK_FILE"
	flock -x 1000
}

unset_lock(){
	flock -u 1000
	rm -rf "$LOCK_FILE"
}

close_in_five(){
	echo_date "插件将在5秒后自动关闭！！"
	sleep 1
	echo_date 5
	sleep 1
	echo_date 4
	sleep 1
	echo_date 3
	sleep 1
	echo_date 2
	sleep 1
	echo_date 1
	sleep 1
	echo_date 0
	dbus set ss_basic_enable="0"
	disable_ss >/dev/null
	echo_date "插件已关闭！！"
	echo_date ======================= 梅林固件 - 【科学上网】 ========================
	unset_lock
	exit
}

# ================================= ss stop ===============================
restore_conf(){
	echo_date 删除ss相关的名单配置文件.
	rm -rf /jffs/configs/dnsmasq.d/gfwlist.conf
	rm -rf /jffs/configs/dnsmasq.d/cdn.conf
	rm -rf /jffs/configs/dnsmasq.d/custom.conf
	rm -rf /jffs/configs/dnsmasq.d/wblist.conf
	rm -rf /jffs/configs/dnsmasq.d/ss_host.conf
	rm -rf /jffs/configs/dnsmasq.d/ss_server.conf
	rm -rf /jffs/configs/dnsmasq.conf.add
	rm -rf /jffs/scripts/dnsmasq.postconf
	rm -rf /tmp/sscdn.conf
	rm -rf /tmp/custom.conf
	rm -rf /tmp/wblist.conf
	rm -rf /tmp/ss_host.conf
	rm -rf /tmp/smartdns.conf
}

kill_process(){
	v2ray_process=`pidof v2ray`
	if [ -n "$v2ray_process" ];then 
		echo_date 关闭V2Ray进程...
		# 有时候killall杀不了v2ray进程，所以用不同方式杀两次
		killall v2ray >/dev/null 2>&1
		kill -9 "$v2ray_process" >/dev/null 2>&1
	fi
	xray_process=`pidof xray`
	if [ -n "$xray_process" ];then 
		echo_date 关闭XRay进程...
		# 有时候killall杀不了Xray进程，所以用不同方式杀两次
		killall xray >/dev/null 2>&1
		kill -9 "$xray_process" >/dev/null 2>&1
	fi
	trojango_process=`pidof trojan-go`
	if [ -n "$trojango_process" ];then 
		echo_date 关闭Trojan-Go进程...
		# 有时候killall杀不了Trojan-Go进程，所以用不同方式杀两次
		killall trojan-go >/dev/null 2>&1
		kill -9 "$trojango_process" >/dev/null 2>&1
	fi

	ssredir=`pidof ss-redir`
	if [ -n "$ssredir" ];then 
		echo_date 关闭ss-redir进程...
		killall ss-redir >/dev/null 2>&1
	fi

	rssredir=`pidof rss-redir`
	if [ -n "$rssredir" ];then 
		echo_date 关闭ssr-redir进程...
		killall rss-redir >/dev/null 2>&1
	fi
	sslocal=`ps | grep -w ss-local | grep -v "grep" | grep -w "23456" | awk '{print $1}'`
	if [ -n "$sslocal" ];then 
		echo_date 关闭ss-local进程:23456端口...
		kill $sslocal  >/dev/null 2>&1
	fi

	ssrlocal=`ps | grep -w rss-local | grep -v "grep" | grep -w "23456" | awk '{print $1}'`
	if [ -n "$ssrlocal" ];then 
		echo_date 关闭ssr-local进程:23456端口...
		kill $ssrlocal  >/dev/null 2>&1
	fi
	sstunnel=`pidof ss-tunnel`
	if [ -n "$sstunnel" ];then 
		echo_date 关闭ss-tunnel进程...
		killall ss-tunnel >/dev/null 2>&1
	fi
	rsstunnel=`pidof rss-tunnel`
	if [ -n "$rsstunnel" ];then 
		echo_date 关闭rss-tunnel进程...
		killall rss-tunnel >/dev/null 2>&1
	fi
	chinadns_process=`pidof chinadns`
	if [ -n "$chinadns_process" ];then 
		echo_date 关闭chinadns2进程...
		killall chinadns >/dev/null 2>&1
	fi
	chinadns1_process=`pidof chinadns1`
	if [ -n "$chinadns1_process" ];then 
		echo_date 关闭chinadns1进程...
		killall chinadns1 >/dev/null 2>&1
	fi
	cdns_process=`pidof cdns`
	if [ -n "$cdns_process" ];then 
		echo_date 关闭cdns进程...
		killall cdns >/dev/null 2>&1
	fi
	dns2socks_process=`pidof dns2socks`
	if [ -n "$dns2socks_process" ];then 
		echo_date 关闭dns2socks进程...
		killall dns2socks >/dev/null 2>&1
	fi
	smartdns_process=$(pidof smartdns)
	if [ -n "$smartdns_process" ]; then
		echo_date 关闭smartdns进程...
		killall smartdns >/dev/null 2>&1
	fi
	koolgame_process=`pidof koolgame`
	if [ -n "$koolgame_process" ];then 
		echo_date 关闭koolgame进程...
		killall koolgame >/dev/null 2>&1
	fi
	pdu_process=`pidof pdu`
	if [ -n "$pdu_process" ];then 
		echo_date 关闭pdu进程...
		kill -9 $pdu >/dev/null 2>&1
	fi
	client_linux_arm5_process=`pidof client_linux_arm5`
	if [ -n "$client_linux_arm5_process" ];then 
		echo_date 关闭kcp协议进程...
		killall client_linux_arm5 >/dev/null 2>&1
	fi
	haproxy_process=`pidof haproxy`
	if [ -n "$haproxy_process" ];then 
		echo_date 关闭haproxy进程...
		killall haproxy >/dev/null 2>&1
	fi
	speederv1_process=`pidof speederv1`
	if [ -n "$speederv1_process" ];then 
		echo_date 关闭speederv1进程...
		killall speederv1 >/dev/null 2>&1
	fi
	speederv2_process=`pidof speederv2`
	if [ -n "$speederv2_process" ];then 
		echo_date 关闭speederv2进程...
		killall speederv2 >/dev/null 2>&1
	fi
	ud2raw_process=`pidof udp2raw`
	if [ -n "$ud2raw_process" ];then 
		echo_date 关闭ud2raw进程...
		killall udp2raw >/dev/null 2>&1
	fi
	https_dns_proxy_process=`pidof https_dns_proxy`
	if [ -n "$https_dns_proxy_process" ];then 
		echo_date 关闭https_dns_proxy进程...
		killall https_dns_proxy >/dev/null 2>&1
	fi
	haveged_process=`pidof haveged`
	if [ -n "$haveged_process" ];then 
		echo_date 关闭haveged进程...
		killall haveged >/dev/null 2>&1
	fi
	plugin_process=`pidof v2ray-plugin`
	if [ -n "$plugin_process" ];then 
		echo_date 关闭v2ray-plugin进程...
		killall v2ray-plugin >/dev/null 2>&1
	fi
}

# ================================= ss prestart ===========================
ss_pre_start(){
	lb_enable=`dbus get ss_lb_enable`
	if [ "$lb_enable" == "1" ];then
		echo_date ---------------------- 【科学上网】 启动前触发脚本 ----------------------
		if [ `dbus get ss_basic_server | grep -o "127.0.0.1"` ] && [ `dbus get ss_basic_port` == `dbus get ss_lb_port` ];then
			echo_date ss启动前触发:触发启动负载均衡功能！
			#start haproxy
			sh /koolshare/scripts/ss_lb_config.sh
		else
			echo_date ss启动前触发:未选择负载均衡节点，不触发负载均衡启动！
		fi
	else
		if [ `dbus get ss_basic_server | grep -o "127.0.0.1"` ] && [ `dbus get ss_basic_port` == `dbus get ss_lb_port` ];then
			echo_date ss启动前触发【警告】：你选择了负载均衡节点，但是负载均衡开关未启用！！
		#else
			#echo_date ss启动前触发：你选择了普通节点，不触发负载均衡启动！
		fi
	fi
}
# ================================= ss start ==============================

resolv_server_ip(){
	if [ "$ss_basic_type" == "3" ] && [ "$ss_basic_v2ray_use_json" == "1" ];then
		#echo_date "你使用的v2ray json配置，请自行将v2ray服务器ip地址添加到IP/CIDR白名单！"
		return 1
	else
		IFIP=`echo $ss_basic_server|grep -E "([0-9]{1,3}[\.]){3}[0-9]{1,3}|:"`
		if [ -z "$IFIP" ];then
			# 服务器地址强制由114解析，以免插件还未开始工作而导致解析失败
			echo "server=/$ss_basic_server/$(get_server_resolver)#53" > /jffs/configs/dnsmasq.d/ss_server.conf
			echo_date 尝试解析节点服务器的ip地址，DNS：$(get_server_resolver)
			server_ip=`nslookup "$ss_basic_server" $(get_server_resolver) | sed '1,4d' | awk '{print $3}' | grep -v :|awk 'NR==1{print}'`
			if [ "$?" == "0" ];then
				server_ip=`echo $server_ip|grep -E "([0-9]{1,3}[\.]){3}[0-9]{1,3}|:"`
			else
				echo_date 节点服务器域名解析失败！
				echo_date 尝试用resolveip方式解析，DNS：系统
				server_ip=`resolveip -4 -t 2 $ss_basic_server|awk 'NR==1{print}'`
				if [ "$?" == "0" ];then
			    	server_ip=`echo $server_ip|grep -E "([0-9]{1,3}[\.]){3}[0-9]{1,3}|:"`
				fi
			fi

			if [ -n "$server_ip" ];then
				echo_date 节点服务器的ip地址解析成功：$server_ip
				# 解析并记录一次ip，方便插件触发重启设定工作
				echo "address=/$ss_basic_server/$server_ip" > /tmp/ss_host.conf
				# 去掉此功能，以免ip发生变更导致问题，或者影响域名对应的其它二级域名
				#ln -sf /tmp/ss_host.conf /jffs/configs/dnsmasq.d/ss_host.conf
				ss_basic_server="$server_ip"
				ss_basic_server_ip="$server_ip"
				dbus set ss_basic_server_ip="$server_ip"
			else
				dbus remvoe ss_basic_server_ip
				echo_date 节点服务器的ip地址解析失败，将由ss-redir自己解析.
			fi
		else
			ss_basic_server_ip="$ss_basic_server"
			dbus set ss_basic_server_ip=$ss_basic_server
			echo_date 检测到你的节点服务器已经是IP格式：$ss_basic_server,跳过解析... 
		fi
	fi
}

ss_arg(){
	# v2ray-plugin
	if [ -n "$ss_basic_ss_v2ray_plugin_opts" ];then
		if [ "$ss_basic_ss_v2ray_plugin" == "1" ];then
			ARG_V2RAY_PLUGIN="--plugin v2ray-plugin --plugin-opts $ss_basic_ss_v2ray_plugin_opts"
		else
			ARG_V2RAY_PLUGIN=""
		fi
	fi
}
# create shadowsocks config file...
create_ss_json(){
	if [ "$ss_basic_type" == "0" ];then
		echo_date 创建SS配置文件到$CONFIG_FILE
		cat > $CONFIG_FILE <<-EOF
			{
			    "server":"$ss_basic_server",
			    "server_port":$ss_basic_port,
			    "local_address":"0.0.0.0",
			    "local_port":3333,
			    "password":"$ss_basic_password",
			    "timeout":600,
			    "method":"$ss_basic_method"
			}
		EOF
	elif [ "$ss_basic_type" == "1" ];then
		echo_date 创建SSR配置文件到$CONFIG_FILE
		cat > $CONFIG_FILE <<-EOF
			{
			    "server":"$ss_basic_server",
			    "server_port":$ss_basic_port,
			    "local_address":"0.0.0.0",
			    "local_port":3333,
			    "password":"$ss_basic_password",
			    "timeout":600,
			    "protocol":"$ss_basic_rss_protocol",
			    "protocol_param":"$ss_basic_rss_protocol_param",
			    "obfs":"$ss_basic_rss_obfs",
			    "obfs_param":"$ss_basic_rss_obfs_param",
			    "method":"$ss_basic_method"
			}
		EOF
	elif [ "$ss_basic_type" == "2" ];then
		echo_date 创建koolgame配置文件到$CONFIG_FILE
		cat > $CONFIG_FILE <<-EOF
			{
			    "server":"$ss_basic_server",
			    "server_port":$ss_basic_port,
			    "local_port":3333,
			    "sock5_port":23456,
			    "dns2ss":7913,
			    "adblock_addr":"",
			    "dns_server":"$ss_dns2ss_user",
			    "password":"$ss_basic_password",
			    "timeout":600,
			    "method":"$ss_basic_method",
			    "use_tcp":$ss_basic_koolgame_udp
			}
		EOF
	fi
	
	if [ "$ss_basic_udp2raw_boost_enable" == "1" ] || [ "$ss_basic_udp_boost_enable" == "1" ];then
		if [ "$ss_basic_udp_upstream_mtu" == "1" ] && [ "$ss_basic_udp_node" == "$ssconf_basic_node" ];then
			echo_date 设定MTU为 $ss_basic_udp_upstream_mtu_value
			cat /koolshare/ss/ss.json | jq --argjson MTU $ss_basic_udp_upstream_mtu_value '. + {MTU: $MTU}' > /koolshare/ss/ss_tmp.json
			mv /koolshare/ss/ss_tmp.json /koolshare/ss/ss.json
		fi
	fi
}

get_type_name() {
	case "$1" in
		0)
			echo "shadowsocks-libev"
		;;
		1)
			echo "shadowsocksR-libev"
		;;
		2)
			echo "koolgame"
		;;
		3)
			echo "v2ray"
		;;
	esac
}

get_dns_name() {
	case "$1" in
		1)
			echo "cdns"
		;;
		2)
			echo "chinadns2"
		;;
		3)
			echo "dns2socks"
		;;
		4)
			if [ -n "$ss_basic_rss_obfs" ];then
				echo "ssr-tunnel"
			else
				echo "ss-tunnel"
			fi
		;;
		5)
			echo "chinadns1"
		;;
		6)
			echo "https_dns_proxy"
		;;
		7)
			echo "v2ray dns"
		;;
		8)
			echo "koolgame内置"
		;;
		9)
		echo "SmartDNS"
		;;
	esac
}

start_sslocal(){
	if [ "$ss_basic_type" == "1" ];then
		echo_date 开启ssr-local，提供socks5代理端口：23456
		rss-local -l 23456 -c $CONFIG_FILE -u -f /var/run/sslocal1.pid >/dev/null 2>&1
	elif  [ "$ss_basic_type" == "0" ];then
		echo_date 开启ss-local，提供socks5代理端口：23456
		if [ "$ss_basic_ss_v2ray_plugin" == "0" ];then
			ss-local -l 23456 -c $CONFIG_FILE -u -f /var/run/sslocal1.pid >/dev/null 2>&1
		else
			ss-local -l 23456 -c $CONFIG_FILE $ARG_V2RAY_PLUGIN -u -f /var/run/sslocal1.pid >/dev/null 2>&1
		fi
	elif [ "$ss_basic_type" == "4" ] && [ "$ss_basic_trojan_binary" == "Trojan-Go" ]; then
		echo_date 开启trojan-go，提供socks5代理端口：23456 
		trojan-go -config $TROJANGO2_CONFIG_FILE >/dev/null 2>&1 &	
	fi
}

start_dns(){
	if [ "$ss_basic_mode" == "6" -a "$ss_foreign_dns" != "8" ];then
		ss_foreign_dns="8"
		dbus set ss_foreign_dns="8"
	fi
	
	# Start ss-local
	# [ "$ss_basic_type" != "3" ] && start_sslocal
	
	# Start cdns
	if [ "$ss_foreign_dns" == "1" ];then
		echo_date 开启cdns，用于dns解析...
		cdns -c /koolshare/ss/rules/cdns.json > /dev/null 2>&1 &
	fi

	# Start chinadns2
	if [ "$ss_foreign_dns" == "2" ];then
		echo_date 开启chinadns2，用于dns解析...
		clinet_ip="114.114.114.114"
		public_ip=`nvram get wan0_realip_ip`
		if [ -z "$public_ip" ];then
			# 路由公网ip为空则获取
			public_ip=`curl --connect-timeout 1 --retry 0 --max-time 1 -s 'http://members.3322.org/dyndns/getip'`
			if [ "$?" == "0" ] && [ -n "$public_ip" ];then
				# 获取成功
				echo_date 你的公网ip地址是：$public_ip
				dbus set ss_basic_publicip="$public_ip"
				clinet_ip="$public_ip"
			else
				# 获取失败，则自动为114
				[ -n "$ss_basic_publicip" ] && clinet_ip="$ss_basic_publicip"
			fi
		else
			# 获取失败，则自动为114
			clinet_ip="$public_ip"
		fi

		if [ -n "$ss_basic_server_ip" ];then
			# 用chnroute去判断SS服务器在国内还是在国外
			ipset test chnroute $ss_basic_server_ip > /dev/null 2>&1
			if [ "$?" != "0" ];then
				# ss服务器是国外IP
				ss_real_server_ip="$ss_basic_server_ip"
			else
				# ss服务器是国内ip （可能用了国内中转，那么用谷歌dns ip地址去作为国外edns标签）
				ss_real_server_ip="8.8.8.8"
			fi
		else
			# ss服务器可能是域名且没有正确解析
			ss_real_server_ip="8.8.8.8"
		fi
		chinadns -p $DNSF_PORT -s $ss_chinadns_user -e $clinet_ip,$ss_real_server_ip -c /koolshare/ss/rules/chnroute.txt >/dev/null 2>&1 &
	fi
	
	# Start DNS2SOCKS (default)
	if [ "$ss_foreign_dns" == "3" ] || [ -z "$ss_foreign_dns" ];then
		[ -z "$ss_foreign_dns" ] && dbus set ss_foreign_dns="3"
		start_sslocal
		echo_date 开启dns2socks，用于dns解析...
		dns2socks 127.0.0.1:23456 "$ss_dns2socks_user" 127.0.0.1:$DNSF_PORT > /dev/null 2>&1 &
	fi
	
	# Start ss-tunnel
	if [ "$ss_foreign_dns" == "4" ];then
		if [ "$ss_basic_type" == "1" ];then
			echo_date 开启ssr-tunnel，用于dns解析...
			rss-tunnel -c $CONFIG_FILE -l $DNSF_PORT -L $ss_sstunnel_user -u -f /var/run/sstunnel.pid >/dev/null 2>&1
		elif [ "$ss_basic_type" == "0" ];then
			echo_date 开启ss-tunnel，用于dns解析...
			if [ "$ss_basic_ss_v2ray_plugin" == "0" ];then
				ss-tunnel -c $CONFIG_FILE -l $DNSF_PORT -L $ss_sstunnel_user -u -f /var/run/sstunnel.pid >/dev/null 2>&1
			else
				ss-tunnel -c $CONFIG_FILE -l $DNSF_PORT -L $ss_sstunnel_user $ARG_V2RAY_PLUGIN -u -f /var/run/sstunnel.pid >/dev/null 2>&1
			fi
		elif [ "$ss_basic_type" == "3" ] || [ "$ss_basic_type" == "4" ];then
			echo_date V2Ray或Trojan 下不支持ss-tunnel，改用dns2socks！
			dbus set ss_foreign_dns=3
			start_sslocal
			echo_date 开启dns2socks，用于dns解析...
			dns2socks 127.0.0.1:23456 "$ss_dns2socks_user" 127.0.0.1:$DNSF_PORT > /dev/null 2>&1 &
		fi
	fi
	
	#start chinadns1
	if [ "$ss_foreign_dns" == "5" ]; then
		# 当国内SmartDNS和国外chiandns1冲突
		if [ "$ss_dns_china" == "13" -a "$ss_foreign_dns" == "5" ]; then
			echo_date "！！中国DNS选择SmartDNS和外国DNS选择chiandns1冲突，将外国DNS默认改为dns2socks！！"
			ss_foreign_dns="3"
			dbus set ss_foreign_dns="3"
			start_sslocal
			echo_date 开启dns2socks，用于chinadns1上游...
			dns2socks 127.0.0.1:23456 "$ss_dns2socks_user" 127.0.0.1:$DNSF_PORT >/dev/null 2>&1 &
		else
			start_sslocal
			echo_date 开启dns2socks，用于chinadns1上游...
			dns2socks 127.0.0.1:23456 "$ss_chinadns1_user" 127.0.0.1:1055 >/dev/null 2>&1 &
			echo_date 开启chinadns1，用于dns解析...
			chinadns1 -p $DNSF_PORT -s $CDN,127.0.0.1:1055 -d -c /koolshare/ss/rules/chnroute.txt >/dev/null 2>&1 &
		fi
	fi


	#start https_dns_proxy
	if [ "$ss_foreign_dns" == "6" ];then
		echo_date 开启https_dns_proxy，用于dns解析...
		if [ -n "$ss_basic_server_ip" ];then
			# 用chnroute去判断SS服务器在国内还是在国外
			ipset test chnroute $ss_basic_server_ip > /dev/null 2>&1
			if [ "$?" != "0" ];then
				# ss服务器是国外IP
				ss_real_server_ip="$ss_basic_server_ip"
			else
				# ss服务器是国内ip （可能用了国内中转，那么用谷歌dns ip地址去作为国外edns标签）
				ss_real_server_ip="8.8.8.8"
			fi
		else
			# ss服务器可能是域名且没有正确解析
			ss_real_server_ip="8.8.8.8"
		fi
		https_dns_proxy -u nobody -p 7913 -b 8.8.8.8,1.1.1.1,8.8.4.4,1.0.0.1,145.100.185.15,145.100.185.16,185.49.141.37 -e $ss_real_server_ip/16 -r "https://cloudflare-dns.com/dns-query?ct=application/dns-json&" -d
	fi
	
	# start v2ray DNSF_PORT
	if [ "$ss_foreign_dns" == "7" ];then
		if [ "$ss_basic_type" == "3" ];then
			return 0
		else
			echo_date $(get_type_name $ss_basic_type)下不支持v2ray dns，改用dns2socks！
			dbus set ss_foreign_dns=3
			start_sslocal
			echo_date 开启dns2socks，用于dns解析...
			dns2socks 127.0.0.1:23456 "$ss_dns2socks_user" 127.0.0.1:$DNSF_PORT > /dev/null 2>&1 &
		fi
	fi

# 开启SmartDNS
	if [ "$ss_dns_china" == "13" ] && [ "$ss_foreign_dns" == "9" ]; then
		# 国内国外都启用SmartDNS （此情况下，如果是gfwlist模式则不用cdn.conf；如果是大陆白名单模式也不需要使用cdn.conf）

		echo_date "开启SmartDNS，用于DNS解析..."
		#if [ "$(nvram get ipv6_service)" == "disabled" ]; then
		#	sed 's/# force-AAAA-SOA yes/force-AAAA-SOA yes/g' /koolshare/ss/rules/smartdns_template.conf > /tmp/smartdns.conf
		#	sed -i '/^#/d /^$/d' /tmp/smartdns.conf
		#else
			sed '/^#/d /^$/d' /koolshare/ss/rules/smartdns_template.conf > /tmp/smartdns.conf
		#fi
		smartdns -c /tmp/smartdns.conf >/dev/null 2>&1 &
		start_sslocal
	elif [ "$ss_dns_china" == "13" ] && [ "$ss_foreign_dns" != "9" ]; then
		# 国内启用SmartDNS，国外不启用SmartDNS （此情况下，如果是gfwlist模式则不用cdn.conf；如果是大陆白名单模式则是根据国外DNS的选择而决定是否使用cdn.conf）
		echo_date "开启SmartDNS，用于DNS解析..."
		#if [ "$(nvram get ipv6_service)" == "disabled" ]; then
		#	sed 's/# force-AAAA-SOA yes/force-AAAA-SOA yes/g' /koolshare/ss/rules/smartdns_template.conf > /tmp/smartdns.conf
		#	sed -i '/^#/d /^$/d /foreign/d' /tmp/smartdns.conf
		#else
			sed '/^#/d /^$/d /foreign/d' /koolshare/ss/rules/smartdns_template.conf > /tmp/smartdns.conf
		#fi
		smartdns -c /tmp/smartdns.conf >/dev/null 2>&1 &
	elif [ "$ss_dns_china" != "13" ] && [ "$ss_foreign_dns" == "9" ]; then
		# 国内不启用SmartDNS，国外启用SmartDNS （此情况下，如果是gfwlist模式则不用cdn.conf；如果是大陆白名单模式则需要使用cdn.conf）
		echo_date "开启SmartDNS，用于DNS解析..."
		#if [ "$(nvram get ipv6_service)" == "disabled" ]; then
		#	sed 's/# force-AAAA-SOA yes/force-AAAA-SOA yes/g' /koolshare/ss/rules/smartdns_template.conf > /tmp/smartdns.conf
		#	sed -i '/^#/d /^$/d /china/d' /tmp/smartdns.conf
		#else
			sed '/^#/d /^$/d /china/d' /koolshare/ss/rules/smartdns_template.conf > /tmp/smartdns.conf
		#fi
		smartdns -c /tmp/smartdns.conf >/dev/null 2>&1 &
		start_sslocal
	fi

	# direct
	if [ "$ss_foreign_dns" == "8" ];then
		if [ "$ss_basic_mode" == "6" ];then
			echo_date 回国模式，国外dns采用直连方案。
		else
			echo_date 非回国模式，国外dns不能使用，自动切换到dns2socks方案。
			dbus set ss_foreign_dns=3
			start_sslocal
			echo_date 开启dns2socks，用于dns解析...
			dns2socks 127.0.0.1:23456 "$ss_dns2socks_user" 127.0.0.1:$DNSF_PORT > /dev/null 2>&1 &
		fi
	fi
	
}
#--------------------------------------------------------------------------------------

detect_domain(){
	domain1=`echo $1|grep -E "^https://|^http://|www|/"`
	domain2=`echo $1|grep -E "\."`
	if [ -n "$domain1" ] || [ -z "$domain2" ];then
		return 1
	else
		return 0
	fi
}

create_dnsmasq_conf(){
	if [ "$ss_dns_china" == "1" ];then
		if [ "$ss_basic_mode" == "6" ];then
			# 使用回国模式的时候，ISP dns是国外的，所以这里直接用114取代
			CDN="114.114.114.114"
		else
			if [ -n "$IFIP_DNS1" ];then
				# 用chnroute去判断运营商DNS是否为局域网(国外)ip地址，有些二级路由的是局域网ip地址，会被ChinaDNS 判断为国外dns服务器，这个时候用114取代之
				ipset test chnroute $IFIP_DNS1 > /dev/null 2>&1
				if [ "$?" != "0" ];then
					# 运营商DNS：ISP_DNS1是局域网(国外)ip
					CDN="114.114.114.114"
				else
					# 运营商DNS：ISP_DNS1是国内ip
					CDN="$ISP_DNS1"
				fi
			else
				# 运营商DNS：ISP_DNS1不是ip格式，用114取代之
				CDN="114.114.114.114"
			fi
		fi
	fi
	[ "$ss_dns_china" == "2" ] && CDN="223.5.5.5"
	[ "$ss_dns_china" == "3" ] && CDN="223.6.6.6"
	[ "$ss_dns_china" == "4" ] && CDN="114.114.114.114"
	[ "$ss_dns_china" == "5" ] && CDN="114.114.115.115"
	[ "$ss_dns_china" == "6" ] && CDN="1.2.4.8"
	[ "$ss_dns_china" == "7" ] && CDN="210.2.4.8"
	[ "$ss_dns_china" == "8" ] && CDN="117.50.11.11"
	[ "$ss_dns_china" == "9" ] && CDN="117.50.22.22"
	[ "$ss_dns_china" == "10" ] && CDN="180.76.76.76"
	[ "$ss_dns_china" == "11" ] && CDN="119.29.29.29"
	[ "$ss_dns_china" == "12" ] && {
		[ -n "$ss_dns_china_user" ] && CDN="$ss_dns_china_user" || CDN="114.114.114.114"
	}
	if [ "$ss_dns_china" == "13" ];then
		CDN="127.0.0.1"
		DNSC_PORT=5335
	fi
	# delete pre settings
	rm -rf /tmp/sscdn.conf
	rm -rf /tmp/custom.conf
	rm -rf /tmp/wblist.conf
	rm -rf /tmp/gfwlist.conf
	rm -rf /jffs/configs/dnsmasq.d/custom.conf
	rm -rf /jffs/configs/dnsmasq.d/wblist.conf
	rm -rf /jffs/configs/dnsmasq.d/cdn.conf
	rm -rf /jffs/configs/dnsmasq.d/gfwlist.conf
	rm -rf /jffs/scripts/dnsmasq.postconf
	rm -rf /tmp/smartdns.conf
	
	# custom dnsmasq settings by user
	if [ -n "$ss_dnsmasq" ];then
		echo_date 添加自定义dnsmasq设置到/tmp/custom.conf
		echo "$ss_dnsmasq" | base64_decode | sort -u >> /tmp/custom.conf
	fi

	# these sites need to go ss inside router
	if [ "$ss_basic_mode" != "6" ];then
		echo "#for router itself" >> /tmp/wblist.conf
		echo "server=/.google.com.tw/127.0.0.1#7913" >> /tmp/wblist.conf
		echo "ipset=/.google.com.tw/router" >> /tmp/wblist.conf
		echo "server=/dns.google.com/127.0.0.1#7913" >> /tmp/wblist.conf
		echo "ipset=/dns.google.com/router" >> /tmp/wblist.conf
		echo "server=/.github.com/127.0.0.1#7913" >> /tmp/wblist.conf
		echo "ipset=/.github.com/router" >> /tmp/wblist.conf
		echo "server=/.github.io/127.0.0.1#7913" >> /tmp/wblist.conf
		echo "ipset=/.github.io/router" >> /tmp/wblist.conf
		echo "server=/.raw.githubusercontent.com/127.0.0.1#7913" >> /tmp/wblist.conf
		echo "ipset=/.raw.githubusercontent.com/router" >> /tmp/wblist.conf
		echo "server=/.adblockplus.org/127.0.0.1#7913" >> /tmp/wblist.conf
		echo "ipset=/.adblockplus.org/router" >> /tmp/wblist.conf
		echo "server=/.entware.net/127.0.0.1#7913" >> /tmp/wblist.conf
		echo "ipset=/.entware.net/router" >> /tmp/wblist.conf
		echo "server=/.apnic.net/127.0.0.1#7913" >> /tmp/wblist.conf
		echo "ipset=/.apnic.net/router" >> /tmp/wblist.conf
	fi
	
	# append white domain list, not through ss
	wanwhitedomain=$(echo $ss_wan_white_domain | base64_decode)
	if [ -n "$ss_wan_white_domain" ];then
		echo_date 应用域名白名单
		echo "#for white_domain" >> /tmp/wblist.conf
		for wan_white_domain in $wanwhitedomain
		do
			detect_domain "$wan_white_domain"
			if [ "$?" == "0" ];then
				# 回国模式下，用外国DNS，否则用中国DNS。
				if [ "$ss_basic_mode" != "6" ];then
					echo "$wan_white_domain" | sed "s/^/server=&\/./g" | sed "s/$/\/$CDN#53/g" >> /tmp/wblist.conf
					echo "$wan_white_domain" | sed "s/^/ipset=&\/./g" | sed "s/$/\/white_list/g" >> /tmp/wblist.conf
				else
					echo "$wan_white_domain" | sed "s/^/server=&\/./g" | sed "s/$/\/$ss_direct_user/g" >> /tmp/wblist.conf
					echo "$wan_white_domain" | sed "s/^/ipset=&\/./g" | sed "s/$/\/white_list/g" >> /tmp/wblist.conf
				fi
			else
				echo_date ！！检测到域名白名单内的【"$wan_white_domain"】不是域名格式！！此条将不会添加！！
			fi
		done
	fi
	
	# 非回国模式下，apple 和 microsoft需要中国cdn
	if [ "$ss_basic_mode" != "6" ]; then
		echo "#for special site (Mandatory China DNS)" >>/tmp/wblist.conf
		for wan_white_domain2 in "apple.com" "microsoft.com" "dns.msftncsi.com"; do
			echo "$wan_white_domain2" | sed "s/^/server=&\/./g" | sed "s/$/\/$CDN#$DNSC_PORT/g" >>/tmp/wblist.conf
			echo "$wan_white_domain2" | sed "s/^/ipset=&\/./g" | sed "s/$/\/white_list/g" >>/tmp/wblist.conf
		done
	fi

	# append black domain list, through ss
	wanblackdomain=$(echo $ss_wan_black_domain | base64_decode)
	if [ -n "$ss_wan_black_domain" ];then
		echo_date 应用域名黑名单
		echo "#for black_domain" >>/tmp/wblist.conf
		for wan_black_domain in $wanblackdomain; do
			detect_domain "$wan_black_domain"
			if [ "$?" == "0" ]; then
				if [ "$ss_basic_mode" != "6" ]; then
					echo "$wan_black_domain" | sed "s/^/server=&\/./g" | sed "s/$/\/127.0.0.1#$DNSF_PORT/g" >>/tmp/wblist.conf
					echo "$wan_black_domain" | sed "s/^/ipset=&\/./g" | sed "s/$/\/black_list/g" >>/tmp/wblist.conf
				else
					echo "$wan_black_domain" | sed "s/^/server=&\/./g" | sed "s/$/\/$CDN#$DNSC_PORT/g" >>/tmp/wblist.conf
					echo "$wan_black_domain" | sed "s/^/ipset=&\/./g" | sed "s/$/\/black_list/g" >>/tmp/wblist.conf
				fi
			else
				echo_date ！！检测到域名黑名单内的【"$wan_black_domain"】不是域名格式！！此条将不会添加！！
			fi
		done
	fi

	# 使用cdn.conf和gfwlist的策略
	# cdn.conf的作用：cdn.conf内包含了4万多条国内的网站，基本包含了普通人的所有国内上网需求，使用cdn.conf会让里面指定的网站强制走中国DNS的解析
	# gfwlist的主用：gfwlist内包含了已知的被墙网站，大部分人的翻墙需求（google, youtube, netflix, etc...），能得到满足，使用gfwlist会让里面指定的网站走国外的dns解析（墙内出去需要防污染，墙外进来直连即可）
	# 1.1 在国内优先模式下（在墙内出去），dnsmasq的全局dns是中国的，所以不需要cdn.conf，此时对路由的dnsmasq的负担也较小，但是为了保证国外被墙的网站解析无污染，使用gfwlist来解析国外被墙网站（此处需要防污染的软件来获得正确dns，如dns2socks的转发方式，chinadns的过滤方式，cdns的edns的特殊获取方式等），这样如果遇到gfwlist漏掉的，或者上普通未被墙的国外网站可能速度较慢；
	# 1.2 在国内优先模式下（在墙外回来），dnsmasq的全局dns是中国的，所以不需要cdn.conf，此时对路由的dnsmasq的负担也较小，但是为了保证国外被墙的网站解析无污染，使用gfwlist来解析国外被墙网站（因为本来身在国外，直连国外当地dns即可，如果转发，则会让这些请求在国内vps上去做，导致污染，如果使用chinadns过滤，则无需指定通过转发的），但是这样会导致很多国外网站的访问是从国内的vps发起的，导致一些国外网站的体验不好
	
	# 2.1 在国外优先的模式下（在墙内出去），dnsmasq的全局dns是国外的（此处需要使用防污染的软件来获得正确的dns），但是要保证国内的网站的解析效果，只好引入cdn.conf，此时路由的负担也会较大，这样国内的网站解析效果完全靠cdn.tx，一般来说能普通人的所有国内上网需求
	# 2.2 在国外优先的模式下（在墙外回来），dnsmasq的全局dns是国外的（此处只需要直连国外当地的dns服务器即可！），但是要保证国内的网站的解析效果，只好引入cdn.conf，此时路由的负担也会较大，这样国内的网站解析效果完全靠cdn.conf，一般来说翻墙回来都是看国内影视剧和音乐等需要，cdn.conf应该能够满足。

	# 总结
	# 国内优先模式，使用gfwlist，不用cdn.conf，国内cdn好，国外cdn差，路由器负担小
	# 国外优先模式，不用gfwlist，使用cdn.conf，国内cdn好，国外cdn好，路由器负担大（dns2socks ss-tunnel，cdns）
	# 国外优先模式，如果dns自带了国内cdn，不用gfwlist，不用cdn.conf，国内cdn好，国外cdn好，路由器负小（chinadns1 chinadns2）

	# 使用场景 
	# 1.1 gfwlist模式：该模式的特点就是只有gfwlist内的网站走代理，所以dns部分也应该是相同的策略，即国内优先模式。
	# 1.2 在gfwlist模式下，如果访问控制内有主机走chnroute模式，那么怎么办？也许这台主机希望获得更好的国外访问效果？原来ks的策略是如果检测到这种情况则切换到国外优先，并且保持gfwlist存在（因为主模式下的主机在iptables内必须匹配gfwlist的ipset）；
	# 2.1 chnroute模式：除了国内的IP不走代理，其余都应该走代理，即使是某个国外的网站未被墙，因为用户的初衷是为了获得更好的国外访问效果才使用chnroute模式，所以dns部分也应该是类似的策略，即国外优先模式：
	# 2.2 在chnroute模式下，如果访问控制内有主机走gfwlist模式，那么怎么办？这台机器应该指望着获得更好的国内访问效果？原来ks的策略是如果检测这种情况，保持国外优先不变的情况下，再引入gfwlist（因为这些gfwlist的主机在iptables内必须匹配gfwlist的ipset）；
	# 对于访问控制存在上面的情况，都是向着国外优先

	# 指定策略
	# 1 一刀切的自动方案：和原KS方案相同，不过对于回国模式需要做出修改，国外的dns不能由软件转发等，直连就行了（fix）
	# 2 用户自己选择，一刀切的方案很多情况下都会走到国外优先上去，这对路由器的负担是很大的，而多数人的上网需求国内优先就足够了，一些人需要国外访问快（代理够快的情况下），可以自行选择国外优先（todo）
	# 3 所以最终保留自动方案，增加国内优先和国外优先的选择方案（todo）

	if [ "$ss_basic_mode" == "6" ];then
		# 回国模式中，因为国外DNS无论如何都不会污染的，所以采取的策略是直连就行，默认国内优先即可
		echo_date 自动判断在回国模式中使用国内优先模式，不加载cdn.conf
	else
		if [ "$ss_basic_mode" == "1" -a -z "$chn_on" -a -z "$all_on" ] || [ "$ss_basic_mode" == "6" ];then
			# gfwlist模式的时候，且访问控制主机中不存在 大陆白名单模式 游戏模式 全局模式，则使用国内优先模式
			# 回国模式下自动判断使用国内优先
			echo_date 自动判断使用国内优先模式，不加载cdn.conf
		else
			# 其它情况，均使用国外优先模式，以下区分是否加载cdn.conf
			# if [ "$ss_foreign_dns" == "2" ] || [ "$ss_foreign_dns" == "5" ] || [ "$ss_foreign_dns" == "9" -a "$ss_dns_china" == "13" ]; then
			if [ "$ss_foreign_dns" == "2" ] || [ "$ss_foreign_dns" == "5" -a "$ss_dns_china" != "13" ] || [ "$ss_foreign_dns" == "10" ]; then
				# 因为chinadns1 chinadns2自带国内cdn，所以也不需要cdn.conf
				echo_date 自动判断dns解析使用国外优先模式...
				echo_date 国外解析方案【$(get_dns_name $ss_foreign_dns)】自带国内cdn，无需加载cdn.conf，路由器开销小...
			else
				echo_date 自动判断dns解析使用国外优先模式...
				echo_date 国外解析方案【$(get_dns_name $ss_foreign_dns)】，需要加载cdn.conf提供国内cdn...
				echo_date 建议将系统dnsmasq替换为dnsmasq-fastlookup，以减轻路由cpu消耗...
				echo_date 生成cdn加速列表到/tmp/sscdn.conf，加速用的dns：$CDN
				echo "#for china site CDN acclerate" >>/tmp/sscdn.conf
				cat /koolshare/ss/rules/cdn.txt | sed "s/^/server=&\/./g" | sed "s/$/\/&$CDN#$DNSC_PORT/g" | sort | awk '{if ($0!=line) print;line=$0}' >>/tmp/sscdn.conf
			fi
		fi
	fi

	#ln_conf
	if [ -f /tmp/custom.conf ];then
		#echo_date 创建域自定义dnsmasq配置文件软链接到/jffs/configs/dnsmasq.d/custom.conf
		ln -sf /tmp/custom.conf /jffs/configs/dnsmasq.d/custom.conf
	fi
	if [ -f /tmp/wblist.conf ];then
		#echo_date 创建域名黑/白名单软链接到/jffs/configs/dnsmasq.d/wblist.conf
		ln -sf /tmp/wblist.conf /jffs/configs/dnsmasq.d/wblist.conf
	fi
	
	if [ -f /tmp/sscdn.conf ];then
		#echo_date 创建cdn加速列表软链接/jffs/configs/dnsmasq.d/cdn.conf
		ln -sf /tmp/sscdn.conf /jffs/configs/dnsmasq.d/cdn.conf
	fi

	if [ "$ss_basic_mode" == "1" ];then
		echo_date 创建gfwlist的软连接到/jffs/etc/dnsmasq.d/文件夹.
		ln -sf /koolshare/ss/rules/gfwlist.conf /jffs/configs/dnsmasq.d/gfwlist.conf
	elif [ "$ss_basic_mode" == "2" ] || [ "$ss_basic_mode" == "3" ];then
		if [ -n "$gfw_on" ];then
			echo_date 创建gfwlist的软连接到/jffs/etc/dnsmasq.d/文件夹.
			ln -sf /koolshare/ss/rules/gfwlist.conf /jffs/configs/dnsmasq.d/gfwlist.conf
		fi
	elif [ "$ss_basic_mode" == "6" ];then
		# 回国模式下默认方案是国内优先，所以gfwlist里的网站不能由127.0.0.1#7913来解析了，应该是国外当地直连
		if [ -n "`echo $ss_direct_user|grep :`" ];then
			echo_date 国外直连dns设定格式错误，将自动更正为8.8.8.8#53.
			ss_direct_user="8.8.8.8#53"
			dbus set ss_direct_user="8.8.8.8#53"
		fi
		echo_date 创建回国模式专用gfwlist的软连接到/jffs/etc/dnsmasq.d/文件夹.
		[ -z "$ss_direct_user" ] && ss_direct_user="8.8.8.8#53"
		cat /koolshare/ss/rules/gfwlist.conf|sed "s/127.0.0.1#7913/$ss_direct_user/g" > /tmp/gfwlist.conf
		ln -sf /tmp/gfwlist.conf /jffs/configs/dnsmasq.d/gfwlist.conf
	fi

	#echo_date 创建dnsmasq.postconf软连接到/jffs/scripts/文件夹.
	[ ! -L "/jffs/scripts/dnsmasq.postconf" ] && ln -sf /koolshare/ss/rules/dnsmasq.postconf /jffs/scripts/dnsmasq.postconf
}

start_haveged(){
	echo_date "启动haveged，为系统提供更多的可用熵！"
	haveged -w 1024 >/dev/null 2>&1
}

auto_start(){
	# nat_auto_start
	mkdir -p /jffs/scripts
	# creating iptables rules to nat-start
	if [ ! -f /jffs/scripts/nat-start ]; then
	cat > /jffs/scripts/nat-start <<-EOF
		#!/bin/sh
		/usr/bin/onnatstart.sh
		
		EOF
	fi
	
	writenat=$(cat /jffs/scripts/nat-start | grep "ssconfig")
	if [ -z "$writenat" ];then
		echo_date 添加nat-start触发事件...用于ss的nat规则重启后或网络恢复后的加载...
		sed -i '2a sh /koolshare/ss/ssconfig.sh' /jffs/scripts/nat-start
		chmod +x /jffs/scripts/nat-start
	fi

	# wan_auto_start
	# Add service to auto start
	if [ ! -f /jffs/scripts/wan-start ]; then
		cat > /jffs/scripts/wan-start <<-EOF
			#!/bin/sh
			/usr/bin/onwanstart.sh
			
			EOF
	fi
	
	startss=$(cat /jffs/scripts/wan-start | grep "/koolshare/scripts/ss_config.sh")
	if [ -z "$startss" ];then
		echo_date 添加wan-start触发事件...用于ss的各种程序的开机启动...
		sed -i '2a sh /koolshare/scripts/ss_config.sh' /jffs/scripts/wan-start
	fi
	chmod +x /jffs/scripts/wan-start
}

start_kcp(){
	# Start kcp
	if [ "$ss_basic_use_kcp" == "1" ];then
		echo_date 启动KCP协议进程，为了更好的体验，建议在路由器上创建虚拟内存.
		export GOGC=30
		[ -z "$ss_basic_kcp_server" ] && ss_basic_kcp_server="$ss_basic_server"
		if [ "$ss_basic_kcp_method" == "1" ];then
			[ -n "$ss_basic_kcp_encrypt" ] && KCP_CRYPT="--crypt $ss_basic_kcp_encrypt"
			[ -n "$ss_basic_kcp_password" ] && KCP_KEY="--key $ss_basic_kcp_password" || KCP_KEY=""
			[ -n "$ss_basic_kcp_sndwnd" ] && KCP_SNDWND="--sndwnd $ss_basic_kcp_sndwnd" || KCP_SNDWND=""
			[ -n "$ss_basic_kcp_rcvwnd" ] && KCP_RNDWND="--rcvwnd $ss_basic_kcp_rcvwnd" || KCP_RNDWND=""
			[ -n "$ss_basic_kcp_mtu" ] && KCP_MTU="--mtu $ss_basic_kcp_mtu" || KCP_MTU=""
			[ -n "$ss_basic_kcp_conn" ] && KCP_CONN="--conn $ss_basic_kcp_conn" || KCP_CONN=""
			[ "$ss_basic_kcp_nocomp" == "1" ] && COMP="--nocomp" || COMP=""
			[ -n "$ss_basic_kcp_mode" ] && KCP_MODE="--mode $ss_basic_kcp_mode" || KCP_MODE=""

			start-stop-daemon -S -q -b -m \
			-p /tmp/var/kcp.pid \
			-x /koolshare/bin/client_linux_arm5 \
			-- -l 127.0.0.1:1091 \
			-r $ss_basic_kcp_server:$ss_basic_kcp_port \
			$KCP_CRYPT $KCP_KEY $KCP_SNDWND $KCP_RNDWND $KCP_MTU $KCP_CONN $COMP $KCP_MODE $ss_basic_kcp_extra
		else
			start-stop-daemon -S -q -b -m \
			-p /tmp/var/kcp.pid \
			-x /koolshare/bin/client_linux_arm5 \
			-- -l 127.0.0.1:1091 \
			-r $ss_basic_kcp_server:$ss_basic_kcp_port \
			$ss_basic_kcp_parameter
		fi
	fi
}

start_speeder(){
	#只有游戏模式下或者访问控制中有游戏模式主机，且udp加速节点和当前使用节点一致
	if [ "$ss_basic_use_kcp" == "1" ] && [ "$ss_basic_kcp_server" == "127.0.0.1" ] && [ "$ss_basic_kcp_port" == "1092" ];then
		echo_date 检测到你配置了KCP与UDPspeeder串联.
		SPEED_KCP=1
	fi
	
	if [ "$ss_basic_use_kcp" == "1" ] && [ "$ss_basic_kcp_server" == "127.0.0.1" ] && [ "$ss_basic_kcp_port" == "1093" ];then
		echo_date 检测到你配置了KCP与UDP2raw串联.
		SPEED_KCP=2
	fi
		
	if [ "$mangle" == "1" ] && [ "$ss_basic_udp_node" == "$ssconf_basic_node" ] || [ "$SPEED_KCP" == "1" ] || [ "$SPEED_KCP" == "2" ];then
		#开启udpspeeder
		if [ "$ss_basic_udp_boost_enable" == "1" ];then
			if [ "$ss_basic_udp_software" == "1" ];then
				echo_date 开启UDPspeederV1进程.
				[ -n "$ss_basic_udpv1_duplicate_time" ] && duplicate_time="-t $ss_basic_udpv1_duplicate_time" || duplicate_time=""
				[ -n "$ss_basic_udpv1_jitter" ] && jitter="-j $ss_basic_udpv1_jitter" || jitter=""
				[ -n "$ss_basic_udpv1_report" ] && report="--report $ss_basic_udpv1_report" || report=""
				[ -n "$ss_basic_udpv1_drop" ] && drop="--random-drop $ss_basic_udpv1_drop" || drop=""
				[ -n "$ss_basic_udpv1_duplicate_nu" ] && duplicate="-d $ss_basic_udpv1_duplicate_nu" || duplicate=""
				[ -n "$ss_basic_udpv1_password" ] && key1="-k $ss_basic_udpv1_password" || key1=""
				[ "$ss_basic_udpv1_disable_filter" == "1" ] && filter="--disable-filter" || filter=""

				if [ "$ss_basic_udp2raw_boost_enable" == "1" ];then
					#串联：如果两者都开启了，则把udpspeeder的流udp量转发给udp2raw
					speederv1 -c -l 0.0.0.0:1092 -r 127.0.0.1:1093 $key1 $ss_basic_udpv1_password \
					$duplicate_time $jitter $report $drop $filter $duplicate $ss_basic_udpv1_duplicate_nu >/dev/null 2>&1 &
					#如果只开启了udpspeeder，则把udpspeeder的流udp量转发给服务器
				else
					speederv1 -c -l 0.0.0.0:1092 -r $ss_basic_udpv1_rserver:$ss_basic_udpv1_rport $key1 \
					$duplicate_time $jitter $report $drop $filter $duplicate $ss_basic_udpv1_duplicate_nu >/dev/null 2>&1 &
				fi
			elif [ "$ss_basic_udp_software" == "2" ];then
				echo_date 开启UDPspeederV2进程.
				[ "$ss_basic_udpv2_disableobscure" == "1" ] && disable_obscure="--disable-obscure" || disable_obscure=""
				[ "$ss_basic_udpv2_disablechecksum" == "1" ] && disable_checksum="--disable-checksum" || disable_checksum=""
				[ -n "$ss_basic_udpv2_timeout" ] && timeout="--timeout $ss_basic_udpv2_timeout" || timeout=""
				[ -n "$ss_basic_udpv2_mode" ] && mode="--mode $ss_basic_udpv2_mode" || mode=""
				[ -n "$ss_basic_udpv2_report" ] && report="--report $ss_basic_udpv2_report" || report=""
				[ -n "$ss_basic_udpv2_mtu" ] && mtu="--mtu $ss_basic_udpv2_mtu" || mtu=""
				[ -n "$ss_basic_udpv2_jitter" ] && jitter="--jitter $ss_basic_udpv2_jitter" || jitter=""
				[ -n "$ss_basic_udpv2_interval" ] && interval="-interval $ss_basic_udpv2_interval" || interval=""
				[ -n "$ss_basic_udpv2_drop" ] && drop="-random-drop $ss_basic_udpv2_drop" || drop=""
				[ -n "$ss_basic_udpv2_password" ] && key2="-k $ss_basic_udpv2_password" || key2=""
				[ -n "$ss_basic_udpv2_fec" ] && fec="-f $ss_basic_udpv2_fec" || fec=""

				if [ "$ss_basic_udp2raw_boost_enable" == "1" ];then
					#串联：如果两者都开启了，则把udpspeeder的流udp量转发给udp2raw
					speederv2 -c -l 0.0.0.0:1092 -r 127.0.0.1:1093 $key2 \
					$fec $timeout $mode $report $mtu $jitter $interval $drop $disable_obscure $disable_checksum $ss_basic_udpv2_other --fifo /tmp/fifo.file >/dev/null 2>&1 &
					#如果只开启了udpspeeder，则把udpspeeder的流udp量转发给服务器
				else
					speederv2 -c -l 0.0.0.0:1092 -r $ss_basic_udpv2_rserver:$ss_basic_udpv2_rport $key2 \
					$fec $timeout $mode $report $mtu $jitter $interval $drop $disable_obscure $disable_checksum $ss_basic_udpv2_other --fifo /tmp/fifo.file >/dev/null 2>&1 &
				fi
			fi
		fi
		#开启udp2raw
		if [ "$ss_basic_udp2raw_boost_enable" == "1" ];then
			echo_date 开启UDP2raw进程.
			[ "$ss_basic_udp2raw_a" == "1" ] && UD2RAW_EX1="-a" || UD2RAW_EX1=""
			[ "$ss_basic_udp2raw_keeprule" == "1" ] && UD2RAW_EX2="--keep-rule" || UD2RAW_EX2=""
			[ -n "$ss_basic_udp2raw_lowerlevel" ] && UD2RAW_LOW="--lower-level $ss_basic_udp2raw_lowerlevel" || UD2RAW_LOW=""
			[ -n "$ss_basic_udp2raw_password" ] && key3="-k $ss_basic_udp2raw_password" || key3=""
			
			udp2raw -c -l 0.0.0.0:1093 -r $ss_basic_udp2raw_rserver:$ss_basic_udp2raw_rport $key3 $UD2RAW_EX1 $UD2RAW_EX2\
			--raw-mode $ss_basic_udp2raw_rawmode --cipher-mode $ss_basic_udp2raw_ciphermode --auth-mode $ss_basic_udp2raw_authmode \
			$UD2RAW_LOW $ss_basic_udp2raw_other >/dev/null 2>&1 &
		fi
	fi
}

start_ss_redir(){
	if [ "$ss_basic_type" == "1" ];then
		echo_date 开启ssr-redir进程，用于透明代理.
		BIN=rss-redir
	elif  [ "$ss_basic_type" == "0" ];then
		# ss-libev需要大于160的熵才能正常工作
		start_haveged
		echo_date 开启ss-redir进程，用于透明代理.
		ss_arg
		BIN=ss-redir
	fi

	if [ "$ss_basic_udp_boost_enable" == "1" ];then
		#只要udpspeeder开启，不管udp2raw是否开启，均设置为1092,
		SPEED_PORT=1092
	else
		# 如果只开了udp2raw，则需要吧udp转发到1093
		SPEED_PORT=1093
	fi

	if [ "$ss_basic_udp2raw_boost_enable" == "1" ] || [ "$ss_basic_udp_boost_enable" == "1" ];then
		#udp2raw开启，udpspeeder未开启则ss-redir的udp流量应该转发到1093
		SPEED_UDP=1
	fi
	
	if [ "$ss_basic_use_kcp" == "1" ] && [ "$ss_basic_kcp_server" == "127.0.0.1" ] && [ "$ss_basic_kcp_port" == "1092" ];then
		SPEED_KCP=1
	fi
	
	if [ "$ss_basic_use_kcp" == "1" ] && [ "$ss_basic_kcp_server" == "127.0.0.1" ] && [ "$ss_basic_kcp_port" == "1093" ];then
		SPEED_KCP=2
	fi
	# Start ss-redir
	if [ "$ss_basic_use_kcp" == "1" ];then
		if [ "$mangle" == "1" ];then
			if [ "$SPEED_UDP" == "1" ] && [ "$ss_basic_udp_node" == "$ssconf_basic_node" ];then
				# tcp go kcp
				if [ "$SPEED_KCP" == "1" ];then
					echo_date $BIN的 tcp 走kcptun, kcptun的 udp 走 udpspeeder
				elif [ "$SPEED_KCP" == "2" ];then
					echo_date $BIN的 tcp 走kcptun, kcptun的 udp 走 udpraw
				else
					echo_date $BIN的 tcp 走kcptun.
				fi
				$BIN -s 127.0.0.1 -p 1091 -c $CONFIG_FILE $ARG_V2RAY_PLUGIN -f /var/run/shadowsocks.pid >/dev/null 2>&1
				# udp go udpspeeder
				[ "$ss_basic_udp2raw_boost_enable" == "1" ]  && [ "$ss_basic_udp_boost_enable" == "1" ] && echo_date $BIN的 udp 走udpspeeder, udpspeeder的 udp 走 udpraw
				[ "$ss_basic_udp2raw_boost_enable" == "1" ]  && [ "$ss_basic_udp_boost_enable" != "1" ] && echo_date $BIN的 udp 走udpraw.
				[ "$ss_basic_udp2raw_boost_enable" != "1" ]  && [ "$ss_basic_udp_boost_enable" == "1" ] && echo_date $BIN的 udp 走udpspeeder.
				[ "$ss_basic_udp2raw_boost_enable" != "1" ]  && [ "$ss_basic_udp_boost_enable" != "1" ] && echo_date $BIN的 udp 走$BIN.
				$BIN -s 127.0.0.1 -p $SPEED_PORT -c $CONFIG_FILE $ARG_V2RAY_PLUGIN -U -f /var/run/shadowsocks.pid >/dev/null 2>&1
			else
				# tcp go kcp
				if [ "$SPEED_KCP" == "1" ];then
					echo_date $BIN的 tcp 走kcptun, kcptun的 udp 走 udpspeeder
				elif [ "$SPEED_KCP" == "2" ];then
					echo_date $BIN的 tcp 走kcptun, kcptun的 udp 走 udpraw
				else
					echo_date $BIN的 tcp 走kcptun.
				fi
				$BIN -s 127.0.0.1 -p 1091 -c $CONFIG_FILE $ARG_V2RAY_PLUGIN -f /var/run/shadowsocks.pid >/dev/null 2>&1
				# udp go ss
				echo_date $BIN的 udp 走$BIN.
				$BIN -c $CONFIG_FILE $ARG_V2RAY_PLUGIN -U -f /var/run/shadowsocks.pid >/dev/null 2>&1
			fi
		else
			# tcp only go kcp
			if [ "$SPEED_KCP" == "1" ];then
				echo_date $BIN的 tcp 走kcptun, kcptun的 udp 走 udpspeeder
			elif [ "$SPEED_KCP" == "2" ];then
				echo_date $BIN的 tcp 走kcptun, kcptun的 udp 走 udpraw
			else
				echo_date $BIN的 tcp 走kcptun.
			fi
			echo_date $BIN的 udp 未开启.
			$BIN -s 127.0.0.1 -p 1091 -c $CONFIG_FILE $ARG_V2RAY_PLUGIN -f /var/run/shadowsocks.pid >/dev/null 2>&1
		fi
	else
		if [ "$mangle" == "1" ];then
			if [ "$SPEED_UDP" == "1" ] && [ "$ss_basic_udp_node" == "$ssconf_basic_node" ];then
				# tcp go ss
				echo_date $BIN的 tcp 走$BIN.
				$BIN -c $CONFIG_FILE $ARG_V2RAY_PLUGIN -f /var/run/shadowsocks.pid >/dev/null 2>&1
				# udp go udpspeeder
				[ "$ss_basic_udp2raw_boost_enable" == "1" ]  && [ "$ss_basic_udp_boost_enable" == "1" ] && echo_date $BIN的 udp 走udpspeeder, udpspeeder的 udp 走 udpraw
				[ "$ss_basic_udp2raw_boost_enable" == "1" ]  && [ "$ss_basic_udp_boost_enable" != "1" ] && echo_date $BIN的 udp 走udpraw.
				[ "$ss_basic_udp2raw_boost_enable" != "1" ]  && [ "$ss_basic_udp_boost_enable" == "1" ] && echo_date $BIN的 udp 走udpspeeder.
				[ "$ss_basic_udp2raw_boost_enable" != "1" ]  && [ "$ss_basic_udp_boost_enable" != "1" ] && echo_date $BIN的 udp 走$BIN.
				$BIN -s 127.0.0.1 -p $SPEED_PORT -c $CONFIG_FILE $ARG_V2RAY_PLUGIN -U -f /var/run/shadowsocks.pid >/dev/null 2>&1
			else
				# tcp udp go ss
				echo_date $BIN的 tcp 走$BIN.
				echo_date $BIN的 udp 走$BIN.
				$BIN -c $CONFIG_FILE $ARG_V2RAY_PLUGIN -u -f /var/run/shadowsocks.pid >/dev/null 2>&1
			fi
		else
			# tcp only go ss
			echo_date $BIN的 tcp 走$BIN.
			echo_date $BIN的 udp 未开启.
			$BIN -c $CONFIG_FILE $ARG_V2RAY_PLUGIN -f /var/run/shadowsocks.pid >/dev/null 2>&1		
		fi
	fi
	echo_date $BIN 启动完毕！.
	
	start_speeder
}

start_koolgame(){
	# Start koolgame
	pdu=`ps|grep pdu|grep -v grep`
	if [ -z "$pdu" ]; then
	echo_date 开启pdu进程，用于优化mtu...
		pdu br0 /tmp/var/pdu.pid >/dev/null 2>&1
		sleep 1
	fi
	echo_date 开启koolgame主进程...
	start-stop-daemon -S -q -b -m -p /tmp/var/koolgame.pid -x /koolshare/bin/koolgame -- -c $CONFIG_FILE
	
	if [ "$mangle" == "1" ] && [ "$ss_basic_udp_node" == "$ssconf_basic_node" ];then
		if [ "$ss_basic_udp_boost_enable" == "1" ];then
			if [ "$ss_basic_udp_software" == "1" ];then
				echo_date 检测到你启用了UDPspeederV1，但是koolgame下不支持UDPspeederV1加速，不启用！
				dbus set ss_basic_udp_boost_enable=0
			elif [ "$ss_basic_udp_software" == "2" ];then
				echo_date 检测到你启用了UDPspeederV2，但是koolgame下不支持UDPspeederV1加速，不启用！
				dbus set ss_basic_udp_boost_enable=0
			fi
		fi
		if [ "$ss_basic_udp2raw_boost_enable" == "1" ];then
			echo_date 检测到你启用了UDP2raw，但是koolgame下不支持UDP2raw，不启用！
			dbus set ss_basic_udp2raw_boost_enable=0
		fi
	fi
}

get_function_switch() {
	case "$1" in
		1)
			echo "true"
		;;
		*)
			echo "false"
		;;
	esac
}

get_ws_header() {
	if [ -n "$1" ];then
		echo {\"Host\": \"$1\"}
	else
		echo "null"
	fi
}

get_h2_host() {
	if [ -n "$1" ];then
		echo [\"$1\"]
	else
		echo "null"
	fi
}

get_path(){
	if [ -n "$1" ];then
		echo \"$1\"
	else
		echo "null"
	fi
}

resolve_node_ip4json(){	
	
	# 检测用户json的服务器ip地址
		node_protocol=$(cat "$V2RAY_CONFIG_FILE" | jq -r .outbounds[0].protocol)
		case $node_protocol in
		vmess)
			node_server=$(cat "$V2RAY_CONFIG_FILE" | jq -r .outbounds[0].settings.vnext[0].address)
			;;
		vless)
			node_server=$(cat "$V2RAY_CONFIG_FILE" | jq -r .outbounds[0].settings.vnext[0].address)
			;;			
		socks)
			node_server=$(cat "$V2RAY_CONFIG_FILE" | jq -r .outbounds[0].settings.servers[0].address)
			;;
		trojan)
			node_server=$(cat "$V2RAY_CONFIG_FILE" | jq -r .outbounds[0].settings.servers[0].address)
			;;
		shadowsocks)
			node_server=$(cat "$V2RAY_CONFIG_FILE" | jq -r .outbounds[0].settings.servers[0].address)
			;;
		*)
			node_server=""
			;;
		esac

		if [ -n "$node_server" -a "$node_server" != "null" ];then
			IFIP_VS=`echo $node_server|grep -E "([0-9]{1,3}[\.]){3}[0-9]{1,3}|:"`
			if [ -n "$IFIP_VS" ];then
				ss_basic_server_ip="$node_server"
				echo_date "检测到你的json配置的${node_protocol}服务器是：$node_server"
			else
				echo_date "检测到你的json配置的${node_protocol}服务器：$node_server不是ip格式！"
				echo_date "为了确保${node_protocol}的正常工作，建议配置ip格式的${node_protocol}服务器地址！"
				echo_date "尝试解析${node_protocol}服务器的ip地址，DNS：$(get_server_resolver)"
				# 服务器地址强制由114解析，以免插件还未开始工作而导致解析失败
				echo "server=/$node_server/$(get_server_resolver)#53" > /jffs/configs/dnsmasq.d/ss_server.conf
				node_server_ip=`nslookup "$node_server" $(get_server_resolver) | sed '1,4d' | awk '{print $3}' | grep -v :|awk 'NR==1{print}'`
				if [ "$?" == "0" ]; then
					node_server_ip=`echo $node_server_ip|grep -E "([0-9]{1,3}[\.]){3}[0-9]{1,3}|:"`
				else
					echo_date ${node_protocol}服务器域名解析失败！
					echo_date 尝试用resolveip方式解析，DNS：系统
					node_server_ip=`resolveip -4 -t 2 $ss_basic_server|awk 'NR==1{print}'`
					if [ "$?" == "0" ];then
						node_server_ip=`echo $node_server_ip|grep -E "([0-9]{1,3}[\.]){3}[0-9]{1,3}|:"`
					fi
				fi

				if [ -n "$node_server_ip" ];then
					echo_date "${node_protocol}服务器的ip地址解析成功：$node_server_ip"
					# 解析并记录一次ip，方便插件触发重启设定工作
					echo "address=/$node_server/$node_server_ip" > /tmp/ss_host.conf
					# 去掉此功能，以免ip发生变更导致问题，或者影响域名对应的其它二级域名
					#ln -sf /tmp/ss_host.conf /jffs/configs/dnsmasq.d/ss_host.conf
					ss_basic_server_ip="$node_server_ip"
				else
					echo_date "${node_protocol}服务器的ip地址解析失败!插件将继续运行，域名解析将由${node_protocol}自己进行！"
					echo_date "请自行将${node_protocol}服务器的ip地址填入IP/CIDR白名单中!"
					echo_date "为了确保${node_protocol}的正常工作，建议配置ip格式的${node_protocol}服务器地址！"
					#close_in_five
				fi
			fi
		else
			echo_date "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
			echo_date "+       没有检测到你的${node_protocol}服务器地址，如果你确定你的配置是正确的        +"
			echo_date "+   请自行将${node_protocol}服务器的ip地址填入【IP/CIDR】黑名单中，以确保正常使用   +"
			echo_date "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
		fi
	
}


create_v2ray_json(){
	rm -rf "$V2RAY_CONFIG_FILE_TMP"
	rm -rf "$V2RAY_CONFIG_FILE"
	if [ "$ss_basic_v2ray_use_json" == "0" ]; then
		echo_date 生成V2Ray配置文件...
		local kcp="null"
		local tcp="null"
		local ws="null"
		local h2="null"
		local grpc="null"
		local tls="null"
		local xtls="null"
		local vless_flow=""

		# tcp和kcp下tlsSettings为null，ws和h2下tlsSettings
		[ -z "$(dbus get ss_basic_v2ray_mux_concurrency)" ] && local ss_basic_v2ray_mux_concurrency=8
		[ "$ss_basic_v2ray_network_security" == "none" ] && local ss_basic_v2ray_network_security=""

		# incase multi-domain input
		if [ "$(echo $ss_basic_v2ray_network_host | grep ",")" ]; then
			ss_basic_v2ray_network_host=$(echo $ss_basic_v2ray_network_host | sed 's/,/", "/g')
		fi

		if [ "$ss_basic_v2ray_network" == "ws" -o "$ss_basic_v2ray_network" == "h2" ] && [ -z "$ss_basic_v2ray_network_tlshost" ] && [ -n "$ss_basic_v2ray_network_host" ]; then
		 	local ss_basic_v2ray_network_tlshost="$ss_basic_v2ray_network_host"
		fi

		case "$ss_basic_v2ray_network_security" in
		tls)
			local tls="{
					\"allowInsecure\": $(get_function_switch $ss_basic_allowinsecure),
					\"serverName\": \"$ss_basic_v2ray_network_tlshost\"
					}"
			;;
		xtls)
			local xtls="{
					\"allowInsecure\": $(get_function_switch $ss_basic_allowinsecure),
					\"serverName\": \"$ss_basic_v2ray_network_tlshost\"
					}"
			local vless_flow="\"flow\": \"$ss_basic_v2ray_network_flow\","
			;;
		*)
			local tls="null"
			local xtls="null"
			;;
		esac
		
		case "$ss_basic_v2ray_network" in
		tcp)
			if [ "$ss_basic_v2ray_headtype_tcp" == "http" ]; then
				local tcp="{
					\"connectionReuse\": true,
					\"header\": {
					\"type\": \"http\",
					\"request\": {
					\"version\": \"1.1\",
					\"method\": \"GET\",
					\"path\": [\"/\"],
					\"headers\": {
					\"Host\": [\"$ss_basic_v2ray_network_host\"],
					\"User-Agent\": [\"Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/55.0.2883.75 Safari/537.36\",\"Mozilla/5.0 (iPhone; CPU iPhone OS 10_0_2 like Mac OS X) AppleWebKit/601.1 (KHTML, like Gecko) CriOS/53.0.2785.109 Mobile/14A456 Safari/601.1.46\"],
					\"Accept-Encoding\": [\"gzip, deflate\"],
					\"Connection\": [\"keep-alive\"],
					\"Pragma\": \"no-cache\"
					}
					},
					\"response\": {
					\"version\": \"1.1\",
					\"status\": \"200\",
					\"reason\": \"OK\",
					\"headers\": {
					\"Content-Type\": [\"application/octet-stream\",\"video/mpeg\"],
					\"Transfer-Encoding\": [\"chunked\"],
					\"Connection\": [\"keep-alive\"],
					\"Pragma\": \"no-cache\"
					}
					}
					}
					}"
			else
				local tcp="null"
			fi
			;;
		kcp)
			local kcp="{
				\"mtu\": 1350,
				\"tti\": 50,
				\"uplinkCapacity\": 12,
				\"downlinkCapacity\": 100,
				\"congestion\": false,
				\"readBufferSize\": 2,
				\"writeBufferSize\": 2,
				\"seed\": \"$ss_basic_v2ray_network_path\",
				\"header\": {
				\"type\": \"$ss_basic_v2ray_headtype_kcp\",
				\"request\": null,
				\"response\": null
				}
				}"
			;;
		ws)
			local ws="{
				\"connectionReuse\": true,
				\"path\": $(get_path $ss_basic_v2ray_network_path),
				\"headers\": $(get_ws_header $ss_basic_v2ray_network_host)
				}"
			;;
		h2)
			local h2="{
				\"path\": $(get_path $ss_basic_v2ray_network_path),
				\"host\": $(get_h2_host $ss_basic_v2ray_network_host)
				}"
			;;
		grpc)
			local grpc="{
				\"serviceName\": $(get_path $ss_basic_v2ray_serviceName) 
				}"
			;;	
		esac
		# log area
		cat >"$V2RAY_CONFIG_FILE_TMP" <<-EOF
			{
			"log": {
				"access": "/dev/null",
				"error": "/tmp/v2ray_log.log",
				"loglevel": "error"
			},
		EOF
		# inbounds area (7913 for dns resolve)
		if [ "$ss_foreign_dns" == "7" ]; then
			echo_date 配置v2ray dns，用于dns解析...
			cat >>"$V2RAY_CONFIG_FILE_TMP" <<-EOF
				"inbounds": [
					{
					"protocol": "dokodemo-door",
					"port": $DNSF_PORT,
					"settings": {
						"address": "8.8.8.8",
						"port": 53,
						"network": "udp",
						"timeout": 0,
						"followRedirect": false
						}
					},
					{
						"listen": "0.0.0.0",
						"port": 3333,
						"protocol": "dokodemo-door",
						"settings": {
							"network": "tcp,udp",
							"followRedirect": true
						}
					}
				],
			EOF
		else
			# inbounds area (23456 for socks5)
			cat >>"$V2RAY_CONFIG_FILE_TMP" <<-EOF
				"inbounds": [
					{
						"port": 23456,
						"listen": "0.0.0.0",
						"protocol": "socks",
						"settings": {
							"auth": "noauth",
							"udp": true,
							"ip": "127.0.0.1",
							"clients": null
						},
						"streamSettings": null
					},
					{
						"listen": "0.0.0.0",
						"port": 3333,
						"protocol": "dokodemo-door",
						"settings": {
							"network": "tcp,udp",
							"followRedirect": true
						}
					}
				],
			EOF
		fi
		# outbounds area
		if [ "$ss_basic_v2ray_protocol" == "vmess" ]; then
			cat >>"$V2RAY_CONFIG_FILE_TMP" <<-EOF
				"outbounds": [
				  {
					"tag": "agentout",
					"protocol": "vmess",
					"settings": {
					  "vnext": [
						{
						  "address": "$(dbus get ss_basic_server)",
						  "port": $ss_basic_port,
						  "users": [
							{
							  "id": "$ss_basic_v2ray_uuid",
							  "alterId": $ss_basic_v2ray_alterid,
							  "security": "$ss_basic_v2ray_security"
							}
						  ]
						}
					  ],
					  "servers": null
					},
					"streamSettings": {
					  "network": "$ss_basic_v2ray_network",
					  "security": "$ss_basic_v2ray_network_security",
					  "tlsSettings": $tls,
					  "tcpSettings": $tcp,
					  "kcpSettings": $kcp,
					  "wsSettings": $ws,
					  "httpSettings": $h2,
					  "grpcSettings": $grpc
					},
					"mux": {
					  "enabled": $(get_function_switch $ss_basic_v2ray_mux_enable),
					  "concurrency": $ss_basic_v2ray_mux_concurrency
					}
				  }
				]
				}
			EOF
		elif [ "$ss_basic_v2ray_protocol" == "vless" ]; then
		  #vless
		  cat >>"$V2RAY_CONFIG_FILE_TMP" <<-EOF
				"outbounds": [
				  {
					"tag": "agentout",
					"protocol": "vless",
					"settings": {
					  "vnext": [
						{
						  "address": "$(dbus get ss_basic_server)",
						  "port": $ss_basic_port,
						  "users": [
							{
							  "id": "$ss_basic_v2ray_uuid",
							  "level": 1,
							  $vless_flow
							  "encryption": "none"
							}
						  ]
						}
					  ],
					  "servers": null
					},
					"streamSettings": {
					  "network": "$ss_basic_v2ray_network",
					  "security": "$ss_basic_v2ray_network_security",
					  "tlsSettings": $tls,
					  "xtlsSettings": $xtls,
					  "tcpSettings": $tcp,
					  "kcpSettings": $kcp,
					  "wsSettings": $ws,
					  "httpSettings": $h2,
					  "grpcSettings": $grpc
					},
					"mux": {
					  "enabled": $(get_function_switch $ss_basic_v2ray_mux_enable),
					  "concurrency": $ss_basic_v2ray_mux_concurrency
					}
				  }
				]
				}
			EOF
		fi
		echo_date 解析V2Ray配置文件...
		cat "$V2RAY_CONFIG_FILE_TMP" | jq --tab . >"$V2RAY_CONFIG_FILE"
		echo_date V2Ray配置文件写入成功到"$V2RAY_CONFIG_FILE"
	elif [ "$ss_basic_v2ray_use_json" == "1" ]; then
		echo_date 使用自定义的v2ray json配置文件...
		echo "$ss_basic_v2ray_json" | base64_decode >"$V2RAY_CONFIG_FILE_TMP"
		local OB=$(cat "$V2RAY_CONFIG_FILE_TMP" | jq .outbound)
		local OBS=$(cat "$V2RAY_CONFIG_FILE_TMP" | jq .outbounds)

		# 兼容旧格式：outbound
		if [ "$OB" != "null" ]; then
			OUTBOUNDS=$(cat "$V2RAY_CONFIG_FILE_TMP" | jq .outbound)
		fi
		
		# 新格式：outbound[]
		if [ "$OBS" != "null" ]; then
			OUTBOUNDS=$(cat "$V2RAY_CONFIG_FILE_TMP" | jq .outbounds[])
		fi
		
		if [ "$ss_foreign_dns" == "7" ]; then
			local TEMPLATE="{
								\"log\": {
									\"access\": \"/dev/null\",
									\"error\": \"/tmp/v2ray_log.log\",
									\"loglevel\": \"error\"
								},
								\"inbounds\": [
									{
										\"protocol\": \"dokodemo-door\", 
										\"port\": $DNSF_PORT,
										\"settings\": {
											\"address\": \"8.8.8.8\",
											\"port\": 53,
											\"network\": \"udp\",
											\"timeout\": 0,
											\"followRedirect\": false
										}
									},
									{
										\"listen\": \"0.0.0.0\",
										\"port\": 3333,
										\"protocol\": \"dokodemo-door\",
										\"settings\": {
											\"network\": \"tcp,udp\",
											\"followRedirect\": true
										}
									}
								]
							}"
		else
			local TEMPLATE="{
								\"log\": {
									\"access\": \"/dev/null\",
									\"error\": \"/tmp/v2ray_log.log\",
									\"loglevel\": \"error\"
								},
								\"inbounds\": [
									{
										\"port\": 23456,
										\"listen\": \"0.0.0.0\",
										\"protocol\": \"socks\",
										\"settings\": {
											\"auth\": \"noauth\",
											\"udp\": true,
											\"ip\": \"127.0.0.1\",
											\"clients\": null
										},
										\"streamSettings\": null
									},
									{
										\"listen\": \"0.0.0.0\",
										\"port\": 3333,
										\"protocol\": \"dokodemo-door\",
										\"settings\": {
											\"network\": \"tcp,udp\",
											\"followRedirect\": true
										}
									}
								]
							}"
		fi
		echo_date 解析V2Ray配置文件...
		echo $TEMPLATE | jq --argjson args "$OUTBOUNDS" '. + {outbounds: [$args]}' >"$V2RAY_CONFIG_FILE"
		echo_date V2Ray配置文件写入成功到"$V2RAY_CONFIG_FILE"

		# 检测用户json的服务器ip地址
		resolve_node_ip4json
	fi

	cd /koolshare/bin
	if [ "$ss_basic_v2ray_xray" == "xray" ] ; then
		echo_date 测试XRay配置文件.....
		result=$(xray -test -config="$V2RAY_CONFIG_FILE" | grep "Configuration OK.")
	else
		echo_date 测试V2Ray配置文件.....
		result=$(v2ray -test -config="$V2RAY_CONFIG_FILE" | grep "Configuration OK.")
	fi
	if [ -n "$result" ]; then
		echo_date $result
		echo_date V2Ray/Xray配置文件通过测试!!!
	else
		echo_date V2Ray/Xray配置文件没有通过测试，请检查设置!!!
		rm -rf "$V2RAY_CONFIG_FILE_TMP"
		rm -rf "$V2RAY_CONFIG_FILE"
		close_in_five
	fi
}

create_trojan_json(){
	rm -rf "$V2RAY_CONFIG_FILE_TMP"
	rm -rf "$V2RAY_CONFIG_FILE"
	if  [ "$ss_basic_type" == "4" ] && [ "$ss_basic_trojan_binary" == "Trojan" ]; then
		echo_date 生成Trojan配置文件...
		 #trojan
		 # inbounds area (23456 for socks5)  
		cat >"$V2RAY_CONFIG_FILE_TMP" <<-EOF
		{
			"log": {
				"access": "/dev/null",
				"error": "/tmp/v2ray_log.log",
				"loglevel": "error"
			},
				"inbounds": [
					{
						"port": 23456,
						"listen": "0.0.0.0",
						"protocol": "socks",
						"settings": {
							"auth": "noauth",
							"udp": true,
							"ip": "127.0.0.1",
							"clients": null
						},
						"streamSettings": null
					},
					{
						"listen": "0.0.0.0",
						"port": 3333,
						"protocol": "dokodemo-door",
						"settings": {
							"network": "tcp,udp",
							"followRedirect": true
						}
					}
				],
			"outbounds": [
			  {
				"protocol": "trojan",
				"settings": {
				  "servers": [
					{
					  "address": "$(dbus get ss_basic_server)",
					  "port": $ss_basic_port,
					  "password": "$ss_basic_password"
					}
				  ]
				},
				"streamSettings": {
				  "network": "tcp",
				  "security": "tls",
				  "tlsSettings": {
					"allowInsecure": $(get_function_switch $ss_basic_allowinsecure),  
                    "serverName": "$ss_basic_trojan_sni"
                }
				}
			  }
			]
		}
		EOF
	
		echo_date 解析Trojan配置文件...
	#	cp "$V2RAY_CONFIG_FILE_TMP" /tmp/home/root/trojantmp.json
		cat "$V2RAY_CONFIG_FILE_TMP" | jq --tab . >"$V2RAY_CONFIG_FILE"
			
		echo_date Trojan配置文件写入成功到"$V2RAY_CONFIG_FILE"
			
		cd /koolshare/bin
		echo_date 测试Trojan配置文件.....
		result=$(xray -test -config="$V2RAY_CONFIG_FILE" | grep "Configuration OK.")
		if [ -n "$result" ]; then
			echo_date $result
			echo_date Trojan配置文件通过测试!!!
		else
			echo_date Trojan配置文件没有通过测试，请检查设置!!!
			rm -rf "$V2RAY_CONFIG_FILE_TMP"
			rm -rf "$V2RAY_CONFIG_FILE"
			close_in_five
		fi
	fi
}


create_trojango_json(){
	rm -rf "$TROJANGO_CONFIG_FILE"
	rm -rf "$TROJANGO2_CONFIG_FILE"
	if  [ "$ss_basic_type" == "4" ] && [ "$ss_basic_trojan_binary" == "Trojan-Go" ]; then
		if [ "$ss_basic_trojan_network" == "1" ]; then
		[ -n "$ss_basic_v2ray_network_path" ] && local ss_basic_v2ray_network_path=$(echo "/$ss_basic_v2ray_network_path" | sed 's,//,/,')
			local ws="{ \"enabled\": true,
						\"path\":  \"$ss_basic_v2ray_network_path\",
						\"host\":  \"$ss_basic_v2ray_network_host\"
						}"
		else
			local ws="{ \"enabled\": false,
						\"path\":  \"\",
						\"host\":  \"\"
						}"
		fi
		[ -z "$(dbus get ss_basic_v2ray_mux_concurrency)" ] && local ss_basic_v2ray_mux_concurrency=8
		echo_date 生成Trojan Go配置文件...
		 #trojan go
		 # 3333 for nat  
		cat >"$TROJANGO_CONFIG_FILE" <<-EOF
			{
				"run_type": "nat",
				"local_addr": "0.0.0.0",
				"local_port": 3333,
				"remote_addr": "$ss_basic_server",
				"remote_port": $ss_basic_port,
				"log_level": 1,
				"log_file": "/tmp/trojan-go_log.log",
				"password": [
				"$ss_basic_password"
				],
				"disable_http_check": false,
				"udp_timeout": 60,
				"ssl": {
					"verify": true,
					"verify_hostname": true,
					"cert": "/rom/etc/ssl/certs/ca-certificates.crt",
					"cipher": "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA:AES128-SHA:AES256-SHA:DES-CBC3-SHA",
					"sni": "$ss_basic_trojan_sni",
					"alpn": [
					"http/1.1"
					],
					"session_ticket": true,
					"reuse_session": true
				},
				"tcp": {
					"no_delay": true,
					"keep_alive": true,
					"prefer_ipv4": true
				},
				"mux": {
					"enabled": $(get_function_switch $ss_basic_v2ray_mux_enable),
					"concurrency": $ss_basic_v2ray_mux_concurrency,
					"idle_timeout": 60
				},
				"websocket": $ws
				,
				"shadowsocks": {
					"enabled": false,
					"method": "AES-128-GCM",
					"password": ""
				}
			}
		EOF

		 #  23456 for socks5  
		cat >"$TROJANGO2_CONFIG_FILE" <<-EOF
			{
				"run_type": "client",
				"local_addr": "127.0.0.1",
				"local_port": 23456,
				"remote_addr": "$ss_basic_server",
				"remote_port": $ss_basic_port,
				"log_level": 1,
				"log_file": "/tmp/trojan-go_log.log",
				"password": [
				"$ss_basic_password"
				],
				"disable_http_check": false,
				"udp_timeout": 60,
				"ssl": {
					"verify": true,
					"verify_hostname": true,
					"cert": "/rom/etc/ssl/certs/ca-certificates.crt",
					"cipher": "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA:AES128-SHA:AES256-SHA:DES-CBC3-SHA",
					"sni": "$ss_basic_trojan_sni",
					"alpn": [
					"http/1.1"
					],
					"session_ticket": true,
					"reuse_session": true
				},
				"tcp": {
					"no_delay": true,
					"keep_alive": true,
					"prefer_ipv4": true
				},
				"mux": {
					"enabled": $(get_function_switch $ss_basic_v2ray_mux_enable),
					"concurrency": $ss_basic_v2ray_mux_concurrency,
					"idle_timeout": 60
				},
				"websocket": $ws
				,
				"shadowsocks": {
					"enabled": false,
					"method": "AES-128-GCM",
					"password": ""
				}
			}
		EOF
		
		echo_date Trojan-Go配置文件写入成功到"$TROJANGO_CONFIG_FILE"
	fi
}

start_v2ray() {
	# v2ray start
	cd /koolshare/bin
	#export GOGC=30
	v2ray -config=/koolshare/ss/v2ray.json >/dev/null 2>&1 &
	local V2PID
	local i=10
	until [ -n "$V2PID" ]; do
		i=$(($i - 1))
		V2PID=$(pidof v2ray)
		if [ "$i" -lt 1 ]; then
			echo_date "v2ray进程启动失败！"
			close_in_five
		fi
		sleep 1
	done
	echo_date v2ray启动成功，pid：$V2PID
}

start_v2ray_xray() {
	if [ "$ss_basic_v2ray_xray" == "xray" ]; then
		start_xray
	elif [ "$ss_basic_type" == "4" ]; then
		start_trojan
	else
		start_v2ray
	fi


}

start_xray() {
	# v2ray start
	cd /koolshare/bin
	#export GOGC=30
	xray run -config=/koolshare/ss/v2ray.json >/dev/null 2>&1 &
	local xrayPID
	local i=10
	until [ -n "$xrayPID" ]; do
		i=$(($i - 1))
		xrayPID=$(pidof xray)
		if [ "$i" -lt 1 ]; then
			echo_date "xray进程启动失败！"
			close_in_five
		fi
		sleep 1
	done
	echo_date xray启动成功，pid：$xrayPID
}

start_trojan() {
	# trojan start
	cd /koolshare/bin
	#export GOGC=30
	xray run -config=/koolshare/ss/v2ray.json >/dev/null 2>&1 &
	local trojanPID
	local i=10
	until [ -n "$trojanPID" ]; do
		i=$(($i - 1))
		trojanPID=$(pidof xray)
		if [ "$i" -lt 1 ]; then
			echo_date "trojan进程启动失败！"
			close_in_five
		fi
		sleep 1
	done
	echo_date trojan启动成功，pid：$trojanPID
}

start_trojango() {
	# trojango start
	cd /koolshare/bin
	trojan-go -config $TROJANGO_CONFIG_FILE >/dev/null 2>&1 &
	local trojangoPID
	local i=10
	until [ -n "$trojangoPID" ]; do
		i=$(($i - 1))
		trojangoPID=`ps | grep -w trojan-go | grep -v "grep" | grep "$TROJANGO_CONFIG_FILE" | awk '{print $1}'`
		if [ "$i" -lt 1 ]; then
			echo_date "trojan-go进程启动失败！"
			close_in_five
		fi
		sleep 1
	done
	echo_date trojan-go启动成功，pid：$trojangoPID
}

write_cron_job(){
	sed -i '/ssupdate/d' /var/spool/cron/crontabs/* >/dev/null 2>&1
	if [ "1" == "$ss_basic_rule_update" ]; then
		echo_date 添加shadowsocks规则定时更新任务，每天"$ss_basic_rule_update_time"自动检测更新规则.
		cru a ssupdate "0 $ss_basic_rule_update_time * * * /bin/sh /koolshare/scripts/ss_rule_update.sh"
	else
		echo_date shadowsocks规则定时更新任务未启用！
	fi
	sed -i '/ssnodeupdate/d' /var/spool/cron/crontabs/* >/dev/null 2>&1
	if [ "$ss_basic_node_update" = "1" ];then
		if [ "$ss_basic_node_update_day" = "7" ];then
			cru a ssnodeupdate "0 $ss_basic_node_update_hr * * * /koolshare/scripts/ss_online_update.sh 3"
			echo_date "设置自动更新节点订阅在每天 $ss_basic_node_update_hr 点。"
		else
			cru a ssnodeupdate "0 $ss_basic_node_update_hr * * $ss_basic_node_update_day /koolshare/scripts/ss_online_update.sh 3"
			echo_date "设置自动更新节点订阅在星期 $ss_basic_node_update_day 的 $ss_basic_node_update_hr 点。"
		fi
	fi
}

kill_cron_job(){
	if [ -n "`cru l|grep ssupdate`" ];then
		echo_date 删除shadowsocks规则定时更新任务...
		sed -i '/ssupdate/d' /var/spool/cron/crontabs/* >/dev/null 2>&1
	fi
	if [ -n "`cru l|grep ssnodeupdate`" ];then
		echo_date 删除节点定时订阅任务...
		sed -i '/ssnodeupdate/d' /var/spool/cron/crontabs/* >/dev/null 2>&1
	fi
}
#--------------------------------------nat part begin------------------------------------------------
load_tproxy(){
	MODULES="nf_tproxy_core xt_TPROXY xt_socket xt_comment"
	OS=$(uname -r)
	# load Kernel Modules
	echo_date 加载TPROXY模块，用于udp转发...
	checkmoduleisloaded(){
		if lsmod | grep $MODULE &> /dev/null; then return 0; else return 1; fi;
	}
	
	for MODULE in $MODULES; do
		if ! checkmoduleisloaded; then
			insmod /lib/modules/${OS}/kernel/net/netfilter/${MODULE}.ko
		fi
	done
	
	modules_loaded=0
	
	for MODULE in $MODULES; do
		if checkmoduleisloaded; then
			modules_loaded=$(( j++ )); 
		fi
	done
	
	if [ $modules_loaded -ne 3 ]; then
		echo "One or more modules are missing, only $(( modules_loaded+1 )) are loaded. Can't start.";
		close_in_five
	fi
}


flush_nat(){
	echo_date 清除iptables规则和ipset...
	# flush rules and set if any
	nat_indexs=`iptables -nvL PREROUTING -t nat |sed 1,2d | sed -n '/SHADOWSOCKS/='|sort -r`
	for nat_index in $nat_indexs
	do
		iptables -t nat -D PREROUTING $nat_index >/dev/null 2>&1
	done
	#iptables -t nat -D PREROUTING -p tcp -j SHADOWSOCKS >/dev/null 2>&1
	
	iptables -t nat -F SHADOWSOCKS > /dev/null 2>&1 && iptables -t nat -X SHADOWSOCKS > /dev/null 2>&1
	iptables -t nat -F SHADOWSOCKS_EXT > /dev/null 2>&1
	iptables -t nat -F SHADOWSOCKS_GFW > /dev/null 2>&1 && iptables -t nat -X SHADOWSOCKS_GFW > /dev/null 2>&1
	iptables -t nat -F SHADOWSOCKS_CHN > /dev/null 2>&1 && iptables -t nat -X SHADOWSOCKS_CHN > /dev/null 2>&1
	iptables -t nat -F SHADOWSOCKS_GAM > /dev/null 2>&1 && iptables -t nat -X SHADOWSOCKS_GAM > /dev/null 2>&1
	iptables -t nat -F SHADOWSOCKS_GLO > /dev/null 2>&1 && iptables -t nat -X SHADOWSOCKS_GLO > /dev/null 2>&1
	iptables -t nat -F SHADOWSOCKS_HOM > /dev/null 2>&1 && iptables -t nat -X SHADOWSOCKS_HOM > /dev/null 2>&1

	mangle_indexs=`iptables -nvL PREROUTING -t mangle |sed 1,2d | sed -n '/SHADOWSOCKS/='|sort -r`
	for mangle_index in $mangle_indexs
	do
		iptables -t mangle -D PREROUTING $mangle_index >/dev/null 2>&1
	done
	#iptables -t mangle -D PREROUTING -p udp -j SHADOWSOCKS >/dev/null 2>&1
	
	iptables -t mangle -F SHADOWSOCKS >/dev/null 2>&1 && iptables -t mangle -X SHADOWSOCKS >/dev/null 2>&1
	iptables -t mangle -F SHADOWSOCKS_GAM > /dev/null 2>&1 && iptables -t mangle -X SHADOWSOCKS_GAM > /dev/null 2>&1
	iptables -t nat -D OUTPUT -p tcp -m set --match-set router dst -j REDIRECT --to-ports 3333 >/dev/null 2>&1
	iptables -t nat -F OUTPUT > /dev/null 2>&1
	iptables -t nat -X SHADOWSOCKS_EXT > /dev/null 2>&1
	#iptables -t nat -D PREROUTING -p udp -s $(get_lan_cidr) --dport 53 -j DNAT --to $lan_ipaddr >/dev/null 2>&1
	chromecast_nu=`iptables -t nat -L PREROUTING -v -n --line-numbers|grep "dpt:53"|awk '{print $1}'`
	[ -n "$chromecast_nu" ] && iptables -t nat -D PREROUTING $chromecast_nu >/dev/null 2>&1
	iptables -t mangle -D QOSO0 -m mark --mark "$ip_prefix_hex" -j RETURN >/dev/null 2>&1
	# flush ipset
	ipset -F chnroute >/dev/null 2>&1 && ipset -X chnroute >/dev/null 2>&1
	ipset -F white_list >/dev/null 2>&1 && ipset -X white_list >/dev/null 2>&1
	ipset -F black_list >/dev/null 2>&1 && ipset -X black_list >/dev/null 2>&1
	ipset -F gfwlist >/dev/null 2>&1 && ipset -X gfwlist >/dev/null 2>&1
	ipset -F router >/dev/null 2>&1 && ipset -X router >/dev/null 2>&1
	#remove_redundant_rule
	ip_rule_exist=`ip rule show | grep "lookup 310" | grep -c 310`
	if [ -n "ip_rule_exist" ];then
		#echo_date 清除重复的ip rule规则.
		until [ "$ip_rule_exist" = 0 ]
		do 
			IP_ARG=`ip rule show | grep "lookup 310"|head -n 1|cut -d " " -f3,4,5,6`
			ip rule del $IP_ARG
			ip_rule_exist=`expr $ip_rule_exist - 1`
		done
	fi
	#remove_route_table
	#echo_date 删除ip route规则.
	ip route del local 0.0.0.0/0 dev lo table 310 >/dev/null 2>&1
}

# create ipset rules
create_ipset(){
	echo_date 创建ipset名单
	ipset -! create white_list nethash && ipset flush white_list
	ipset -! create black_list nethash && ipset flush black_list
	ipset -! create gfwlist nethash && ipset flush gfwlist
	ipset -! create router nethash && ipset flush router
	ipset -! create chnroute nethash && ipset flush chnroute
	sed -e "s/^/add chnroute &/g" /koolshare/ss/rules/chnroute.txt | awk '{print $0} END{print "COMMIT"}' | ipset -R
}

add_white_black_ip(){
	# black ip/cidr
	if [ "$ss_basic_mode" != "6" ];then
		ip_tg="149.154.0.0/16 91.108.4.0/22 91.108.56.0/24 109.239.140.0/24 67.198.55.0/24"
		for ip in $ip_tg
		do
			ipset -! add black_list $ip >/dev/null 2>&1
		done
	fi
	
	if [ -n "$ss_wan_black_ip" ];then
		ss_wan_black_ip=`dbus get ss_wan_black_ip|base64_decode|sed '/\#/d'`
		echo_date 应用IP/CIDR黑名单
		for ip in $ss_wan_black_ip
		do
			ipset -! add black_list $ip >/dev/null 2>&1
		done
	fi
	
	# white ip/cidr
	[ -n "$ss_basic_server_ip" ] && SERVER_IP="$ss_basic_server_ip" || SERVER_IP=""
	[ -n "$IFIP_DNS1" ] && ISP_DNS_a="$ISP_DNS1" || ISP_DNS_a=""
	[ -n "$IFIP_DNS2" ] && ISP_DNS_b="$ISP_DNS2" || ISP_DNS_a=""
	ip_lan="0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4 223.5.5.5 223.6.6.6 114.114.114.114 114.114.115.115 1.2.4.8 210.2.4.8 117.50.11.11 117.50.22.22 180.76.76.76 119.29.29.29 $ISP_DNS_a $ISP_DNS_b $SERVER_IP $(get_wan0_cidr)"
	for ip in $ip_lan
	do
		ipset -! add white_list $ip >/dev/null 2>&1
	done
	
	if [ -n "$ss_wan_white_ip" ];then
		ss_wan_white_ip=`echo $ss_wan_white_ip|base64_decode|sed '/\#/d'`
		echo_date 应用IP/CIDR白名单
		for ip in $ss_wan_white_ip
		do
			ipset -! add white_list $ip >/dev/null 2>&1
		done
	fi
}

get_action_chain() {
	case "$1" in
		0)
			echo "RETURN"
		;;
		1)
			echo "SHADOWSOCKS_GFW"
		;;
		2)
			echo "SHADOWSOCKS_CHN"
		;;
		3)
			echo "SHADOWSOCKS_GAM"
		;;
		5)
			echo "SHADOWSOCKS_GLO"
		;;
		6)
			echo "SHADOWSOCKS_HOM"
		;;
	esac
}

get_mode_name() {
	case "$1" in
		0)
			echo "不通过SS"
		;;
		1)
			echo "gfwlist模式"
		;;
		2)
			echo "大陆白名单模式"
		;;
		3)
			echo "游戏模式"
		;;
		5)
			echo "全局模式"
		;;
		6)
			echo "回国模式"
		;;
	esac
}

factor(){
	if [ -z "$1" ] || [ -z "$2" ]; then
		echo ""
	else
		echo "$2 $1"
	fi
}

get_jump_mode(){
	case "$1" in
		0)
			echo "j"
		;;
		*)
			echo "g"
		;;
	esac
}

lan_acess_control(){
	# lan access control
	acl_nu=`dbus list ss_acl_mode_|cut -d "=" -f 1 | cut -d "_" -f 4 | sort -n`
	if [ -n "$acl_nu" ]; then
		for acl in $acl_nu
		do
			ipaddr=`dbus get ss_acl_ip_$acl`
			ipaddr_hex=`dbus get ss_acl_ip_$acl | awk -F "." '{printf ("0x%02x", $1)} {printf ("%02x", $2)} {printf ("%02x", $3)} {printf ("%02x\n", $4)}'`
			ports=`dbus get ss_acl_port_$acl`
			proxy_mode=`dbus get ss_acl_mode_$acl`
			proxy_name=`dbus get ss_acl_name_$acl`
			if [ "$ports" == "all" ];then
				ports=""
				echo_date 加载ACL规则：【$ipaddr】【全部端口】模式为：$(get_mode_name $proxy_mode)
			else
				echo_date 加载ACL规则：【$ipaddr】【$ports】模式为：$(get_mode_name $proxy_mode)
			fi
			# 1 acl in SHADOWSOCKS for nat
			iptables -t nat -A SHADOWSOCKS $(factor $ipaddr "-s") -p tcp $(factor $ports "-m multiport --dport") -$(get_jump_mode $proxy_mode) $(get_action_chain $proxy_mode)
			# 2 acl in OUTPUT（used by koolproxy）
			iptables -t nat -A SHADOWSOCKS_EXT -p tcp  $(factor $ports "-m multiport --dport") -m mark --mark "$ipaddr_hex" -$(get_jump_mode $proxy_mode) $(get_action_chain $proxy_mode)
			# 3 acl in SHADOWSOCKS for mangle
			if [ "$proxy_mode" == "3" ];then
				iptables -t mangle -A SHADOWSOCKS $(factor $ipaddr "-s") -p udp $(factor $ports "-m multiport --dport") -$(get_jump_mode $proxy_mode) $(get_action_chain $proxy_mode)
			else
				[ "$mangle" == "1" ] && iptables -t mangle -A SHADOWSOCKS $(factor $ipaddr "-s") -p udp -j RETURN
			fi
		done

		if [ "$ss_acl_default_port" == "all" ];then
			ss_acl_default_port=""
			[ -z "$ss_acl_default_mode" ] && dbus set ss_acl_default_mode="$ss_basic_mode" && ss_acl_default_mode="$ss_basic_mode"
			echo_date 加载ACL规则：【剩余主机】【全部端口】模式为：$(get_mode_name $ss_acl_default_mode)
		else
			echo_date 加载ACL规则：【剩余主机】【$ss_acl_default_port】模式为：$(get_mode_name $ss_acl_default_mode)
		fi
	else
		ss_acl_default_mode="$ss_basic_mode"
		if [ "$ss_acl_default_port" == "all" ];then
			ss_acl_default_port="" 
			echo_date 加载ACL规则：【全部主机】【全部端口】模式为：$(get_mode_name $ss_acl_default_mode)
		else
			echo_date 加载ACL规则：【全部主机】【$ss_acl_default_port】模式为：$(get_mode_name $ss_acl_default_mode)
		fi
	fi
	dbus remove ss_acl_ip
	dbus remove ss_acl_name
	dbus remove ss_acl_mode
	dbus remove ss_acl_port
}

apply_nat_rules(){
	#----------------------BASIC RULES---------------------
	echo_date 写入iptables规则到nat表中...
	# 创建SHADOWSOCKS nat rule
	iptables -t nat -N SHADOWSOCKS
	# 扩展
	iptables -t nat -N SHADOWSOCKS_EXT
	# IP/cidr/白域名 白名单控制（不走ss）
	iptables -t nat -A SHADOWSOCKS -p tcp -m set --match-set white_list dst -j RETURN
	iptables -t nat -A SHADOWSOCKS_EXT -p tcp -m set --match-set white_list dst -j RETURN
	#-----------------------FOR GLOABLE---------------------
	# 创建gfwlist模式nat rule
	iptables -t nat -N SHADOWSOCKS_GLO
	# IP黑名单控制-gfwlist（走ss）
	iptables -t nat -A SHADOWSOCKS_GLO -p tcp -j REDIRECT --to-ports 3333
	#-----------------------FOR GFWLIST---------------------
	# 创建gfwlist模式nat rule
	iptables -t nat -N SHADOWSOCKS_GFW
	# IP/CIDR/黑域名 黑名单控制（走ss）
	iptables -t nat -A SHADOWSOCKS_GFW -p tcp -m set --match-set black_list dst -j REDIRECT --to-ports 3333
	# IP黑名单控制-gfwlist（走ss）
	iptables -t nat -A SHADOWSOCKS_GFW -p tcp -m set --match-set gfwlist dst -j REDIRECT --to-ports 3333
	#-----------------------FOR CHNMODE---------------------
	# 创建大陆白名单模式nat rule
	iptables -t nat -N SHADOWSOCKS_CHN
	# IP/CIDR/域名 黑名单控制（走ss）
	iptables -t nat -A SHADOWSOCKS_CHN -p tcp -m set --match-set black_list dst -j REDIRECT --to-ports 3333
	# cidr黑名单控制-chnroute（走ss）
	iptables -t nat -A SHADOWSOCKS_CHN -p tcp -m set ! --match-set chnroute dst -j REDIRECT --to-ports 3333
	#-----------------------FOR GAMEMODE---------------------
	# 创建游戏模式nat rule
	iptables -t nat -N SHADOWSOCKS_GAM
	# IP/CIDR/域名 黑名单控制（走ss）
	iptables -t nat -A SHADOWSOCKS_GAM -p tcp -m set --match-set black_list dst -j REDIRECT --to-ports 3333
	# cidr黑名单控制-chnroute（走ss）
	iptables -t nat -A SHADOWSOCKS_GAM -p tcp -m set ! --match-set chnroute dst -j REDIRECT --to-ports 3333
	#-----------------------FOR HOMEMODE---------------------
	# 创建回国模式nat rule
	 iptables -t nat -N SHADOWSOCKS_HOM
	# IP/CIDR/域名 黑名单控制（走ss）
	iptables -t nat -A SHADOWSOCKS_HOM -p tcp -m set --match-set black_list dst -j REDIRECT --to-ports 3333
	# cidr黑名单控制-chnroute（走ss）
	iptables -t nat -A SHADOWSOCKS_HOM -p tcp -m set --match-set chnroute dst -j REDIRECT --to-ports 3333

	[ "$mangle" == "1" ] && load_tproxy
	[ "$mangle" == "1" ] && ip rule add fwmark 0x07 table 310
	[ "$mangle" == "1" ] && ip route add local 0.0.0.0/0 dev lo table 310
	# 创建游戏模式udp rule
	[ "$mangle" == "1" ] && iptables -t mangle -N SHADOWSOCKS
	# IP/cidr/白域名 白名单控制（不走ss）
	[ "$mangle" == "1" ] && iptables -t mangle -A SHADOWSOCKS -p udp -m set --match-set white_list dst -j RETURN
	# 创建游戏模式udp rule
	[ "$mangle" == "1" ] && iptables -t mangle -N SHADOWSOCKS_GAM
	# IP/CIDR/域名 黑名单控制（走ss）
	[ "$mangle" == "1" ] && iptables -t mangle -A SHADOWSOCKS_GAM -p udp -m set --match-set black_list dst -j TPROXY --on-port 3333 --tproxy-mark 0x07
	# cidr黑名单控制-chnroute（走ss）
	[ "$mangle" == "1" ] && iptables -t mangle -A SHADOWSOCKS_GAM -p udp -m set ! --match-set chnroute dst -j TPROXY --on-port 3333 --tproxy-mark 0x07
	#-------------------------------------------------------
	# 局域网黑名单（不走ss）/局域网黑名单（走ss）
	lan_acess_control
	#-----------------------FOR ROUTER---------------------
	# router itself
	[ "$ss_basic_mode" != "6" ] && iptables -t nat -A OUTPUT -p tcp -m set --match-set router dst -j REDIRECT --to-ports 3333
	iptables -t nat -A OUTPUT -p tcp -m mark --mark "$ip_prefix_hex" -j SHADOWSOCKS_EXT
	
	# 把最后剩余流量重定向到相应模式的nat表中对应的主模式的链
	iptables -t nat -A SHADOWSOCKS -p tcp $(factor $ss_acl_default_port "-m multiport --dport") -j $(get_action_chain $ss_acl_default_mode)
	iptables -t nat -A SHADOWSOCKS_EXT -p tcp $(factor $ss_acl_default_port "-m multiport --dport") -j $(get_action_chain $ss_acl_default_mode)
	
	# 如果是主模式游戏模式，则把SHADOWSOCKS链中剩余udp流量转发给SHADOWSOCKS_GAM链
	# 如果主模式不是游戏模式，则不需要把SHADOWSOCKS链中剩余udp流量转发给SHADOWSOCKS_GAM，不然会造成其他模式主机的udp也走游戏模式
	###[ "$mangle" == "1" ] && ss_acl_default_mode=3
	[ "$ss_acl_default_mode" != "0" ] && [ "$ss_acl_default_mode" != "3" ] && ss_acl_default_mode=0
	[ "$ss_basic_mode" == "3" ] && iptables -t mangle -A SHADOWSOCKS -p udp -j $(get_action_chain $ss_acl_default_mode)
	# 重定所有流量到 SHADOWSOCKS
	KP_NU=`iptables -nvL PREROUTING -t nat |sed 1,2d | sed -n '/KOOLPROXY/='|head -n1`
	[ "$KP_NU" == "" ] && KP_NU=0
	INSET_NU=`expr "$KP_NU" + 1`
	iptables -t nat -I PREROUTING "$INSET_NU" -p tcp -j SHADOWSOCKS
	[ "$mangle" == "1" ] && iptables -t mangle -A PREROUTING -p udp -j SHADOWSOCKS
	# QOS开启的情况下
	QOSO=`iptables -t mangle -S | grep -o QOSO | wc -l`
	RRULE=`iptables -t mangle -S | grep "A QOSO" | head -n1 | grep RETURN`
	if [ "$QOSO" -gt "1" ] && [ -z "$RRULE" ];then
		iptables -t mangle -I QOSO0 -m mark --mark "$ip_prefix_hex" -j RETURN
	fi
}

chromecast(){
	chromecast_nu=`iptables -t nat -L PREROUTING -v -n --line-numbers|grep "dpt:53"|awk '{print $1}'`
	if [ "$ss_basic_dns_hijack" == "1" ];then
		if [ -z "$chromecast_nu" ]; then
			iptables -t nat -A PREROUTING -p udp -s $(get_lan_cidr) --dport 53 -j DNAT --to $lan_ipaddr >/dev/null 2>&1
			echo_date 开启DNS劫持功能功能，防止DNS污染...
		else
			echo_date DNS劫持规则已经添加，跳过~
		fi
	else
		echo_date DNS劫持功能未开启，建议开启！
	fi
}
# -----------------------------------nat part end--------------------------------------------------------

restart_dnsmasq(){
	# Restart dnsmasq
	echo_date 重启dnsmasq服务...
	service restart_dnsmasq >/dev/null 2>&1
}

load_module(){
	xt=`lsmod | grep xt_set`
	OS=$(uname -r)
	if [ -f /lib/modules/${OS}/kernel/net/netfilter/xt_set.ko ] && [ -z "$xt" ];then
		echo_date "加载xt_set.ko内核模块！"
		insmod /lib/modules/${OS}/kernel/net/netfilter/xt_set.ko
	fi
}

# write number into nvram with no commit
write_numbers(){
	nvram set update_ipset="$(cat /koolshare/ss/rules/version | sed -n 1p | sed 's/#/\n/g'| sed -n 1p)"
	nvram set update_chnroute="$(cat /koolshare/ss/rules/version | sed -n 2p | sed 's/#/\n/g'| sed -n 1p)"
	nvram set update_cdn="$(cat /koolshare/ss/rules/version | sed -n 4p | sed 's/#/\n/g'| sed -n 1p)"
	nvram set ipset_numbers=$(cat /koolshare/ss/rules/gfwlist.conf | grep -c ipset)
	nvram set chnroute_numbers=$(cat /koolshare/ss/rules/chnroute.txt | grep -c .)
	nvram set cdn_numbers=$(cat /koolshare/ss/rules/cdn.txt | grep -c .)
}

set_ulimit(){
	ulimit -n 16384
	echo 1 > /proc/sys/vm/overcommit_memory
}

remove_ss_reboot_job(){
	if [ -n "`cru l|grep ss_reboot`" ]; then
		echo_date 删除插件自动重启定时任务...
		#cru d ss_reboot >/dev/null 2>&1
		sed -i '/ss_reboot/d' /var/spool/cron/crontabs/* >/dev/null 2>&1
	fi
}

set_ss_reboot_job(){
	if [[ "${ss_reboot_check}" == "0" ]]; then
		remove_ss_reboot_job
	elif [[	"${ss_reboot_check}" ==	"1"	]];	then
		echo_date 设置每天${ss_basic_time_hour}时${ss_basic_time_min}分重启插件...
		cru	a ss_reboot	${ss_basic_time_min} ${ss_basic_time_hour}"	* *	* /koolshare/ss/ssconfig.sh	restart"
	elif [[	"${ss_reboot_check}" ==	"2"	]];	then
		echo_date 设置每周${ss_basic_week}的${ss_basic_time_hour}时${ss_basic_time_min}分重启插件...
		cru	a ss_reboot	${ss_basic_time_min} ${ss_basic_time_hour}"	* *	"${ss_basic_week}" /koolshare/ss/ssconfig.sh restart"
	elif [[	"${ss_reboot_check}" ==	"3"	]];	then
		echo_date 设置每月${ss_basic_day}日${ss_basic_time_hour}时${ss_basic_time_min}分重启插件...
		cru	a ss_reboot	${ss_basic_time_min} ${ss_basic_time_hour} ${ss_basic_day}"	* *	/koolshare/ss/ssconfig.sh restart"
	elif [[	"${ss_reboot_check}" ==	"4"	]];	then
		if [[ "${ss_basic_inter_pre}" == "1" ]]; then
			echo_date 设置每隔${ss_basic_inter_min}分钟重启插件...
			cru	a ss_reboot	"*/"${ss_basic_inter_min}" * * * * /koolshare/ss/ssconfig.sh restart"
		elif [[	"${ss_basic_inter_pre}"	== "2" ]]; then
			echo_date 设置每隔${ss_basic_inter_hour}小时重启插件...
			cru	a ss_reboot	"0 */"${ss_basic_inter_hour}" *	* *	/koolshare/ss/ssconfig.sh restart"
		elif [[	"${ss_basic_inter_pre}"	== "3" ]]; then
			echo_date 设置每隔${ss_basic_inter_day}天${ss_basic_inter_hour}小时${ss_basic_time_min}分钟重启插件...
			cru	a ss_reboot	${ss_basic_time_min} ${ss_basic_time_hour}"	*/"${ss_basic_inter_day} " * * /koolshare/ss/ssconfig.sh restart"
		fi
	elif [[	"${ss_reboot_check}" ==	"5"	]];	then
		check_custom_time=`dbus	get	ss_basic_custom	| base64_decode`
		echo_date 设置每天${check_custom_time}时的${ss_basic_time_min}分重启插件...
		cru	a ss_reboot	${ss_basic_time_min} ${check_custom_time}" * * * /koolshare/ss/ssconfig.sh restart"
	else
		remove_ss_reboot_job
	fi
}

remove_ss_trigger_job(){
	if [ -n "`cru l|grep ss_tri_check`" ]; then
		echo_date 删除插件触发重启定时任务...
		#cru d ss_tri_check >/dev/null 2>&1
		sed -i '/ss_tri_check/d' /var/spool/cron/crontabs/* >/dev/null 2>&1
	fi
}

set_ss_trigger_job(){
	if [ "$ss_basic_tri_reboot_time" == "0" ] || [ -z "$ss_basic_tri_reboot_time" ];then
		remove_ss_trigger_job
	else
		if [ "$ss_basic_tri_reboot_policy" == "1" ];then
			echo_date 设置每隔$ss_basic_tri_reboot_time分钟检查服务器IP地址，如果IP发生变化，则重启科学上网插件...
		else
			echo_date 设置每隔$ss_basic_tri_reboot_time分钟检查服务器IP地址，如果IP发生变化，则重启dnsmasq...
		fi
		cru d ss_tri_check  >/dev/null 2>&1
		cru a ss_tri_check "*/$ss_basic_tri_reboot_time * * * * /koolshare/scripts/ss_reboot_job.sh check_ip"
	fi
}

load_nat(){
	nat_ready=$(iptables -t nat -L PREROUTING -v -n --line-numbers|grep -v PREROUTING|grep -v destination)
	i=120
	until [ -n "$nat_ready" ]
	do
		i=$(($i-1))
		if [ "$i" -lt 1 ];then
			echo_date "错误：不能正确加载nat规则!"
			close_in_five
		fi
		sleep 1
		nat_ready=$(iptables -t nat -L PREROUTING -v -n --line-numbers|grep -v PREROUTING|grep -v destination)
	done
	echo_date "加载nat规则!"
	#create_ipset
	add_white_black_ip
	apply_nat_rules
	chromecast
}

ss_post_start(){
	# 在SS插件启动成功后触发脚本
	mkdir -p /koolshare/ss/postscripts && cd /koolshare/ss/postscripts
	for i in $(find ./ -name 'P*' | sort) ;
	do
		trap "" INT QUIT TSTP EXIT
		echo_date ------------- 【科学上网】 启动后触发脚本: $i -------------
		if [ -r "$i" ]; then
			$i start
		fi
		echo_date ----------------- 触发脚本: $i 运行完毕 -----------------
	done
}

ss_pre_stop(){
	# 在SS插件关闭前触发脚本
	mkdir -p /koolshare/ss/postscripts && cd /koolshare/ss/postscripts
	for i in $(find ./ -name 'P*' | sort -r) ;
	do
		trap "" INT QUIT TSTP EXIT
		echo_date ------------- 【科学上网】 关闭前触发脚本: $i ------------
		if [ -r "$i" ]; then
			$i stop
		fi
		echo_date ----------------- 触发脚本: $i 运行完毕 -----------------
	done
}

detect(){
	# 检测jffs2脚本是否开启，如果没有开启，将会影响插件的自启和DNS部分（dnsmasq.postconf）
	if [ "`nvram get jffs2_scripts`" != "1" ];then
		echo_date "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
		echo_date "+     发现你未开启Enable JFFS custom scripts and configs选项！     +"
		echo_date "+    【软件中心】和【科学上网】插件都需要此项开启才能正常使用！！         +"
		echo_date "+     请前往【系统管理】- 【系统设置】去开启，并重启路由器后重试！！      +"
		echo_date "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
		close_in_five
	fi
	
	# 检测是否在lan设置中是否自定义过dns,如果有给干掉
	if [ -n "`nvram get dhcp_dns1_x`" ];then
		nvram unset dhcp_dns1_x
		nvram commit
	fi
	if [ -n "`nvram get dhcp_dns2_x`" ];then
		nvram unset dhcp_dns2_x
		nvram commit
	fi
}

mount_dnsmasq(){
	killall dnsmasq >/dev/null 2>&1
	mount --bind /koolshare/bin/dnsmasq /usr/sbin/dnsmasq
	#service restart_dnsmasq >/dev/null 2>&
}

umount_dnsmasq(){
	killall dnsmasq >/dev/null 2>&1
	umount /usr/sbin/dnsmasq
}


mount_dnsmasq_now(){
	MOUNTED=`mount|grep -o dnsmasq`
	case $ss_basic_dnsmasq_fastlookup in
	0)
		if [ -n "$MOUNTED" ];then
			echo_date "【dnsmasq替换】：从dnsmasq-fastlookup切换为原版dnsmasq"
			umount_dnsmasq
		fi
		;;
	1|3)
		if [ -n "$MOUNTED" ];then
			echo_date "【dnsmasq替换】：dnsmasq-fastlookup已经替换过了！"
		else
			echo_date "【dnsmasq替换】：用dnsmasq-fastlookup替换原版dnsmasq！"
			mount_dnsmasq
		fi
		;;
	2)
		if [ -L "/jffs/configs/dnsmasq.d/cdn.conf" ];then
			if [ -z "$MOUNTED" ];then
				echo_date "【dnsmasq替换】：检测到cdn.conf，用dnsmasq-fastlookup替换原版dnsmasq！"
				mount_dnsmasq
			fi
		else
			if [ -n "$MOUNTED" ];then
				echo_date "【dnsmasq替换】：没有检测到cdn.conf，从dnsmasq-fastlookup切换为原版dnsmasq"
				umount_dnsmasq
			else
				echo_date "【dnsmasq替换】：没有检测到cdn.conf，不替换dnsmasq-fastlookup"
			fi
		fi
		;;
	esac
}

umount_dnsmasq_now(){
	MOUNTED=`mount|grep -o dnsmasq`
	case $ss_basic_dnsmasq_fastlookup in
	0|1|2)
		if [ -n "$MOUNTED" ];then
			echo_date "【dnsmasq替换】：从dnsmasq-fastlookup切换为原版dnsmasq"
			umount_dnsmasq
		fi
		;;
	3)
		if [ -n "$MOUNTED" ];then
			echo_date "【dnsmasq替换】：dnsmasq-fastlookup已经替换过了，插件关闭后保持替换！"
		else
			echo_date "【dnsmasq替换】：用dnsmasq-fastlookup替换原版dnsmasq！且插件关闭后保持替换！"
			mount_dnsmasq
		fi
		;;
	esac
}

disable_ss(){
	echo_date ======================= 梅林固件 - 【科学上网】 ========================
	echo_date
	echo_date ------------------------- 关闭【科学上网】 -----------------------------
	nvram set ss_mode=0
	dbus set dns2socks=0
	dbus remove ss_basic_server_ip
	nvram commit
	kill_process
	remove_ss_trigger_job
	remove_ss_reboot_job
	restore_conf
	umount_dnsmasq_now
	restart_dnsmasq
	flush_nat
	kill_cron_job
	echo_date ------------------------ 【科学上网】已关闭 ----------------------------
}

apply_ss(){
	# router is on boot
	WAN_ACTION=`ps|grep /jffs/scripts/wan-start|grep -v grep`
	# now stop first
	echo_date ======================= 梅林固件 - 【科学上网】 ========================
	echo_date
	echo_date ------------------------- 启动【科学上网】 -----------------------------
	ss_pre_stop
	nvram set ss_mode=0
	dbus set dns2socks=0
	nvram commit
	kill_process
	remove_ss_trigger_job
	remove_ss_reboot_job
	restore_conf
	# restart dnsmasq when ss server is not ip or on router boot
	restart_dnsmasq
	flush_nat
	kill_cron_job
	#echo_date ------------------------ 【科学上网】已关闭 ----------------------------
	# pre-start
	ss_pre_start
	# start
	#echo_date ------------------------- 启动 【科学上网】 ----------------------------
	detect
	resolv_server_ip
	load_module
	create_ipset
	create_dnsmasq_conf
	# do not re generate json on router start, use old one
	[ -z "$WAN_ACTION" ] && [ "$ss_basic_type" != "3" ] && [ "$ss_basic_type" != "4" ] && create_ss_json
	[ -z "$WAN_ACTION" ] && [ "$ss_basic_type" = "3" ] && create_v2ray_json
	[ -z "$WAN_ACTION" ] && [ "$ss_basic_type" = "4" -a "$ss_basic_trojan_binary" == "Trojan" ] && create_trojan_json
	[ -z "$WAN_ACTION" ] && [ "$ss_basic_type" = "4" -a "$ss_basic_trojan_binary" == "Trojan-Go" ] && create_trojango_json
	[ "$ss_basic_type" == "0" ] || [ "$ss_basic_type" == "1" ] && start_ss_redir
	[ "$ss_basic_type" == "2" ] && start_koolgame
	[ "$ss_basic_type" == "3" ] || [ "$ss_basic_type" == "4" -a "$ss_basic_trojan_binary" == "Trojan" ] && start_v2ray_xray
	[ "$ss_basic_type" == "4" -a "$ss_basic_trojan_binary" == "Trojan-Go" ] && start_trojango
	[ "$ss_basic_type" != "2" ] && start_kcp
	[ "$ss_basic_type" != "2" ] && start_dns
	#===load nat start===
	load_nat
	#===load nat end===
	mount_dnsmasq_now
	restart_dnsmasq
	auto_start
	write_cron_job
	set_ss_reboot_job
	set_ss_trigger_job
	# post-start
	ss_post_start
	echo_date ------------------------ 【科学上网】 启动完毕 ------------------------
}

# for debug
get_status(){
	echo_date 
	echo_date =========================================================
	echo_date "PID of this script: $$"
	echo_date "PPID of this script: $PPID"
	echo_date ========== 本脚本的PID ==========
	ps|grep $$|grep -v grep
	echo_date ========== 本脚本的PPID ==========
	ps|grep $PPID|grep -v grep
	echo_date ========== 所有运行中的shell ==========
	ps|grep "\.sh"|grep -v grep
	echo_date ------------------------------------

	WAN_ACTION=`ps|grep /jffs/scripts/wan-start|grep -v grep`
	NAT_ACTION=`ps|grep /jffs/scripts/nat-start|grep -v grep`
	WEB_ACTION=`ps|grep "ss_config.sh"|grep -v grep`
	[ -n "$WAN_ACTION" ] && echo_date 路由器开机触发koolss重启！
	[ -n "$NAT_ACTION" ] && echo_date 路由器防火墙触发koolss重启！
	[ -n "$WEB_ACTION" ] && echo_date WEB提交操作触发koolss重启！
	
	iptables -nvL PREROUTING -t nat
	iptables -nvL OUTPUT -t nat
	iptables -nvL SHADOWSOCKS -t nat
	iptables -nvL SHADOWSOCKS_EXT -t nat
	iptables -nvL SHADOWSOCKS_GFW -t nat
	iptables -nvL SHADOWSOCKS_CHN -t nat
	iptables -nvL SHADOWSOCKS_GAM -t nat
	iptables -nvL SHADOWSOCKS_GLO -t nat
}

# =========================================================================

case $ACTION in
start)
	set_lock
	if [ "$ss_basic_enable" == "1" ];then
		logger "[软件中心]: 启动科学上网插件！"
		set_ulimit >> "$LOG_FILE"
		apply_ss >> "$LOG_FILE"
		write_numbers >> "$LOG_FILE"
	else
		logger "[软件中心]: 科学上网插件未开启，不启动！"
	fi
	#get_status >> /tmp/ss_start.txt
	unset_lock
	;;
stop)
	set_lock
	ss_pre_stop
	disable_ss
	echo_date
	echo_date 你已经成功关闭shadowsocks服务~
	echo_date See you again!
	echo_date
	echo_date ======================= 梅林固件 - 【科学上网】 ========================
	#get_status >> /tmp/ss_start.txt
	unset_lock
	;;
restart)
	set_lock
	set_ulimit
	apply_ss
	write_numbers
	echo_date
	echo_date "Across the Great Wall we can reach every corner in the world!"
	echo_date
	echo_date ======================= 梅林固件 - 【科学上网】 ========================
	#get_status >> /tmp/ss_start.txt
	unset_lock
	;;
flush_nat)
	set_lock
	flush_nat
	unset_lock
	;;
*)
	set_lock
	if [ "$ss_basic_enable" == "1" ];then
		set_ulimit
		apply_ss
		write_numbers
	fi
	#get_status >> /tmp/ss_start.txt
	unset_lock
	;;
esac
