ARG MKVVERSION=1.17.2
ARG DEBIAN_FRONTEND=noninteractive

#use official slim python image
FROM python:slim

RUN groupadd -g 1000 ripper && \
    useradd -u 1000 -g ripper ripper

#update repository
RUN apt-get update && apt-get upgrade -y

#install needed packages for ffmpeg download
RUN apt-get install -y --no-install-recommends \
    tzdata curl grep wget lsb-release less eject gddrescue

#install latest jellyfin-ffmpeg which includes fdk_aac and HWAcc
RUN curl -s https://api.github.com/repos/jellyfin/jellyfin-ffmpeg/releases/latest \
    | grep "browser.*jellyfin-ffmpeg.*$(lsb_release -cs)_$(dpkg --print-architecture).deb" \
    | awk '!/.sha256sum/' \
    | cut -d : -f 2,3 \
    | tr -d \" \
    | wget -qi -

#install ffmpeg (dependencies will be automatically resolved by apt)
RUN apt-get install -y --no-install-recommends ./jellyfin-ffmpeg*.deb && \
    ln -s /usr/lib/jellyfin-ffmpeg/ffmpeg /bin/ffmpeg


#install build dependencies for MakeMKV
RUN apt-get install -y --no-install-recommends \
    build-essential pkg-config libc6-dev libssl-dev libexpat1-dev libavcodec-dev \
    libgl1-mesa-dev qtbase5-dev zlib1g-dev

#Download and build makemkv-oss
RUN wget -nv -P /tmp/ "http://www.makemkv.com/download/makemkv-oss-${MKVVERSION}.tar.gz" && \
    tar xvf /tmp/makemkv-oss-${MKVVERSION}.tar.gz -C /tmp/  && \
    cd /tmp/makemkv-oss-${MKVVERSION}   && \
    ./configure  && \
    make  && \
    make install  && \
    make clean  && \
    rm /tmp/makemkv-oss-${MKVVERSION}.tar.gz
    
#Download and build makemkv-bin
RUN wget -nv -P /tmp/ "http://www.makemkv.com/download/makemkv-bin-${MKVVERSION}.tar.gz" && \
    tar xvf /tmp/makemkv-bin-${MKVVERSION}.tar.gz -C /tmp/  && \
    cd /tmp/makemkv-bin-${MKVVERSION}   && \
    mkdir tmp && touch tmp/eula_accepted &&\
    make  && \
    make install  && \
    make clean  && \
    rm /tmp/makemkv-bin-${MKVVERSION}.tar.gz


#install abcde and dependencies
RUN apt-get install -y --no-install-recommends \
    abcde eyed3 flac lame mkcue speex vorbis-tools vorbisgain id3 id3v2 

#install HandBrakeCLI
RUN apt-get install -y --no-install-recommends \
    handbrake-cli


#mount config dict
COPY config /config
VOLUME /config
RUN chown -R ripper:ripper /config && \
    chmod +x /config/default/ripper.sh


COPY init_ripper.sh /usr/local/bin
RUN chmod +x /usr/local/bin/init_ripper.sh


USER ripper

#install apprise for notifications
RUN python3 -m ensurepip --upgrade
RUN pip3 install apprise

CMD /usr/local/bin/init_ripper.sh


