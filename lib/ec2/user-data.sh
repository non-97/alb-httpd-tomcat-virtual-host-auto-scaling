#!/bin/bash

# -x to display the command to be executed
set -xe

# Redirect /var/log/user-data.log and /dev/console
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# Install Packages
token=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
region_name=$(curl -H "X-aws-ec2-metadata-token: $token" -v http://169.254.169.254/latest/meta-data/placement/availability-zone | sed -e 's/.$//')

dnf install -y "https://s3.${region_name}.amazonaws.com/amazon-ssm-${region_name}/latest/linux_amd64/amazon-ssm-agent.rpm" java-17-openjdk httpd

# SSM Agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Tomcat 10
# Install
cd /usr/local/
curl https://dlcdn.apache.org/tomcat/tomcat-10/v10.1.12/bin/apache-tomcat-10.1.12.tar.gz -o apache-tomcat-10.1.12.tar.gz
tar zxvf apache-tomcat-10.1.12.tar.gz
rm -rf apache-tomcat-10.1.12.tar.gz

# symbolic link
ln -s apache-tomcat-10.1.12 tomcat10
ls -l | grep tomcat

# Add tomcat user
useradd tomcat -M -s /sbin/nologin
id tomcat

mkdir -p ./tomcat10/pid/
chown tomcat:tomcat -R ./tomcat10/
ls -l | grep tomcat
ls -l ./tomcat10/

# setenv.sh
tee ./tomcat10/bin/setenv.sh << 'EOF'
export CATALINA_OPTS=" \
  -server \
  -Xms512m \
  -Xmx512m \
  -Xss512k \
  -XX:MetaspaceSize=512m \
  -Djava.security.egd=file:/dev/urandom"
export CATALINA_PID=/usr/local/tomcat10/pid/tomcat10.pid
EOF

# AJP
line_num_comment_start=$(($(grep -n '<Connector protocol="AJP/1.3"' ./tomcat10/conf/server.xml | cut -d : -f 1)-1))
line_num_comment_end=$(tail -n +$(($line_num_comment_start)) ./tomcat10/conf/server.xml \
  | grep -n '\-\->' \
  | head -n 1 \
  | cut -d : -f 1
)
line_num_comment_end=$(($line_num_comment_end+$line_num_comment_start-1))

sed "${line_num_comment_start}d" ./tomcat10/conf/server.xml > tmpfile && mv -f tmpfile ./tomcat10/conf/server.xml
sed "$((${line_num_comment_end}-1))d" ./tomcat10/conf/server.xml > tmpfile && mv -f tmpfile ./tomcat10/conf/server.xml
sed "$((${line_num_comment_end}-3))a \               secretRequired=\"false\"" ./tomcat10/conf/server.xml > tmpfile && mv -f tmpfile ./tomcat10/conf/server.xml

# Virtual Host
line_num_engine_end=$(($(grep -n '</Engine>' ./tomcat10/conf/server.xml | cut -d : -f 1)))
insert_text=$(cat <<'EOF'

     <Host name="hoge.web.non-97.net" appBase="hoge"
          unpackWARs="true" autoDeploy="false" >
          <Valve className="org.apache.catalina.valves.AccessLogValve" directory="logs"
               prefix="hoge_access_log" suffix=".log" rotatable="false"
               pattern="%h %l %u %t &quot;%r&quot; %s %b" />
     </Host>

     <Host name="fuga.web.non-97.net" appBase="fuga"
          unpackWARs="true" autoDeploy="false" >
          <Valve className="org.apache.catalina.valves.AccessLogValve" directory="logs"
               prefix="fuga_access_log" suffix=".log" rotatable="false"
               pattern="%h %l %u %t &quot;%r&quot; %s %b" />
     </Host>
EOF
)
awk -v n=$line_num_engine_end \
  -v s="$insert_text" \
    'NR == n {print s} {print}' ./tomcat10/conf/server.xml \
  > tmpfile && mv -f tmpfile ./tomcat10/conf/server.xml

# Contents
line_num_comment_start=$(($(grep -n 'org.apache.catalina.valves.RemoteAddrValve' ./tomcat10/webapps/examples/META-INF/context.xml | cut -d : -f 1)-1))
line_num_comment_end=$(($line_num_comment_start+3))

sed "$((${line_num_comment_start}))a <\!\-\-" ./tomcat10/webapps/examples/META-INF/context.xml > tmpfile && mv -f tmpfile ./tomcat10/webapps/examples/META-INF/context.xml
sed "$((${line_num_comment_end}))a \-\->" ./tomcat10/webapps/examples/META-INF/context.xml > tmpfile && mv -f tmpfile ./tomcat10/webapps/examples/META-INF/context.xml

cp -pr ./tomcat10/webapps/ ./tomcat10/hoge
cp -pr ./tomcat10/webapps/ ./tomcat10/fuga

echo "hoge tomcat $(uname -n)" > ./tomcat10/hoge/examples/index.html
echo "fuga tomcat $(uname -n)" > ./tomcat10/fuga/examples/index.html

# systemd
tee /etc/systemd/system/tomcat10.service << EOF
[Unit]
Description=Apache Tomcat Web Application Container
ConditionPathExists=/usr/local/tomcat10
After=syslog.target network.target

[Service]
User=tomcat
Group=tomcat
Type=oneshot
RemainAfterExit=yes

ExecStart=/usr/local/tomcat10/bin/startup.sh
ExecStop=/usr/local/tomcat10/bin/shutdown.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl list-unit-files --type=service | grep tomcat

systemctl start tomcat10
systemctl enable tomcat10

# httpd
# Virtual Host
tee /etc/httpd/conf.d/httpd-vhosts.conf << EOF
<VirtualHost *:80>
    ServerName hoge.web.non-97.net
    DocumentRoot /var/www/html/hoge

    ProxyPass /tomcat10/ ajp://localhost:8009/
    ProxyPassReverse /tomcat10/ ajp://localhost:8009/

    <Directory /var/www/html/hoge>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /var/log/httpd/hoge_error_log
    CustomLog /var/log/httpd/hoge_access_log combined
</VirtualHost>

<VirtualHost *:80>
    ServerName fuga.web.non-97.net
    DocumentRoot /var/www/html/fuga

    ProxyPass /tomcat10/ ajp://localhost:8009/
    ProxyPassReverse /tomcat10/ ajp://localhost:8009/

    <Directory /var/www/html/fuga>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /var/log/httpd/fuga_error_log
    CustomLog /var/log/httpd/fuga_access_log combined
</VirtualHost>
EOF

# Contents
mkdir -p /var/www/html/hoge
mkdir -p /var/www/html/fuga

echo "hoge $(uname -n)" > /var/www/html/hoge/index.html
echo "fuga $(uname -n)" > /var/www/html/fuga/index.html

systemctl start httpd
systemctl enable httpd

# SELinux
setsebool -P httpd_can_network_connect=true
getsebool -a