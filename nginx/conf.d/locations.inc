location = /wp-admin {
    return 404;
}

location ^~ /wp-admin/ {
    return 404;
}

location = /wp-login.php {
    return 404;
}

location / {
    proxy_pass http://frontend:4000;

    proxy_http_version 1.1;
    proxy_read_timeout 15s;
    proxy_connect_timeout 5s;
    proxy_send_timeout 15s;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
}

location /api/ {
    limit_req zone=api_limit burst=20 nodelay;

    proxy_pass http://backend:3000/;

    proxy_http_version 1.1;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

location /blog/wp-admin/ {
    proxy_pass http://wordpress-nginx:8080/wp-admin/;
    include /etc/nginx/conf.d/wordpress-proxy-headers.inc;
}

location /blog/wp-login.php {
    limit_req zone=wp_login_limit burst=5 nodelay;

    proxy_pass http://wordpress-nginx:8080/wp-login.php;
    include /etc/nginx/conf.d/wordpress-proxy-headers.inc;
}

location /blog/wp-includes/ {
    proxy_pass http://wordpress-nginx:8080/wp-includes/;
    include /etc/nginx/conf.d/wordpress-proxy-headers.inc;
}

location /blog/wp-content/uploads/ {
    proxy_pass http://wordpress-nginx:8080/wp-content/uploads/;
    include /etc/nginx/conf.d/wordpress-proxy-headers.inc;

    expires 30d;
    add_header Cache-Control "public, immutable";
}

location /blog/wp-content/ {
    proxy_pass http://wordpress-nginx:8080/wp-content/;
    include /etc/nginx/conf.d/wordpress-proxy-headers.inc;
}

location /blog/ {
    return 403;
}
