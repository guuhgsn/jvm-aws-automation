## os comandos devem ser executados no host criado para hospedar as JVMs

## realizar o download do Apache Tomcat
cd /tmp
wget https://dlcdn.apache.org/tomcat/tomcat-9/v9.0.120/bin/apache-tomcat-9.0.120.tar.gz
sudo tar -xzf apache-tomcat-9.0.120.tar.gz

## mover a pasta descompactada e cria a estrutura
sudo mv apache-tomcat-9.0.120 /suporteapp/app/tomcat_usprd01a
sudo cp -r /suporteapp/app/tomcat_usprd01a /suporteapp/app/tomcat_usprd02b
sudo cp -r /suporteapp/app/tomcat_usprd01a /suporteapp/app/tomcat_usprd03c
sudo cp -r /suporteapp/app/tomcat_usprd01a /suporteapp/app/tomcat_usprd04d

## editar o server.xml de cada JVM e separar suas portas
sudo vi /suporteapp/app/tomcat_usprd01a/conf/server.xml

# usprd01a
# Server port="8005"
# Connector port="8080"

# usprd02b
# Server port="8006"
# Connector port="8081"

# usprd03c
# Server port="8007"
# Connector port="8082"

# usprd04d
# Server port="8008"
# Connector port="8083"

## garantir o ownership
sudo chown -R ec2-user:ec2-user /suporteapp

## copiar a aplicacao para a pasta central de deploy e distribuir entre as JVMs
mkdir -p /tmp/jvm
aws s3 cp s3://jvm-status-ops-01a/status.war /tmp/jvm/status.war
sudo cp /tmp/jvm/status.war /suporteapp/deploy/ROOT.war

# limpar cache residual de boas vindas
sudo rm -rf /suporteapp/app/tomcat_usprd01a/webapps/ROOT*
sudo rm -rf /suporteapp/app/tomcat_usprd02b/webapps/ROOT*
sudo rm -rf /suporteapp/app/tomcat_usprd03c/webapps/ROOT*
sudo rm -rf /suporteapp/app/tomcat_usprd04d/webapps/ROOT*

sudo cp /suporteapp/deploy/ROOT.war /suporteapp/app/tomcat_usprd01a/webapps/
sudo cp /suporteapp/deploy/ROOT.war /suporteapp/app/tomcat_usprd02b/webapps/
sudo cp /suporteapp/deploy/ROOT.war /suporteapp/app/tomcat_usprd03c/webapps/
sudo cp /suporteapp/deploy/ROOT.war /suporteapp/app/tomcat_usprd04d/webapps/

## definir as variaveis utilizadas por cada JVM
# JVM 01a
cat << 'EOF' | sudo tee /suporteapp/app/tomcat_usprd01a/bin/setenv.sh > /dev/null
#!/bin/bash
export CATALINA_HOME=/suporteapp/app/tomcat_usprd01a
export CATALINA_BASE=/suporteapp/app/tomcat_usprd01a
export CATALINA_OUT=/suporteapp/logs/usprd01a/SystemOut.log
export JVM_NAME="usprd01a"
EOF

# JVM 02b
cat << 'EOF' | sudo tee /suporteapp/app/tomcat_usprd02b/bin/setenv.sh > /dev/null
#!/bin/bash
export CATALINA_HOME=/suporteapp/app/tomcat_usprd02b
export CATALINA_BASE=/suporteapp/app/tomcat_usprd02b
export CATALINA_OUT=/suporteapp/logs/usprd02b/SystemOut.log
export JVM_NAME="usprd02b"
EOF

# JVM 03c
cat << 'EOF' | sudo tee /suporteapp/app/tomcat_usprd03c/bin/setenv.sh > /dev/null
#!/bin/bash
export CATALINA_HOME=/suporteapp/app/tomcat_usprd03c
export CATALINA_BASE=/suporteapp/app/tomcat_usprd03c
export CATALINA_OUT=/suporteapp/logs/usprd03c/SystemOut.log
export JVM_NAME="usprd03c"
EOF

# JVM 04d
cat << 'EOF' | sudo tee /suporteapp/app/tomcat_usprd04d/bin/setenv.sh > /dev/null
#!/bin/bash
export CATALINA_HOME=/suporteapp/app/tomcat_usprd04d
export CATALINA_BASE=/suporteapp/app/tomcat_usprd04d
export CATALINA_OUT=/suporteapp/logs/usprd04d/SystemOut.log
export JVM_NAME="usprd04d"
EOF

# conceder permissao de execucao para todos os arquivos criados
sudo chmod +x /suporteapp/app/tomcat_usprd01a/bin/setenv.sh
sudo chmod +x /suporteapp/app/tomcat_usprd02b/bin/setenv.sh
sudo chmod +x /suporteapp/app/tomcat_usprd03c/bin/setenv.sh
sudo chmod +x /suporteapp/app/tomcat_usprd04d/bin/setenv.sh

## iniciar as JVMs como o usuario padrao
sudo su - ec2-user -c "sh /suporteapp/app/tomcat_usprd01a/bin/startup.sh"
sudo su - ec2-user -c "sh /suporteapp/app/tomcat_usprd02b/bin/startup.sh"
sudo su - ec2-user -c "sh /suporteapp/app/tomcat_usprd03c/bin/startup.sh"
sudo su - ec2-user -c "sh /suporteapp/app/tomcat_usprd04d/bin/startup.sh"

## editar o arquivo de configuracao do NGINX e incluir antes do bloco "server {":"
sudo vi /etc/nginx/nginx.conf

# upstream cluster_jvms {
#    # ele distribui o trafego em round-robin entre estas JVMs
#    server 127.0.0.1:8080; # usprd01a
#    server 127.0.0.1:8081; # usprd02b
#    server 127.0.0.1:8082; # usprd03c
#    server 127.0.0.1:8083; # usprd04d
# }

# no bloco "server {", dentro do "location / {" aponte para o cluster

# server {
#    listen 80;
#    server_name _;
#    location / {
#        proxy_pass http://cluster_jvms;
#        proxy_set_header Host $host;
#        proxy_set_header X-Real-IP $remote_addr;
#    }
# }

## reiniciar o NGINX para aplicar a coletividade
sudo systemctl restart nginx