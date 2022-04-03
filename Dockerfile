FROM debian:bullseye-slim AS builder

ARG MKVVERSION=1.16.7
ARG FDKVERSION=2.0.2
ARG aptCacher
ARG PREFIX=/usr/local
# Set correct environment variables
ENV HOME /root
ENV DEBIAN_FRONTEND noninteractive
ENV LC_ALL C.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /root/
# 3008 Pin versions in apt get install
# hadolint ignore=DL3008,DL3003,SC2086
RUN if [ -n ${aptCacher} ]; then printf "Acquire::http::Proxy \"http://%s:3142\";" "${aptCacher}">/etc/apt/apt.conf.d/01proxy \
    && printf "Acquire::https::Proxy \"http://%s:3142\";" "${aptCacher}">>/etc/apt/apt.conf.d/01proxy ; fi  \
    #&& echo "Dir::Cache \"\";\nDir::Cache::archives \"\";" | tee /etc/apt/apt.conf.d/02nocache && \
    && printf "#/etc/dpkg/dpkg.cfg.d/01_nodoc\n\n# Delete locales\npath-exclude=/usr/share/locale/*\n\n# Delete man pages\npath-exclude=/usr/share/man/*\n\n# Delete docs\npath-exclude=/usr/share/doc/*\npath-include=/usr/share/doc/*/copyright" | tee /etc/dpkg/dpkg.cfg.d/03nodoc \
    #Massive apt install of jeedom requirements to optimise downloads
    && buildDeps='build-essential pkg-config libc6-dev libssl-dev libexpat1-dev libavcodec-dev libgl1-mesa-dev \
    qtbase5-dev zlib1g-dev'  \
    && apt-get update && apt-get install -y --no-install-recommends git wget gnupg ca-certificates apt-transport-https \
    software-properties-common libavcodec-extra $buildDeps \
    # build fdk \
    && echo "Building fdk" \
    && wget -nv http://downloads.sourceforge.net/opencore-amr/fdk-aac-$FDKVERSION.tar.gz \
    && tar xvf fdk-aac-$FDKVERSION.tar.gz \
    && cd fdk-aac-$FDKVERSION && ./configure --prefix=/usr --disable-static \
    && make && make install \
    # build ffmpeg \
    && echo "Building ffmpeg" \
    && git clone --depth 1 git://source.ffmpeg.org/ffmpeg.git ffmpeg \
    && cd ffmpeg \
    && ./configure --prefix=/tmp/ffmpeg --enable-static --disable-shared --enable-pic --disable-yasm --enable-libfdk-aac \
    && make && make install && make clean
# hadolint ignore=DL3003,SC2086
RUN echo "downloading and checking makemkv-bin-${MKVVERSION}" \
    # get & check makemkv-{oss,bin}
    && wget -nv -O /tmp/sha.txt "http://www.makemkv.com/download/makemkv-sha-${MKVVERSION}.txt" \
    && GNUPGHOME="$(mktemp -d)" \
    && gpg --batch --keyserver keyserver.ubuntu.com --recv-keys 2ECF23305F1FC0B32001673394E3083A18042697 \
    && gpg --batch --decrypt --output /tmp/shadec.txt /tmp/sha.txt \
    && gpgconf --kill all \
    && wget -nv -P /tmp/ "http://www.makemkv.com/download/makemkv-bin-${MKVVERSION}.tar.gz" \
    && wget -nv -P /tmp/ "http://www.makemkv.com/download/makemkv-oss-${MKVVERSION}.tar.gz" \
    && shaosstxt="$(grep -oP ".*(?=  makemkv-oss-${MKVVERSION})" /tmp/sha.txt)"  && [ -n ${shaosstxt} ] \
    && shabintxt="$(grep -oP ".*(?=  makemkv-bin-${MKVVERSION})" /tmp/sha.txt)" && [ -n ${shabintxt} ] \
    && cd /tmp/ && grep -P "makemkv-(oss|bin)-${MKVVERSION}" /tmp/sha.txt | sha256sum -c - \
    # build makemkv-oss
    && echo "Building makemkv-oss-${MKVVERSION}" \
    && mkdir -p /tmp/makemkv-oss-${MKVVERSION} /tmp/makemkv-bin-${MKVVERSION} \
    && echo "Building makemkv-oss-${MKVVERSION}.tar.gz" \
    && tar xvf /tmp/makemkv-oss-${MKVVERSION}.tar.gz -C /tmp/ \
    && cd /tmp/makemkv-oss-${MKVVERSION} && ls -al && chmod +x ./configure && ./configure PREFIX="${PREFIX}" \
    && make PREFIX="${PREFIX}" && make install PREFIX="${PREFIX}" && make clean \
    && rm /tmp/makemkv-oss-${MKVVERSION}.tar.gz \
    # build makemkv-bin \
    && tar xvf /tmp/makemkv-bin-${MKVVERSION}.tar.gz -C /tmp/ \
    && cd /tmp/makemkv-bin-${MKVVERSION} && pwd && mkdir tmp && touch tmp/eula_accepted && make && make install \
    && make clean && rm /tmp/makemkv-bin-${MKVVERSION}.tar.gz


FROM debian:bullseye-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# oss
COPY --from=builder /usr/lib/libdriveio.so.0 /usr/lib/libdriveio.so.0
COPY --from=builder /usr/lib/libmakemkv.so.1 /usr/lib/libmakemkv.so.1
COPY --from=builder /usr/lib/libmmbd.so.0 /usr/lib/libmmbd.so.0
COPY --from=builder /usr/bin/makemkv* /usr/bin/
COPY --from=builder /usr/share/applications/makemkv.desktop /usr/share/applications/makemkv.desktop
COPY --from=builder /usr/share/icons/hicolor/16x16/apps/makemkv.png /usr/share/icons/hicolor/16x16/apps/makemkv.png
COPY --from=builder /usr/share/icons/hicolor/22x22/apps/makemkv.png /usr/share/icons/hicolor/22x22/apps/makemkv.png
COPY --from=builder /usr/share/icons/hicolor/32x32/apps/makemkv.png /usr/share/icons/hicolor/32x32/apps/makemkv.png
COPY --from=builder /usr/share/icons/hicolor/64x64/apps/makemkv.png /usr/share/icons/hicolor/64x64/apps/makemkv.png
COPY --from=builder /usr/share/icons/hicolor/128x128/apps/makemkv.png /usr/share/icons/hicolor/128x128/apps/makemkv.png
COPY --from=builder /usr/share/icons/hicolor/256x256/apps/makemkv.png /usr/share/icons/hicolor/256x256/apps/makemkv.png
COPY --from=builder /usr/bin/mmccextr /usr/bin/mmccextr
# bin
COPY --from=builder /usr/share/MakeMKV /usr/share/MakeMKV
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

WORKDIR /root
# Install software
# hadolint ignore=DL3008,DL3013,DL3042,SC2086
RUN export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get upgrade -y \
    && apt-get -y install --no-install-recommends supervisor wget eject git curl gddrescue abcde eyed3 flac lame \
    mkcue speex vorbis-tools vorbisgain id3 id3v2 libavcodec-extra \
    # Install python for web ui
    && apt-get -y install --no-install-recommends python3 python3-pip python3-setuptools build-essential \
    python-pip-whl python3-distutils python3-lib2to3  python3-dev python3-wheel sdparm \
    && pip3 install wheel docopt flask waitress setuptools  \
    # add notification eml/pushover/pushbullet \
    && git clone https://github.com/ltpitt/python-simple-notifications.git \
    && apt-get -y autoremove \
    && ln -s -f makemkvcon sdftool \
    # Configure user nobody to match unRAID's settings
    && usermod -u 99 nobody \
    && usermod -g 100 nobody \
    && usermod -d /home nobody \
    && chown -R nobody:users /home \
    # Clean up temp files
    && echo "Purge the dependencies"  \
    && apt-get purge -y --auto-remove $buildDeps \
    && echo "Purge the apt cache" \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy project Files
COPY root/ /

# Start supervisord as init system
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]

LABEL maintainer="edgd1er <edgd1er@htomail.com>" \
      org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="Ripper" \
      org.label-schema.description="Provides automatic CD/DVD ripping tool in Docker." \
      org.label-schema.url="https://hub.docker.com/r/edgd1er/docker-ripper" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/edgd1er/docker-ripper" \
      org.label-schema.version=${MKVVERSION} \
      org.label-schema.schema-version="1.0"

ENV NOTIFICATION_ON="n" \
    EMAIL_SENDER='' \
    EMAIL_PASSWORD='' \
    EMAIL_SERVER='' \
    EMAIL_SERVER_PORT='' \
    EMAIL_DEBUG_LEVEL='' \
    PUSHOVER_APP_TOKEN='' \
    USER_KEY='' \
    PUSHBULLET_APP_TOKEN=''