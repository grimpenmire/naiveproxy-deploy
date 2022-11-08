#!/bin/bash

set -e

if [ -z "$PASSWORD" ]; then
    echo "PASSWORD environment variable not set (to be used for HTTP basic auth)."
    exit 1
fi

if [ -z "$DOMAIN" ]; then
    echo "DOMAIN environment variable not set."
    exit 1
fi

SSL_EMAIL="${VARIABLE:-mahsa@${DOMAIN}}"

apt install -y tinyproxy haproxy nginx nftables

# Setup firewall

systemctl enable nftables
systemctl start nftables

# accept related traffic, internal traffic, and ping requests
nft flush table filter  # clear before adding; useful mostly for tests where we run this many times
nft add rule inet filter input ct state related,established counter accept
nft add rule inet filter input iif lo counter accept
nft add rule inet filter input ip protocol icmp icmp type echo-request counter accept
nft add rule inet filter input ip6 nexthdr icmpv6 icmpv6 type echo-request counter accept

# open ports 22, 80, and 443
nft add rule inet filter input tcp dport 22 counter accept
nft add rule inet filter input tcp dport { http, https } counter accept

# drop everything else
nft add rule inet filter input counter drop

# save
nft list ruleset > /etc/nftables.conf

# Enable BBR congestion control. I'm still not completely convinced
# about this. But it looks like it could be good.

cat >> /etc/sysctl.d/50-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl -p /etc/sysctl.d/50-bbr.conf

# Setup acme

git clone https://github.com/Neilpang/acme.sh.git
cd ./acme.sh
./acme.sh --install
cd ..

rm -rf acme.sh
shopt -s expand_aliases
export LE_WORKING_DIR=~/.acme.sh
alias acme.sh=~/.acme.sh/acme.sh

# Setup a sample blog to camouflage as a normal website

curl -L https://github.com/arcdetri/sample-blog/archive/master.tar.gz | tar -C /tmp -zxf -
mv /tmp/sample-blog-master/html/* /var/www/html

# Obtain certificates

acme.sh --register-account -m ${SSL_EMAIL}

RENEW_SKIP=2
ret=0
acme.sh -k ec-256 -d ${DOMAIN} --issue -w /var/www/html || ret=$?
[ "$ret" != "$RENEW_SKIP" ] && [ "$ret" != "0" ] && exit 1;
ret=0
acme.sh -k 2048 -d ${DOMAIN} --issue -w /var/www/html || ret=$?
[ "$ret" != "$RENEW_SKIP" ] && [ "$ret" != "0" ] && exit 1;

# Install certificates for use by haproxy, and setup crontabs for
# renewing them
mkdir -p /etc/haproxy/certs
acme.sh --install-cert --ecc -d ${DOMAIN} --key-file /tmp/${DOMAIN}.key --fullchain-file /tmp/${DOMAIN}.crt --reloadcmd "cat /tmp/${DOMAIN}.* >/etc/haproxy/certs/${DOMAIN}.pem.ecdsa; rm /tmp/${DOMAIN}.*; systemctl restart haproxy"
acme.sh --install-cert -d ${DOMAIN} --key-file /tmp/${DOMAIN}.key --fullchain-file /tmp/${DOMAIN}.crt --reloadcmd "cat /tmp/${DOMAIN}.* >/etc/haproxy/certs/${DOMAIN}.pem.rsa; rm /tmp/${DOMAIN}.*; systemctl restart haproxy"

# Configure tinyproxy (forward proxy) and haproxy (reverse proxy)

cat >/etc/tinyproxy/tinyproxy.conf <<EOF
User tinyproxy
Group tinyproxy
PidFile "/run/tinyproxy/tinyproxy.pid"
MaxClients 100
MinSpareServers 5
MaxSpareServers 20
StartServers 10
Port 8888

Listen 127.0.0.1
LogFile "/dev/null"
DisableViaHeader Yes
EOF

cat >/etc/haproxy/haproxy.cfg <<EOF
userlist users
        user mahsa insecure-password ${PASSWORD}

global
        log stdout local0 debug

defaults
        mode http
        log global
        option httplog
        timeout connect 5s
        timeout client 30s
        timeout server 30s

frontend haproxy_tls
        bind :443 ssl crt /etc/haproxy/certs/ alpn h2,http/1.1
        option http-use-proxy-header
        acl login base_dom login-key.test
        acl auth_ok http_auth(users)
        http-request auth realm proxyserver if login !auth_ok
        http-request redirect location https://google.com if login auth_ok
        use_backend proxy if auth_ok
        default_backend masquerade

backend proxy
        mode http
        http-request del-header proxy-authorization
        server proxy 127.0.0.1:8888

backend masquerade
        mode http
        server nginx 127.0.0.1:80
EOF

echo "Restarting tinyproxy and haproxy..."
systemctl restart tinyproxy haproxy

echo "Done."