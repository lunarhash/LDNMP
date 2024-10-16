#!/bin/bash

# 检查是否安装了 Docker11
if ! [ -x "$(command -v docker)" ]; then
  echo "Docker 未安装。正在安装 Docker..."
  apt update && apt install -y docker.io
else
  echo "Docker 已安装"
fi

# 检查是否安装了 Docker Compose
if ! [ -x "$(command -v docker-compose)" ]; then
  echo "Docker Compose 未安装。正在安装 Docker Compose..."
  apt install -y docker-compose
else
  echo "Docker Compose 已安装"
fi

# 提示输入域名
read -p "请输入你的域名: " DOMAIN

# 安装 Certbot
if ! [ -x "$(command -v certbot)" ]; then
  echo "Certbot 未安装。正在安装 Certbot..."
  apt install -y certbot
else
  echo "Certbot 已安装"
fi

# 申请 SSL 证书
echo "申请 SSL 证书..."
certbot certonly --standalone --non-interactive --agree-tos -m admin@$DOMAIN -d $DOMAIN

# 创建目录结构
echo "创建目录结构..."
mkdir -p ~/wordpress-docker/html ~/wordpress-docker/nginx/conf.d ~/wordpress-docker/nginx/log ~/wordpress-docker/nginx/certs

# 生成 docker-compose.yml 文件
echo "生成 docker-compose.yml..."
cat > ~/wordpress-docker/docker-compose.yml <<EOL
version: '3.8'

services:
  nginx:
    image: nginx:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/certs:/etc/nginx/certs
      - ./html:/var/www/html
      - ./nginx/log:/var/log/nginx
    depends_on:
      - php
      - wordpress
    networks:
      - wp-network

  php:
    image: php:fpm-alpine
    volumes:
      - ./html:/var/www/html
    networks:
      - wp-network

  mysql:
    image: mysql:5.7
    command: --default-authentication-plugin=mysql_native_password
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: example_root_password
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wordpress_user
      MYSQL_PASSWORD: example_password
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - wp-network

  wordpress:
    image: wordpress:latest
    restart: always
    environment:
      WORDPRESS_DB_HOST: mysql:3306
      WORDPRESS_DB_USER: wordpress_user
      WORDPRESS_DB_PASSWORD: example_password
      WORDPRESS_DB_NAME: wordpress
    volumes:
      - ./html:/var/www/html
    depends_on:
      - mysql
    networks:
      - wp-network

  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    restart: always
    environment:
      PMA_HOST: mysql
      MYSQL_ROOT_PASSWORD: example_root_password
    ports:
      - "8080:80"
    depends_on:
      - mysql
    networks:
      - wp-network

  redis:
    image: redis:alpine
    restart: always
    networks:
      - wp-network

networks:
  wp-network:
    driver: bridge

volumes:
  db_data:
EOL

# 生成 nginx.conf 文件
echo "生成 nginx.conf..."
cat > ~/wordpress-docker/nginx/nginx.conf <<EOL
user  nginx;
worker_processes  auto;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    sendfile        on;
    keepalive_timeout  65;

    include /etc/nginx/conf.d/*.conf;
    server_tokens off;  # 隐藏服务器版本信息
}
EOL

# 生成站点配置文件 default.conf
echo "生成 Nginx 站点配置 default.conf..."
cat > ~/wordpress-docker/nginx/conf.d/default.conf <<EOL
server {
    listen 80;
    server_name $DOMAIN;

    root /var/www/html;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass php:9000;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    # 使用 certbot 生成的 SSL 证书
    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # 强制将 HTTP 重定向到 HTTPS
    if (\$scheme = http) {
        return 301 https://\$host\$request_uri;
    }

    # 阻止 Censys 和其他扫描工具
    if (\$http_user_agent ~* (censys|masscan|nmap|zmap)) {
        return 403;
    }
}
EOL

# 设置目录权限
echo "设置目录权限..."
chown -R nginx:nginx ~/wordpress-docker/html
chmod -R 755 ~/wordpress-docker/html

# 启动 Docker Compose
echo "启动 Docker 容器..."
cd ~/wordpress-docker && docker-compose up -d

echo "所有服务已启动，请访问 https://$DOMAIN"
