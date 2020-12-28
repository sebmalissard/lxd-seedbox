#!/bin/bash -e

LXD_CONTAINER_NAME="seedbox"


debug()
{
    echo -e "DEBUG: $*"
}

info()
{
    echo -e "\e[1mINFO: $*\e[0m"
}

warning()
{
    echo -e "\e[1;93mWARNING: $*\e[0m"
}

# Replace the first argument by the second argument in a file (third argument)
substitute()
{
    if [ "$(lxc exec ${LXD_CONTAINER_NAME} -- grep -c "$1" "$3")" != "1" ]; then
        warning "'grep' command fail or invalid number of pattern match (expected only one match)."
    else
        lxc exec ${LXD_CONTAINER_NAME} -- sed "s|$1|$2|" -i "$3" \
            || warning "'sed' command fail."
    fi
}


info "Create and configure container ${LXD_CONTAINER_NAME}..."

lxc launch images:alpine/3.12 ${LXD_CONTAINER_NAME}
lxc config device add ${LXD_CONTAINER_NAME} port80 proxy listen=tcp:0.0.0.0:80 connect=tcp:127.0.0.1:80
lxc config set ${LXD_CONTAINER_NAME} raw.idmap "gid 3002 3002"

sleep 1


info "Setup group 'download'..."

lxc exec ${LXD_CONTAINER_NAME} -- addgroup -g 3002 -S download



info "Install packages..."

lxc exec ${LXD_CONTAINER_NAME} -- apk update
lxc exec ${LXD_CONTAINER_NAME} -- apk upgrade
lxc exec ${LXD_CONTAINER_NAME} -- apk add rtorrent nginx php7-fpm php7-session php7-json
# With rtorrent 0.98+, the rutorrent version 3.10 is required (by default rutorrent 3.9 is installed)  
lxc exec ${LXD_CONTAINER_NAME} -- apk add rutorrent=3.10-r0 --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community


info "Setup php-fdm..."

debug "Setup php-fpm7 unix socket"
substitute ";listen.group = nobody" "listen.group = www-data" "/etc/php7/php-fpm.d/www.conf"
substitute "listen = 127.0.0.1:9000" "listen = /run/php-fpm.sock" "/etc/php7/php-fpm.d/www.conf"
substitute "group = nobody" "group = rutorrent" "/etc/php7/php-fpm.d/www.conf"

debug "Add php-fpm7 openrc service"
lxc exec ${LXD_CONTAINER_NAME} -- rc-update add php-fpm7 default
lxc exec ${LXD_CONTAINER_NAME} -- rc-service php-fpm7 start


info "Setup rtorrent..."

debug "Create rtorrent user and group"
lxc exec ${LXD_CONTAINER_NAME} -- addgroup -S rtorrent
lxc exec ${LXD_CONTAINER_NAME} -- adduser -S -D -g rtorrent -h /home/rtorrent -G rtorrent rtorrent
lxc exec ${LXD_CONTAINER_NAME} -- adduser rtorrent download

debug "Setup rtorrent log directory"
lxc exec ${LXD_CONTAINER_NAME} -- mkdir /var/log/rtorrent
lxc exec ${LXD_CONTAINER_NAME} -- chown rtorrent:rtorrent /var/log/rtorrent

debug "Setup rtorrent home directory"
lxc file push -r -v overlay/home/rtorrent ${LXD_CONTAINER_NAME}/home/
lxc exec ${LXD_CONTAINER_NAME} -- chown -R rtorrent:rtorrent /home/rtorrent/

debug "Add rtorrent openrc service"
lxc file push -v overlay/etc/init.d/rtorrent ${LXD_CONTAINER_NAME}/etc/init.d/rtorrent
lxc exec ${LXD_CONTAINER_NAME} -- chown root:root /etc/init.d/rtorrent
lxc exec ${LXD_CONTAINER_NAME} -- rc-update add rtorrent default
lxc exec ${LXD_CONTAINER_NAME} -- rc-service rtorrent start


info "Setup rutorrent..."
substitute "// \$scgi_port = 0;" "\$scgi_port = 0;" "/usr/share/webapps/rutorrent/conf/config.php"
substitute "// \$scgi_host = \"unix:///tmp/rpc.socket\";" "\$scgi_host = \"unix:///run/rtorrent/rtorrent-rpc.sock\";" "/usr/share/webapps/rutorrent/conf/config.php"
lxc exec ${LXD_CONTAINER_NAME} -- chown -R rtorrent /usr/share/webapps/rutorrent/share


info "Setup nginx..."

debug "Setup seedbox server"
lxc file push -v overlay/etc/nginx/conf.d/seedbox.conf ${LXD_CONTAINER_NAME}/etc/nginx/conf.d/seedbox.conf
lxc exec ${LXD_CONTAINER_NAME} -- rm /etc/nginx/conf.d/default.conf

debug "Add nginx openrc service"
lxc exec ${LXD_CONTAINER_NAME} -- rc-update add nginx default
lxc exec ${LXD_CONTAINER_NAME} -- rc-service nginx start


info "Mount raid 'Download' directory..."
lxc config device add ${LXD_CONTAINER_NAME} download disk source=/media/raid/Download path=/home/rtorrent/download/


info "Reboot container ${LXD_CONTAINER_NAME}..."
lxc exec ${LXD_CONTAINER_NAME} -- reboot
