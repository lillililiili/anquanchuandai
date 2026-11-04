# Build context: private vendor directory containing DMInstall.bin and auto_install.xml.
# Official test package provenance and actual server version are recorded in docs/deployment.
FROM eclipse-temurin:21-jre-jammy@sha256:d63bd8d9b171999cbed8576f2c76e874dd4856791a358536e5c4d407e77edc13
RUN apt-get update && apt-get install -y --no-install-recommends libaio1=0.3.112-13build1 && rm -rf /var/lib/apt/lists/*
RUN groupadd -r dinstall && useradd -r -g dinstall -m -s /bin/bash dmdba
COPY DMInstall.bin auto_install.xml /tmp/
RUN echo '71d0eef76796360bbc9a5ddad39c697f3fd63706f83af02c043e9b7167117c49  /tmp/DMInstall.bin' | sha256sum -c - \
 && bash /tmp/DMInstall.bin -q /tmp/auto_install.xml \
 && rm -f /tmp/DMInstall.bin /tmp/auto_install.xml
ENV LD_LIBRARY_PATH=/opt/dmdbms/bin PATH=/opt/dmdbms/bin:$PATH
USER dmdba
EXPOSE 5236
# Initialization and schema migration are explicit operator tasks, never startup side effects.
CMD ["dmserver", "/opt/dmdbms/data/DAMENG/dm.ini", "-noconsole"]
