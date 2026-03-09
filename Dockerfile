FROM node:20-alpine AS site-build

WORKDIR /src

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM alpine:3.20

RUN apk add --no-cache curl jq unzip rsync nginx supervisor

WORKDIR /app

# Copy pull-agent script
COPY docker/poll-and-deploy.sh /app/poll-and-deploy.sh
RUN chmod +x /app/poll-and-deploy.sh

# Copy nginx config
COPY docker/nginx.conf /etc/nginx/http.d/default.conf

# Create directories
RUN mkdir -p /run/nginx /var/log/nginx /site /state /var/log/supervisor

# Seed site output so the container can serve immediately.
COPY --from=site-build /src/_site/ /site/

# Supervisor config to manage both processes
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE 8069

ENTRYPOINT ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
