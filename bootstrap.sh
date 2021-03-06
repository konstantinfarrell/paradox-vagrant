# this makes DNS lookups fast
echo "options single-request-reopen" >> /etc/resolv.conf

yum clean all

# update yum
yum -y update

# good utils
yum install -y vim wget nc curl emacs words mlocate dos2unix gcc

# epel
wget http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-7.noarch.rpm
rpm -Uvh epel-release-7*.rpm
rm -f epel-release-7*.rpm

# set the hostname to some random list of words
hostname=`shuf -n 2 /usr/share/dict/words | tr '\n' '.' | tr '[:upper:]' '[:lower:]' | tr -cd "[.a-z]" | sed "s/\.$//"`
hostname $hostname
sed -i "s/HOSTNAME=.*/HOSTNAME=$hostname/" /etc/sysconfig/network

# set the root password to vagrant
echo "vagrant" | sudo passwd --stdin root

# kill iptables
systemctl stop ip6tables
systemctl stop iptables
chkconfig iptables off
chkconfig ip6tables off

# set the timezone to something reasonable
ln -sf /usr/share/zoneinfo/US/Pacific /etc/localtime

# install network time
yum install ntp

# install mariadb
yum -y install mariadb-server mariadb

systemctl start mariadb.service
systemctl enable mariadb.service

# install apache
yum install -y httpd httpd-tools mod_ssl

systemctl start httpd.service
systemctl enable httpd.service

# Set a firewall exception
firewall-cmd --permanent --zone=public --add-service=http 
firewall-cmd --permanent --zone=public --add-service=https
firewall-cmd --reload

# make sure it starts when this machine boots
chkconfig --levels 235 httpd on


# customize apache a bit
sed -i "s/#ExtendedStatus On/ExtendedStatus On/" /etc/httpd/conf/httpd.conf
sed -i "s/#ServerName .*/ServerName $hostname/" /etc/httpd/conf/httpd.conf
sed -i "s/#EnableSendfile off/EnableSendfile off/" /etc/httpd/conf/httpd.conf
sed -i "s/LogLevel warn/LogLevel info/" /etc/httpd/conf/httpd.conf
sed -i "s/#NameVirtualHost \*:80/NameVirtualHost *:80/" /etc/httpd/conf/httpd.conf
# this is the logformat commonly used by the unix team
echo 'LogFormat "%v %h %l %u %t \"%r\" %>s %b" vhost' >> /etc/httpd/conf/httpd.conf
# this is where the unix team keeps vhosts
echo 'Include vhost.d/*.conf' >> /etc/httpd/conf/httpd.conf

# remove this because it screws up `Options Indexes`
rm -f /etc/httpd/conf.d/welcome.conf

# setup some vhosts
mkdir -p /etc/httpd/vhost.d
cat > /etc/httpd/vhost.d/vagrant.conf <<EOF
<VirtualHost *:80>
    DocumentRoot /vagrant
    ErrorLog /var/log/httpd/vagrant.error_log
    CustomLog /var/log/httpd/vagrant.access_log vhost

    <Directory /vagrant>
        AllowOverride All
        Options Indexes FollowSymLinks
    </Directory>
</VirtualHost>
EOF

cat > /etc/httpd/vhost.d/example.conf.example <<EOF
<VirtualHost *:80>
    ServerName example.local
    # so wildcard DNS for any IP works (see xip.io or nip.io)
    ServerAlias example.*

    DocumentRoot /home/example/htdocs
    ErrorLog /var/log/httpd/example.local.error_log
    CustomLog /var/log/httpd/example.local.access_log vhost

    <Directory /home/example/htdocs>
        AllowOverride All
    </Directory>
</VirtualHost>
EOF

cat > /etc/httpd/vhost.d/django.conf.example <<EOF
<VirtualHost *:80>
    ServerName django.local
    # this isn't actually necessary, but the unix team requires it
    DocumentRoot /home/django/static
    # so wildcard DNS for any IP works (see xip.io or nip.io)
    ServerAlias django.local.*

    # logs
    ErrorLog /var/log/httpd/django.local.error_log
    CustomLog /var/log/httpd/django.local.access_log vhost

    # django
    WSGIDaemonProcess django.local processes=2 threads=25 display-name=%{GROUP}
    WSGIProcessGroup  django.local
    WSGIScriptAlias / /home/django.local/django/wsgi.py

    # make aliases for files and dirs that should not be handled by django
    Alias /robots.txt  /home/django/static/robots.txt
    Alias /favicon.ico /home/django/static/favicon.ico
    Alias /static /home/django/static

    <Directory /home/django/static>
        AllowOverride All
    </Directory>
</VirtualHost>
EOF

# install the IUS repo which has a bunch of updated packages in it
wget https://centos7.iuscommunity.org/ius-release.rpm
rpm -Uvh ius-release*.rpm
rm -f ius-release*.rpm

# install PHP
yum install -y php

systemctl restart httpd.service

# install PHP dependencies
yum -y install php-mysql
yum -y install php-gd php-ldap php-odbc php-pear php-xml php-xmlrpc php-mbstring php-snmp php-soap curl curl-devel

systemctl restart httpd.service

# prepare for postgres
sed -i -E 's#(\[(base|updates)\])#\1\nexclude=postgresql*#g'  /etc/yum.repos.d/CentOS-Base.repo
yum -y localinstall http://yum.postgresql.org/9.4/redhat/rhel-6-x86_64/pgdg-centos94-9.4-1.noarch.rpm

# install postgres94 with postgis
yum install -y postgresql94 postgresql94-server postgresql94-libs postgresql94-contrib postgresql94-devel postgis2_94
/usr/pgsql-9.4/bin/postgresql94-setup initdb
service postgresql-9.4 start
chkconfig postgresql-9.4 on

# create a root user
su -c "psql -c \"CREATE ROLE root WITH PASSWORD 'vagrant' SUPERUSER LOGIN;\"" postgres
# allow md5 auth
echo "host    all             all             all            md5" >> /var/lib/pgsql/9.4/data/pg_hba.conf
# Add postgres bins to path
printf 'export PATH=/usr/pgsql-9.4/bin:$PATH\n' >> ~/.bashrc
# Allow external connections (pgadmin etc)
echo "listen_addresses = '*'" >> /var/lib/pgsql/9.4/data/postgresql.conf

# git
yum install -y curl-devel expat-devel gettext-devel openssl-devel zlib-devel perl-devel
yum install -y git

# elasticsearch
rpm --import http://packages.elasticsearch.org/GPG-KEY-elasticsearch
cat > /etc/yum.repos.d/elasticsearch.repo <<EOF
[elasticsearch-1.2]
name=Elasticsearch repository for 1.2.x packages
baseurl=http://packages.elasticsearch.org/elasticsearch/1.2/centos
gpgcheck=1
gpgkey=http://packages.elasticsearch.org/GPG-KEY-elasticsearch
enabled=1
EOF

yum install -y java-1.7.0-openjdk
yum install -y elasticsearch
service elasticsearch start
chkconfig --add elasticsearch

# rabbitmq
yum install -y rabbitmq-server
service rabbitmq-server start
chkconfig rabbitmq-server on

# LDAP
yum install -y openldap-clients openldap-devel
# set the search base for ldap
sed -i "s/#BASE.*/BASE dc=pdx,dc=edu/" /etc/openldap/ldap.conf
sed -i "s@#URI.*@URI ldap://ldap-login.oit.pdx.edu@" /etc/openldap/ldap.conf



# Python
git clone https://github.com/yyuu/pyenv.git /root/.pyenv
echo 'export PYENV_ROOT="/root/.pyenv"' >> /root/.bashrc
echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> /root/.bashrc
echo 'eval "$(pyenv init -)"' >> /root/.bashrc
exec $SHELL


# Redis
adduser --base-dir /opt/ redis
su --login redis - <<EOF
    cd
    wget http://download.redis.io/releases/redis-3.2.1.tar.gz
    tar xzf redis-3.2.1.tar.gz
    cd redis-3.2.1
    make PREFIX=/opt/redis install
    cp redis.conf /opt/redis/redis.conf
    exit
EOF
touch /var/log/redis.log
chown redis:redis /var/log/redis.log
cat > /etc/init/redis-server.conf <<EOF
description "redis server"

start on runlevel [23]
stop on shutdown

exec sudo -u redis /opt/redis/bin/redis-server /opt/redis/redis.conf

respawn
EOF

# config
sed -i "s/# bind 127.0.0.1/bind 127.0.0.1/" /opt/redis/redis.conf
sed -i "s/timeout 0/timeout 300/" /opt/redis/redis.conf
sed -i 's#logfile ""#logfile /var/log/redis.log#' /opt/redis/redis.conf
sed -i 's#dir ./#dir /opt/redis/#' /opt/redis/redis.conf
start redis-server

# make the blue lighter
sed -i "s/DIR 01;34/DIR 01;94/" /etc/DIR_COLORS

# make the locate command work
updatedb

cp -r /vagrant/.vim* ~

systemctl restart httpd
systemctl restart mysqld

# install vim 7.4
yum -y --skip-broken groupinstall 'Development tools'
yum -y install ncurses ncurses-devel
cd /usr/local/src
wget ftp://ftp.vim.org/pub/vim/unix/vim-7.4.tar.bz2
tar -xjf vim-7.4.tar.bz2
cd vim74
./configure --prefix=/usr/local --with-features=huge --enable-rubyinterp --enable-pythoninterp
make && make install

# no one in their right mind wants to use the old vi
echo "alias vi=vim" >> ~/.bashrc
echo "export EDITOR=vim" >> ~/.bashrc
git config --global core.editor vim

# redirect all mail to root
# http://www.euperia.com/development/how-to-configure-postfix-to-deliver-all-mail-to-one-mailbox/1132
echo '/^.*$/ root' > /etc/postfix/canonical-redirect
echo "canonical_maps = regexp:/etc/postfix/canonical-redirect" > /etc/postfix/main.cf
service postfix restart
# much better mail client
yum install -y alpine
echo "alias mail=alpine" >> ~/.bashrc

# Lets make the vagrant user have the same dotfiles as root
cp ~/.gitconfig /home/vagrant/.gitconfig
cp ~/.bashrc /home/vagrant/.bashrc
cp -r /vagrant/.vim* /home/vagrant
chown -R vagrant:vagrant /home/vagrant/.vim
