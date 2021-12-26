#!/bin/bash

# 使用说明：加在 openwrt 上系统 计划任务里 添加定时运行，如 0 4 * * 2,4,6 bash /root/cf-auto-passwall.sh > /dev/null
# 0 4 * * 2,4,6 的意思是在每周二、周四、周六的凌晨4点会自动运行一次。/root/cf-auto-passwall.sh 是你脚本的绝对地址

#########################################注意注意注意注意注意############################################

# 1、请在脚本中修改你期望优选 IP 的带宽大小（默认5M）

# 2、请更改 422 行 的 xxxxxxxxxx 字符串，为你自己 PassWall 的节点值（不会请看视频教程或是博客）

######################################################################################################
blue(){
    echo -e "\033[34m\033[01m$1\033[0m"
}
green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}
red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}
clear
green "=========================================================="
 blue "用途：用于自动筛选 CF IP，并自动替换优选 IP 为 PassWall 的节点地址"
 blue "网站： www.v2rayssr.com （已开启禁止国内访问）"
 blue "YouTube频道：波仔分享"
 blue "本脚本感谢 GitHub：Lbingyi 以及 Paniy"
 blue "本教程视频演示地址：https://youtu.be/WzRHi9f9QKg"
green "=========================================================="
green "=========================================================="
 red  "请在脚本中修改你期望优选 IP 的带宽大小（默认5M）脚本自动运行中....."
 red  "脚本第44行 bandwidth 后面的数值为期望优选带宽大小（ Mbps ）  "
green "=================脚本正在运行中.....======================="
sleep 8s
/etc/init.d/haproxy stop
/etc/init.d/passwall stop
version=20211226

function bettercloudflareip (){
declare -i bandwidth
declare -i speed
#read -p "请设置期望的带宽大小(默认0,单位 Mbps):" bandwidth
bandwidth=50
#read -p "请设置RTT测试进程数(默认25,最大50):" tasknum
tasknum=50
if [ -z "$tasknum" ]
then
	tasknum=25
fi
if [ $tasknum -eq 0 ]
then
	echo 进程数不能为0,自动设置为默认值
	tasknum=25
fi
if [ $tasknum -gt 50 ]
then
	echo 超过最大进程限制,自动设置为最大值
	tasknum=50
fi
speed=bandwidth*128*1024
starttime=$(date +'%Y-%m-%d %H:%M:%S')
cloudflaretest
declare -i realbandwidth
realbandwidth=max/128
endtime=$(date +'%Y-%m-%d %H:%M:%S')
start_seconds=$(date --date="$starttime" +%s)
end_seconds=$(date --date="$endtime" +%s)
clear
curl --$ips --resolve service.anycast.eu.org:443:$anycast --retry 3 -s -X POST https://service.anycast.eu.org -o temp.txt
publicip=$(grep publicip= temp.txt | cut -f 2- -d'=')
colo=$(grep colo= temp.txt | cut -f 2- -d'=')
rm -rf temp.txt
echo $anycast>$ips.txt
echo 优选IP $anycast
echo 公网IP $publicip
echo 自治域 AS$asn
echo 经纬度 $longitude,$latitude
echo META城市 $city
echo 设置带宽 $bandwidth Mbps
echo 实测带宽 $realbandwidth Mbps
echo 峰值速度 $max kB/s
echo 往返延迟 $avgms 毫秒
echo 数据中心 $colo
echo 总计用时 $((end_seconds-start_seconds)) 秒
}

function rtt (){
declare -i avgms
declare -i getrtt
t=1
n=1
for ip in `cat rtt/$1.txt`
do
	while true
	do
		if [ $t -le 5 ]
		then
			curl --resolve www.cloudflare.com:443:$ip https://www.cloudflare.com/cdn-cgi/trace -o /dev/null -s --connect-timeout 1 -w "$ip"_%{time_connect}_"HTTP"%{http_code}"\n">>rtt/$1-$n.log
			t=$[$t+1]
		else
			ipaddr=$(cat rtt/$1-$n.log | awk 'NR==1' | awk -F_ '{print $1}')
			getrtt=$(grep HTTP200 rtt/$1-$n.log | wc -l)
			if [ $getrtt == 0 ]
			then
				rm -rf rtt/$1-$n.log
				n=$[$n+1]
				t=1
				break
			fi
			avgms=0
			for i in `grep HTTP200 rtt/$1-$n.log | awk -F_ '{printf ("%d\n",$2*1000000)}'`
			do
				avgms=$i+avgms
			done
			avgms=(avgms/getrtt)/1000
			getrtt=5-getrtt
			if [ $avgms -lt 10 ]
			then
				echo $getrtt 00$avgms $ipaddr>rtt/$1-$n.log
			elif [ $avgms -ge 10 ] && [ $avgms -lt 100 ]
			then
				echo $getrtt 0$avgms $ipaddr>rtt/$1-$n.log
			else
				echo $getrtt $avgms $ipaddr>rtt/$1-$n.log
			fi
			n=$[$n+1]
			t=1
			break
		fi
	done
done
rm -rf rtt/$1.txt
}

function speedtest (){
curl --resolve $domain:443:$1 https://$domain/$file -o /dev/null --connect-timeout 5 --max-time 10 > log.txt 2>&1
cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep -v 'k\|M' >> speed.txt
for i in `cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep k | sed 's/k//g'`
do
	declare -i k
	k=$i
	k=k*1024
	echo $k >> speed.txt
done
for i in `cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep M | sed 's/M//g'`
do
	i=$(echo | awk '{print '$i'*10 }')
	declare -i M
	M=$i
	M=M*1024*1024/10
	echo $M >> speed.txt
done
declare -i max
max=0
for i in `cat speed.txt`
do
	if [ $i -ge $max ]
	then
		max=$i
	fi
done
rm -rf log.txt speed.txt
echo $max
}

function cloudflaretest (){
while true
do
	while true
	do
		declare -i ipnum
		declare -i iplist
		declare -i n
		rm -rf rtt data.txt meta.txt log.txt anycast.txt temp.txt speed.txt
		mkdir rtt
		if [ ! -f "$ips.txt" ]
		then
			echo DNS防污染解析
			curl --$ips -v --retry 3 -s https://speed.cloudflare.com/cdn-cgi/trace>data.txt 2>&1
			grep Connected data.txt | awk -F'(' '{print $2}' | awk -F')' '{print $1}'>$ips.txt
		fi
		echo 指向解析获取CF节点IP
		echo 如果长时间无法获取CF节点IP,重新运行程序并选择清空缓存
		resolveip=$(cat $ips.txt)
		curl --$ips --resolve speed.cloudflare.com:443:$resolveip --retry 3 -s https://speed.cloudflare.com/meta | sed -e 's/{//g' -e 's/}//g' -e 's/"//g' -e 's/,/\n/g'>meta.txt
		asn=$(grep asn: meta.txt | awk -F: '{print $2}')
		city=$(grep city: meta.txt | awk -F: '{print $2}')
		latitude=$(grep latitude: meta.txt | awk -F: '{print $2}')
		longitude=$(grep longitude: meta.txt | awk -F: '{print $2}')
		curl --$ips --resolve service.anycast.eu.org:443:$resolveip --retry 3 https://service.anycast.eu.org -o data.txt -#
		domain=$(grep domain= data.txt | cut -f 2- -d'=')
		file=$(grep file= data.txt | cut -f 2- -d'=')
		url=$(grep url= data.txt | cut -f 2- -d'=')
		app=$(grep app= data.txt | cut -f 2- -d'=')
		if [ "$app" != "$version" ]
		then
			echo 发现新版本程序: $app
			echo 更新地址: $url
			echo 更新后才可以使用
			exit
		fi
		if [ $selfmode == 1 ]
		then
			rm -rf data.txt
			n=0
			while true
			do
				if [ $n == 256 ]
				then
					break
				else
					echo $selfip.$n>>anycast.txt
					n=n+1
				fi
			done
		else
			for i in `cat data.txt | sed '1,4d'`
			do
				echo $i>>anycast.txt
			done
		fi
		rm -rf meta.txt data.txt
		ipnum=$(cat anycast.txt | wc -l)
		if [ $ipnum -lt $tasknum ]
		then
			tasknum=ipnum
		fi
		iplist=ipnum/tasknum
		declare -i a=1
		declare -i b=1
		for i in `cat anycast.txt`
		do
			echo $i>>rtt/$b.txt
			if [ $a == $iplist ]
			then
				a=1
				b=b+1
			else
				a=a+1
			fi
		done
		rm -rf anycast.txt
		if [ $a != 1 ]
		then
			a=1
			b=b+1
		fi
		while true
		do
			if [ $a == $b ]
			then
				break				
			else
				rtt $a &
			fi
			a=a+1
		done
		while true
		do
			sleep 2
			n=$(ls rtt | grep txt | grep -v "grep" | wc -l)
			if [ $n -ne 0 ]
			then
				echo 等待RTT测试结束,剩余进程数 $n
			else
				echo RTT测试完成
				break
			fi
		done
		n=$(ls rtt | wc -l)
		if [ $n -ge 5 ]
		then
			cat rtt/*.log | sort | awk '{print $2"_"$3}'>ip.txt
			echo 待测速的IP地址
			echo $(sed -n '1p' ip.txt | awk -F_ '{print "第1个IP "$2" 往返延迟 "$1" 毫秒"}')
			echo $(sed -n '2p' ip.txt | awk -F_ '{print "第2个IP "$2" 往返延迟 "$1" 毫秒"}')
			echo $(sed -n '3p' ip.txt | awk -F_ '{print "第3个IP "$2" 往返延迟 "$1" 毫秒"}')
			echo $(sed -n '4p' ip.txt | awk -F_ '{print "第4个IP "$2" 往返延迟 "$1" 毫秒"}')
			echo $(sed -n '5p' ip.txt | awk -F_ '{print "第5个IP "$2" 往返延迟 "$1" 毫秒"}')
			n=0
			for ip in `cat ip.txt`
			do
				if [ $n == 5 ]
				then
					echo 没有满足速度要求的IP
					break
				else
					n=n+1
				fi
				avgms=$(echo $ip | awk -F_ '{print $1}')
				ip=$(echo $ip | awk -F_ '{print $2}')
				echo 正在测试 $ip
				max=$(speedtest $ip)
				if [ $max -ge $speed ]
				then
					anycast=$ip
					max=$[$max/1024]
					echo $ip 峰值速度 $max kB/s
					break
				else
				max=$[$max/1024]
				echo $ip 峰值速度 $max kB/s
				fi
			done
			rm -rf rtt ip.txt
			if [ $n != 5 ]
			then
				break
			fi
		else
			echo 当前所有IP都存在RTT丢包
			tasknum=10
		fi
	done
		break
done
}

function singletest (){
read -p "请输入需要测速的IP: " testip
curl --resolve service.anycast.eu.org:443:$testip https://service.anycast.eu.org -o temp.txt -#
domain=$(grep domain= temp.txt | cut -f 2- -d'=')
file=$(grep file= temp.txt | cut -f 2- -d'=')
rm -rf temp.txt
curl --resolve $domain:443:$testip https://$domain/$file -o /dev/null --connect-timeout 5 --max-time 15
}


while true
do
		rm -rf ipv4.txt ipv6.txt rtt data.txt meta.txt log.txt anycast.txt temp.txt speed.txt icmp ip.txt meta.txt
		ips=ipv4
		selfmode=0
		bettercloudflareip
		break
done
	uci set passwall.xxxxxxxxxx.address=$anycast
	uci commit passwall
	/etc/init.d/haproxy restart
	/etc/init.d/passwall restart
	exit
