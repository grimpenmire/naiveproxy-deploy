#!/bin/sh

set -e

if [ -z "$PASSWORD" ]; then
    echo "PASSWORD environment variable not set (to be used for HTTP basic auth)."
    exit 1
fi

if [ -z "$DOMAIN" ]; then
    echo "DOMAIN environment variable not set."
    exit 1
fi

SSL_EMAIL="${SSL_EMAIL:-mahsa@${DOMAIN}}"

# Install packages

apt install -y nftables

# Download a sample blog to camouflage as a normal website

curl -L https://github.com/arcdetri/sample-blog/archive/master.tar.gz | tar -C /tmp -zxf -
mkdir -p /var/www/html
mv /tmp/sample-blog-master/html/* /var/www/html

# Install golang

curl -L https://go.dev/dl/go1.19.3.linux-amd64.tar.gz -o golang.tar.gz
rm -rf /usr/local/go
tar -C /usr/local -xzf golang.tar.gz
rm golang.tar.gz
export PATH=$PATH:/usr/local/go/bin
echo 'export PATH=$PATH:/usr/local/go/bin'>>~/.bashrc

# Build and install Caddy + ForwardProxy

go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/sagernet/forwardproxy@latest
install ./caddy /usr/local/bin/caddy
rm ./caddy

mkdir -p /etc/caddy
cat >/etc/caddy/Caddyfile <<EOF
{
  order forward_proxy before file_server
}
:443, ${DOMAIN} {
  tls ${SSL_EMAIL}
  forward_proxy {
    basic_auth mahsa ${PASSWORD}
    hide_ip
    hide_via
    probe_resistance
  }
  file_server {
    root /var/www/html
  }
}
EOF

# Create a systemd service for caddy

groupadd --system caddy || true
useradd --system \
    --gid caddy \
    --create-home \
    --home-dir /var/lib/caddy \
    --shell /usr/sbin/nologin \
    --comment "Caddy web server" \
    caddy || true

cat >/etc/systemd/system/caddy.service <<EOF
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
User=caddy
Group=caddy
ExecStart=/usr/local/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# Setup firewall

systemctl enable nftables
systemctl start nftables

# accept related traffic, internal traffic, and ping requests
nft flush table inet filter  # clear before adding; useful mostly for tests where we run this many times
nft add table filter
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

cat >/etc/sysctl.d/50-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl -p /etc/sysctl.d/50-bbr.conf

# Enable and start services

systemctl daemon-reload
systemctl enable caddy
systemctl start caddy

echo
echo "Config URL: naive+https://mahsa:${PASSWORD}@${DOMAIN}:443?udp-over-tcp=true"
echo
echo 'JSON Config:'
echo '{'
echo '    "listen": "socks://127.0.0.1:1080",'
echo "    \"proxy\": \"https://mahsa:${PASSWORD}@${DOMAIN}:443\","
echo '    "log": ""'
echo '}'
echo

echo "Done."
