FROM openresty/openresty:alpine-fat AS build

RUN opm get bungle/lua-resty-template \
  && opm get spacewander/luafilesystem \
  && opm get fffonion/lua-resty-acme \
  && echo "All done!"

FROM openresty/openresty:alpine

EXPOSE 80/tcp

EXPOSE 443/tcp

ENV LUA_PATH="/usr/local/openresty/site/lualib/?.lua;;"

ENV BUILD_CONFIG_PATH="/usr/local/share/lua/5.1/build_config.lua"

COPY <<EOF $BUILD_CONFIG_PATH
require'resty.template'.new{root = '/etc/nginx'}.render'nginx.conf'
EOF

COPY --from=build /usr/local/openresty/site/lualib /usr/local/openresty/site/lualib

CMD luajit $BUILD_CONFIG_PATH > /var/run/openresty/nginx.conf && openresty -c /var/run/openresty/nginx.conf

ADD ./conf  /etc/nginx
