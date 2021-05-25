#!/bin/bash

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

# 1st script parameter - 1st backend server address
# 2nd script parameter - 2nd backend server address
echo "load balancer provision start..."

# some global variables
WORK_DIR="/home/vagrant/"
DOWNLOAD_DIR="/tmp/"

mkdir --parents "$WORK_DIR" "$DOWNLOAD_DIR"

echo "Installing gcc, git and httpd-utils..."
sudo yum install -y gcc gcc-c++ git httpd-tools iptables-services > /dev/null

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

echo "Creating certificate..."
# some values for subject
COUNTRY=BY
STATE=Minsk
LOCALITY=Minsk
ORGANIZATION=EPAM
ORGANIZATIONAL_UNIT=DevOps-Lab
EMAIL=Uladzislau_Petravets@example.com
COMMON_NAME="nginx-loadbalancer"
CERT_NAME="server"

# pathes for security files
SECURITY_PATH="${WORK_DIR%/}/SECRET-XXX/"
mkdir --parents "$SECURITY_PATH"
CERT_PATH="${SECURITY_PATH%/}/${CERT_NAME}.crt"
CSR_PATH="${SECURITY_PATH%/}/${CERT_NAME}.csr"
# of course i should place it in a safer place; i hope i'll fix it later
KEY_PATH="${SECURITY_PATH%/}/${CERT_NAME}.key"

# generate key
openssl genrsa -out "$KEY_PATH" 2048 >& /dev/null
# creating CS request
openssl req -new -key "$KEY_PATH" -out "$CSR_PATH" \
        -subj "/C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/O=${ORGANIZATION}/OU=${ORGANIZATIONAL_UNIT}/CN=${COMMON_NAME}/emailAddress=${EMAIL}"
# and sign it
openssl x509 -req -days 1337 -in "$CSR_PATH" -signkey "$KEY_PATH" -out "$CERT_PATH" 

# set permissions on certificate and directory
chmod 700 "$SECURITY_PATH"
chmod 600 "${SECURITY_PATH%/}/"*

# now dealing with config files
VHOSTS_PATH="${INSTALL_PATH%/}/conf/vhosts/"
UPSTREAMS_PATH="${INSTALL_PATH%/}/conf/upstreams/"
mkdir --parents "$VHOSTS_PATH"
mkdir --parents "$UPSTREAMS_PATH"

LB_PATH="${VHOSTS_PATH%/}/lb.conf"
UPSTREAM_PATH="${UPSTREAMS_PATH%/}/web.conf"
HTPASSWD_PATH="${INSTALL_PATH%/}/conf/.htpasswd"

# make hidden file with users
htpasswd -cb "$HTPASSWD_PATH" admin nginx
htpasswd -b "$HTPASSWD_PATH" vladi vladi

echo "Creating $UPSTREAM_PATH..."
cat <<EOT > "$UPSTREAM_PATH"
upstream backend {
    server $1:8080 weight=1;
    server $2:8080 weight=3;
}
EOT

# creating custom error page
GIF_PATH="https://miro.medium.com/max/656/0uBeoHYGK1WtcBE80"
wget --quiet $GIF_PATH -O "${INSTALL_PATH%/}/html/err.gif"
if [ $? -ne 0 ] 
then
    CONTENT="<h1>I can't even download .gif so here is a joke on my custom 404 page.</h1><br>What's red and bad for your teeth?<br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br>a brick."
else
    CONTENT="<img src="./err.gif" width="100%" />"
fi
echo "$CONTENT" > "${INSTALL_PATH%/}/html/err.html"

IP_ADDR=$( ip -f inet a show eth1 | awk '/inet/ {print $2}' | cut -d/ -f1 )
HTTP_PORT=8080
HTTPS_PORT=8443
cat <<EOT > "$LB_PATH"
vhost_traffic_status_zone;
log_format vladi '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                 '\$status \$body_bytes_sent "\$http_referer" '
                 '"\$http_user_agent" "\$http_x_forwarded_for"';

server {
    listen ${HTTP_PORT} default_server;
    server_name ${IP_ADDR};
    return 301 https://${IP_ADDR}:${HTTPS_PORT}\$request_uri;
}

server {
    listen ${HTTPS_PORT} ssl;
    server_name ${IP_ADDR};

    ssl_certificate ${CERT_PATH};
    ssl_certificate_key ${KEY_PATH};

    access_log logs/vladi.access.log vladi;

    error_page 404 /err.html;
    proxy_intercept_errors on;

    location = /err.html {
        root html;
    }

    location / {
        proxy_pass http://backend;
    }

    location /status {
        vhost_traffic_status_display;
        vhost_traffic_status_display_format html;
    }
}

EOT

# we need this service to save configuration
sudo systemctl start iptables
sudo systemctl enable iptables > /dev/null
# redirect from 80 to 8080 and 443 to 8443
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080 
sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443 
sudo iptables -I INPUT -p tcp --dport 8080 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 8443 -j ACCEPT
# and saving this configuration
# but for this we need to download missing service

sudo service iptables save

# set owner recursively to vagrant
sudo chown -R "$USER_NAME":"$GROUP_NAME" "$WORK_DIR"

echo "Editing nginx.conf..."
# add vagrant user
# nginx: [warn] the "user" directive makes sense only if the master
sed -i 's,#\(user[[:blank:]]*\)nobody,\1'"$USER_NAME"',' "$CONFIG_FILE_PATH"

# add include directives above existing server block
sed -i 's,^\(    server\),    include '"$UPSTREAM_PATH"';\n\1,' "$CONFIG_FILE_PATH"
sed -i 's,^\(    server\),    include '"$LB_PATH"';\n\1,' "$CONFIG_FILE_PATH"

# delete existing server block
sed -i '/^    server {/,/^    }/d' "$CONFIG_FILE_PATH"

# uncomment error logs
sed -i 's/#\(error_log\)/\1/' "$CONFIG_FILE_PATH"

echo "Starting nginx.service..."
sudo systemctl start nginx
echo "The end :)"
