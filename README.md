This repository contains a script to setup a [naiveproxy][1] on your
own server. You also need a domain name with DNS already setup to
point to your server's IP address.

In order to use the script, you need to set two environment variables:

 - `PASSWORD`: The password to use with the proxy. The username will
   always be `mahsa`.
 - `DOMAIN`: should be your domain name (like `example.org`).

You can run the script remotely like this, replacing the values for
`PASSWORD` and `DOMAIN`, and also user and server ip address,
accordingly.

    curl -L https://grimpen.one/naive.sh | ssh [user@]<server-ip> -- PASSWORD=<...> DOMAIN=<...> sh
