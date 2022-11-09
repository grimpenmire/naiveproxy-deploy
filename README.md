# Deploying to server

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

When done, the script prints out a config url and a json config to be
used in your client of your choice.

# Clients

On Android you can use the [SagerNet][2] client. If you manually setup
the client, do not forget to enable UDP over TCP (if you need
voice/video calls to work, or anything else requiring UDP).

On Linux, you can put the json config printed by the script in the
config.json file required by the client.

[1]: https://github.com/klzgrad/naiveproxy
[2]: https://sagernet.org/
