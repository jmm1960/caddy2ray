#!/bin/sh
SOURCE="$0"
while [ -h "$SOURCE"  ]; do
    DIR="$( cd -P "$( dirname "$SOURCE"  )" && pwd  )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /*  ]] && SOURCE="$DIR/$SOURCE"
done
DIR="$( cd -P "$( dirname "$SOURCE"  )" && pwd  )"

cd $DIR

if [ -z $DOMAIN ];then
    echo "未设置环境变量-DOMAIN"
    exit 2
fi

if [ -z $ALIAS ];then
    ALIAS="$DOMAIN"
fi

CADDY_HTTP_TEMPLATE="/conf/caddy/http.Caddyfile"
CADDY_HTTPS_TEMPLATE="/conf/caddy/https.Caddyfile"
V2RAY_DEFAULT_CONFIG="/conf/v2ray/default_config.json"
V2RAY_DEFAULT_CLIENT="/conf/v2ray/default_client.json"

CADDYFILE_PATH="/etc/caddy/Caddyfile"
V2RAY_CONFIG="/etc/v2ray/config.json"
V2RAY_CLIENT="/etc/v2ray/client.json"
PORT=443
if [ -z $EMAIL ];then
    PORT=80
fi

V2RAY_CLIENT_HOST=""
if [ -e "$V2RAY_CLIENT" ]; then
    V2RAY_CLIENT_HOST=$(jq -r '.host' "$V2RAY_CLIENT")
fi

# 初始情况 或者 域名变更
if [ ! -e "$CADDYFILE_PATH" ] || [ "$V2RAY_CLIENT_HOST" != "$DOMAIN" ]; then
    WS_PATH="`echo $RANDOM | md5sum | cut -c 3-11`"
    WS_PORT=$(($RANDOM+1234))
    UUID=$(uuidgen)

    if [ -z $EMAIL ];then
        cp -f $CADDY_HTTP_TEMPLATE $CADDYFILE_PATH
    else
        cp -f $CADDY_HTTPS_TEMPLATE $CADDYFILE_PATH
    fi
    
    sed -i "s/example.domain/${DOMAIN}/" $CADDYFILE_PATH
    sed -i "s/ws_path/${WS_PATH}/" $CADDYFILE_PATH
    sed -i "s/1234/${WS_PORT}/" $CADDYFILE_PATH
    sed -i "s/your@email.com/${EMAIL}/" $CADDYFILE_PATH

    /usr/bin/caddy fmt --overwrite $CADDYFILE_PATH

    cp -f $V2RAY_DEFAULT_CONFIG $V2RAY_CONFIG
    sed -i "s/1234/${WS_PORT}/" $V2RAY_CONFIG
    sed -i "s/uuid/${UUID}/" $V2RAY_CONFIG
    sed -i "s/ws_path/${WS_PATH}/" $V2RAY_CONFIG

    cp -f $V2RAY_DEFAULT_CLIENT $V2RAY_CLIENT
    sed -i "s/hostname-placeholder/${DOMAIN}/" $V2RAY_CLIENT
    sed -i "s/address-placeholder/${DOMAIN}/" $V2RAY_CLIENT
    sed -i "s/ps-placeholder/${ALIAS}/" $V2RAY_CLIENT
    sed -i "s/uuid-placeholder/${UUID}/" $V2RAY_CLIENT
    sed -i "s/ws_path-placeholder/${WS_PATH}/" $V2RAY_CLIENT
fi

echo "====================================="
echo "V2ray 配置信息"
echo "地址（address）: $(jq -r '.host' $V2RAY_CLIENT)"
echo "端口（port）： ${PORT}"
echo "用户id（UUID）： $(jq -r '.id' $V2RAY_CLIENT)"
echo "加密方式（security）： 自适应"
echo "传输协议（network）： ws"
echo "伪装类型（type）： none"
echo "路径（不要落下/）： $(jq -r '.path' $V2RAY_CLIENT)"
echo "底层传输安全： tls"
echo "====================================="

clientBase64="`cat $V2RAY_CLIENT | base64 -w 0`"
echo "=========复制以下内容进行导入=========="
echo "vmess://"$clientBase64
echo "=========复制以上内容进行导入=========="

start-stop-daemon --start \
	-b -1 /var/log/v2ray.log -2 /var/log/v2ray.log \
	-m -p /run/v2ray.pid \
	--exec /usr/bin/v2ray -- run -c $V2RAY_CONFIG 

/usr/bin/caddy run --config $CADDYFILE_PATH --adapter caddyfile