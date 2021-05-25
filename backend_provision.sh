#!/bin/bash

# DEBUG ONLY
sudo yum -y install vim > /dev/null

# 1st parameter - URL
# 2nd parameter - resource name; name of folder in extract path
# 3rd parameter - dir to extract
function download_and_extract_tar_gz() {
	DOWNLOAD_URL=$1
	NAME="$2"
	EXTRACT_DIR="$3"
	
	# if dir = /tmp/ and name = some_name then extract_path = /tmp/some_name
	EXTRACT_PATH="${3%/}/${2}"
	
	echo "Downloading ${DOWNLOAD_URL}..."
	curl --silent -L $DOWNLOAD_URL > "${DOWNLOAD_DIR}${NAME}.tar.gz"

	echo "Extracting ${NAME}..."
	mkdir --parents "${EXTRACT_PATH}"
	# we need 'strip-components' because tar extract filename can be different from expected
	# so we just create new directory & remove first from tar
	tar zxf "${DOWNLOAD_DIR}${NAME}.tar.gz" -C "$EXTRACT_PATH" --strip-components=1
}

# 1st script parameter - what number of this server (1st or 2nd)
# 2nd script parameter - workstation (host) machine IP (need it to allow /status)
echo "backend$1 server provision start..."

# some global variables
WORK_DIR="/home/vagrant/"
DOWNLOAD_DIR="/tmp/"

mkdir --parents "$WORK_DIR" "$DOWNLOAD_DIR"

echo "Installing gcc, git and httpd-utils..."
sudo yum install -y gcc gcc-c++ git httpd-tools > /dev/null

echo "Installing NGINX with yum..."
sudo yum install -y nginx > /dev/null
cp /usr/lib/systemd/system/nginx.service /tmp
echo "Uninstalling NGINX with yum..."
sudo yum remove -y nginx > /dev/null

# downloading & extracting NGINX
NGINX_URL="http://nginx.org/download/nginx-1.20.0.tar.gz"
NGINX_NAME="nginx-1.20.0"
download_and_extract_tar_gz $NGINX_URL "$NGINX_NAME" "$WORK_DIR"

# downloading & extracting NGINX-MODULE-VTS
VTS_URL="https://github.com/vozlt/nginx-module-vts/archive/refs/tags/v0.1.18.tar.gz"
VTS_NAME="nginx-module-vts-0.1.18"
download_and_extract_tar_gz $VTS_URL "$VTS_NAME" "$WORK_DIR"

# downloading & extracting PCRE
PCRE_URL="https://sourceforge.net/projects/pcre/files/pcre/8.44/pcre-8.44.tar.gz/download"
PCRE_NAME="pcre-8.44"
download_and_extract_tar_gz $PCRE_URL "$PCRE_NAME" "$WORK_DIR"

# downloading & extracting OpenSSL
OPEN_SSL_URL="https://github.com/openssl/openssl/archive/refs/tags/OpenSSL_1_0_2u.tar.gz"
OPEN_SSL_NAME="openSSL-1.0.2u"
download_and_extract_tar_gz $OPEN_SSL_URL "$OPEN_SSL_NAME" "$WORK_DIR"

# some variables for ./configure 
INSTALL_PATH="/home/vagrant/nginx/"
# ---------------------------but it is all default???
BINARY_FILE_PATH="${INSTALL_PATH%/}/sbin/nginx" 
CONFIG_FILE_PATH="${INSTALL_PATH%/}/conf/nginx.conf"
ERROR_LOG_PATH="${INSTALL_PATH%/}/logs/error.log"
ACCESS_LOG_PATH="${INSTALL_PATH%/}/logs/access.log"
PID_FILE_PATH="${INSTALL_PATH%/}/logs/nginx.pid"
# ---------------------------

VTS_PATH="${WORK_DIR}${VTS_NAME}"
PCRE_PATH="${WORK_DIR}${PCRE_NAME}"
OPEN_SSL_PATH="${WORK_DIR}${OPEN_SSL_NAME}"

echo "Configuring NGINX..."
( cd "${WORK_DIR}${NGINX_NAME}"; ./configure --prefix="${INSTALL_PATH%/}" --with-http_ssl_module --with-http_realip_module --without-http_gzip_module --add-module="$VTS_PATH" --with-pcre="$PCRE_PATH" --with-openssl="$OPEN_SSL_PATH" > /dev/null )
echo "Installing NGINX..."
( cd "${WORK_DIR}${NGINX_NAME}" && make > /dev/null && make install )

USER_NAME="vagrant"
GROUP_NAME="vagrant"
# modify unit file from 'yum install..' according to the task
echo "Creating nginx.service..."
sed -i 's,^\(\[Service\]\),\1\nUser='"$USER_NAME"'\nGroup='"$USER_NAME"',' /tmp/nginx.service
sed -i 's,/run/nginx.pid,'"$PID_FILE_PATH"',' /tmp/nginx.service
sed -i 's,/usr/\(sbin/nginx\),'"$INSTALL_PATH"'\1,' /tmp/nginx.service
# move it to other systemd files...
sudo mv /tmp/nginx.service /usr/lib/systemd/system/
sudo systemctl daemon-reload

echo "Extracting from html.tar.gz..."
tar xzf /vagrant/html.tar.gz -C "${INSTALL_PATH%/}/html/" --strip-components=1

VHOSTS_PATH="${INSTALL_PATH%/}/conf/vhosts/"
BACKEND_PATH="${VHOSTS_PATH%/}/backend.conf"
HTPASSWD_PATH="${INSTALL_PATH%/}/conf/.htpasswd"
mkdir --parents "$VHOSTS_PATH"

# make hidden file with users
htpasswd -cb "$HTPASSWD_PATH" admin nginx
htpasswd -b "$HTPASSWD_PATH" vladi vladi

echo "Creating backend.conf..."
IP_ADDR=$( ip -f inet a show eth1 | awk '/inet/ {print $2}' | cut -d/ -f1 )
HOST_IP_ADDR=$2
PORT=8080
cat <<EOT >> "$BACKEND_PATH"
vhost_traffic_status_zone;
log_format vladi '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                 '\$status \$body_bytes_sent "\$http_referer" '
                 '"\$http_user_agent" "\$http_x_forwarded_for"';

server {
    listen ${IP_ADDR}:${PORT};
    server_name localhost;

    access_log logs/vladi.access.log vladi;

    add_header backend_srv ${1}_very_cool_backend_server;

    location / {
        root html;
        index index.html;
    }

    error_page 404 /404.html;

    location /pictures/ {
        alias html/resources/pictures/;
    }

    location /admin {
        try_files \$uri \$uri.html;

        auth_basic "Very restricted admin page";
        auth_basic_user_file ${HTPASSWD_PATH};
    }

    location /status {
        vhost_traffic_status_display;
        vhost_traffic_status_display_format html;
        allow ${2};
        deny all;
    }
}

EOT

# set owner recursively to vagrant
sudo chown -R "$USER_NAME":"$GROUP_NAME" "$WORK_DIR"

echo "Editing nginx.conf..."
# add vagrant user
sed -i 's,#\(user[[:blank:]]*\)nobody,\1'"$USER_NAME"',' "$CONFIG_FILE_PATH"

# add include directive above existing server block
sed -i 's,^\(    server\),    include '"$BACKEND_PATH"';\n\1,' "$CONFIG_FILE_PATH"

# delete existing server block
sed -i '/^    server {/,/^    }/d' "$CONFIG_FILE_PATH"

# uncomment error logs
sed -i 's/#\(error_log\)/\1/' "$CONFIG_FILE_PATH"

echo "Extracting html.tar.gz..."
tar xzf /vagrant/html.tar.gz -C "${INSTALL_PATH%/}/html/" --strip-components=1

echo "Starting nginx.service..."
sudo systemctl start nginx
echo "The end :)"
