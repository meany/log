FROM node:20-alpine AS site-build

WORKDIR /src

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM alpine:3.20

RUN apk add --no-cache nginx

WORKDIR /app

# Copy nginx config
COPY docker/nginx.conf /etc/nginx/http.d/default.conf

# Create directories
RUN mkdir -p /run/nginx /var/log/nginx /site

# Seed site output so the container can serve immediately.
COPY --from=site-build /src/_site/ /site/

EXPOSE 8069

ENTRYPOINT ["nginx", "-g", "daemon off;"]
