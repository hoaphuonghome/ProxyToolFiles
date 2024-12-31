#!/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
	ip64() {
		echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
	}
	echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}
Eth=$(ip addr show | grep -E '^2:' | sed 's/^[0-9]*: \(.*\):.*/\1/')
IP4=$(ip addr show "$Eth" | awk '/inet / {print $2}' | head -1 | cut -d '/' -f 1)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

# Lặp cho đến khi IP6 không còn trống
while [ -z "$IP6" ]; do
    # Restart network nếu IP6 trống
    if [ "$EUID" -ne 0 ]; then
        echo "Please run this script as root or with sudo."
        exit 1
    fi
    
    service network restart
    sleep 10 # Đợi 10 giây
    
    # Lấy IP6 sau khi khởi động lại mạng
    IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')
done

gen_data() {
	ipv6_list=()

    while IFS=":" read -r col1 col2 col3 col4; do
        ipv6="$(gen64 $IP6)"

        while [[ " ${ipv6_list[@]} " =~ " $ipv6 " ]]; do
            ipv6="$(gen64 $IP6)"
        done
        ipv6_list+=("$ipv6")

        echo "${col3}/${col4}/${col1}/${col2}/$ipv6"
    done < /root/proxy.txt
}
gen_proxy() {
    cat <<EOF
daemon
maxconn 2000
nserver 1.1.1.1
nserver 8.8.4.4
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456 
flush
auth strong

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})


$(awk -F "/" -v PASS="$PASS" '{
    auth = (PASS == 1 || $3 == $5) ? "strong" : "none";
    proxy_type = ($3 != $5) ? "-6" : "-4" ;
    print "auth " auth;
    print "allow  " $1;
    print "proxy " proxy_type " -n -a -p" $4 " -i" $3 " -e" $5;
    print "flush";
}' ${WORKDATA})
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" -v Eth="${Eth}" '{print "ifconfig " Eth " inet6 add " $5 "/64"}' ${WORKDATA} | sed '$d')
EOF
}


WORKDIR="/home/Lowji194"
WORKDATA="${WORKDIR}/data.txt"
# Kiểm tra xem file tồn tại hay không
if [ -e "${WORKDIR}/pass.txt" ]; then
    # Nếu file tồn tại, đọc giá trị từ file
    PASS=$(cat "${WORKDIR}/pass.txt")
else
    # Nếu file không tồn tại, gán giá trị mặc định là 1
    PASS=1
fi

if [ "$IP6" != "$(cat ${WORKDIR}/ip6.txt)" ]; then
    # Nếu khác nhau, thực hiện các thao tác dưới đây
    
echo "Gen Proxy"
gen_data >$WORKDIR/data.txt

echo "Config Proxy"
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
echo "$IP6" > "${WORKDIR}/ip6.txt"

echo "Boot Proxy"
bash /home/Lowji194/boot_ifconfig.sh 2>/dev/null

startProxy() {
  ulimit -n 1000048
  /usr/local/etc/LowjiConfig/bin/StartProxy /usr/local/etc/LowjiConfig/UserProxy.cfg
}

echo "Restart Proxy Services"
if pgrep StartProxy >/dev/null; then
  echo "LowjiProxy đang chạy, khởi động lại..."
  /usr/bin/kill $(pgrep StartProxy)
fi

echo "Start Proxy Services"
startProxy

# Vòng lặp kiểm tra StartProxy đã khởi động hay chưa
while true; do
  if pgrep StartProxy >/dev/null; then
    echo "StartProxy đã hoạt động."
    break  # Thoát khỏi vòng lặp nếu StartProxy đã khởi động
  else
    echo "StartProxy chưa hoạt động, thử khởi động lại..."
    startProxy
    sleep 5  # Chờ 5 giây trước khi kiểm tra lại
  fi
done

echo "Rotate IP Succces"
