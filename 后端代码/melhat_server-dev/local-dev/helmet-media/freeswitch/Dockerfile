# Official SignalWire base supplies the native build dependencies. Source is pinned.
FROM signalwire/freeswitch-public-base:bookworm
ARG FS_REF=v1.10.12
RUN git clone --depth 1 --branch "$FS_REF" https://github.com/signalwire/freeswitch.git /usr/src/freeswitch
WORKDIR /usr/src/freeswitch
RUN find /etc/apt -type f -name '*.list' -exec sed -i '/freeswitch.signalwire.com/d' {} + && apt-get update && apt-get install -y --no-install-recommends libavcodec-dev libavformat-dev libavutil-dev libswresample-dev libswscale-dev libvpx-dev libyuv-dev && rm -rf /var/lib/apt/lists/*
RUN ./bootstrap.sh -j && printf '%s\n' applications/mod_av applications/mod_commands applications/mod_conference applications/mod_dptools applications/mod_hash codecs/mod_opus dialplans/mod_dialplan_xml endpoints/mod_sofia event_handlers/mod_event_socket formats/mod_sndfile loggers/mod_console loggers/mod_logfile xml_int/mod_xml_curl > modules.conf && ./configure --prefix=/usr/local/freeswitch && make -j1 && make install
RUN mkdir -p /var/lib/freeswitch/db /var/log/freeswitch
CMD ["/usr/local/freeswitch/bin/freeswitch", "-nonat", "-nf", "-conf", "/helmet-conf", "-log", "/var/log/freeswitch", "-db", "/var/lib/freeswitch/db"]
