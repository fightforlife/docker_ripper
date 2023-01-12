#use official ubuntu rolling image
FROM ubuntu:rolling

ENV MKVVERSION=1.17.2
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Berlin
#update repository
RUN apt-get update && apt-get upgrade -y

#install needed packages for ffmpeg download
RUN apt-get install -y --no-install-recommends \
    tzdata curl grep wget lsb-release less eject \
    gddrescue jq vainfo bzip2 build-essential

#install abcde and dependencies
RUN apt-get install -y --no-install-recommends \
    abcde eyed3 flac lame mkcue speex vorbis-tools vorbisgain id3 id3v2 

#build latest Intel libva
RUN cd && rm -rf libva-* && \
    curl -s https://api.github.com/repos/intel/libva/releases/latest \
    | grep "browser.*libva-.*.tar.bz2" \
    | awk '!/.sha1sum/' \
    | cut -d : -f 2,3 \
    | tr -d \" \
    | wget -qi - && \
    tar -xvf libva-*.tar.bz2 && cd libva-*/ && \
    ./configure && make && make install && \
    cd && rm -rf libva-*

#build latest Intel gmmlib
RUN cd && rm -rf intel-gmmlib-* && \
    wget https://api.github.com/repos/intel/gmmlib/tarball/refs/tags/$(curl "https://api.github.com/repos/intel/gmmlib/tags" | jq -r '.[0].name') && \
    tar -xvf intel-gmmlib-* && cd intel-gmmlib-*/ && \
    mkdir build && cd build/ && \
    cmake -DCMAKE_BUILD_TYPE=Release .. && \
    make -j"$(nproc)" && make install && \
    cd && rm -rf intel-gmmlib-*

#build latest Intel media driver
RUN cd && rm -rf intel-media-* && \
    curl -s https://api.github.com/repos/intel/media-driver/releases/latest \
    | jq -r '.tarball_url' \
    | wget -qi - && \
    tar -xvf intel-media-* && cd intel-media-*/ && \
    mkdir build && cd build/ && \
    cmake .. && make -j"$(nproc)" && make install && \
    cd && rm -rf intel-media-*

#build latest Intel media sdk
RUN cd && rm -rf intel-mediasdk-* && \
    curl -s https://api.github.com/repos/Intel-Media-SDK/MediaSDK/releases/latest \
    | jq -r '.tarball_url' \
    | wget -qi - && \
    tar -xvf intel-mediasdk-* && cd intel-mediasdk-*/ && \ 
    mkdir build && cd build/ && \
    cmake .. && make && make install && \
    cd && rm -rf intel-mediasdk-*


#install HandBrakeCLI dependencies (https://handbrake.fr/docs/en/latest/developer/install-dependencies-debian.html)
RUN apt-get install  -y --no-install-recommends \
    autoconf automake autopoint appstream build-essential cmake git libass-dev \
    libbz2-dev libfontconfig1-dev libfreetype6-dev libfribidi-dev libharfbuzz-dev \
    libjansson-dev liblzma-dev libmp3lame-dev libnuma-dev libogg-dev libopus-dev \
    libsamplerate-dev libspeex-dev libtheora-dev libtool libtool-bin libturbojpeg0-dev \
    libvorbis-dev libx264-dev libxml2-dev libvpx-dev m4 make meson nasm ninja-build \
    patch pkg-config tar zlib1g-dev clang \
    libva-dev libdrm-dev
#build HandBrakeCLI
RUN curl -s https://api.github.com/repos/HandBrake/HandBrake/releases/latest \
    | grep "browser.*HandBrake.*-source.tar.bz2" \
    | awk '!/.sig/' \
    | cut -d : -f 2,3 \
    | tr -d \" \
    | wget -qi -
RUN tar -xvf HandBrake*-source.tar.bz2
RUN cd HandBrake*/ && \
    ./configure --launch-jobs=$(nproc) --launch --enable-qsv --disable-gtk && \
    make --directory=build install
RUN cd && rm -rf HandBrake*


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


RUN groupadd -g 1000 ripper && \
    useradd -m -u 1000 -g ripper ripper

#mount config dict
COPY config /config
RUN chown -R ripper:ripper /config && \
    chmod +x /config/default/ripper.sh


RUN mkdir /out
RUN chown -R ripper:ripper /out

COPY init_ripper.sh /usr/local/bin
RUN chmod +x /usr/local/bin/init_ripper.sh

USER ripper
VOLUME /out
VOLUME /config
CMD /usr/local/bin/init_ripper.sh
