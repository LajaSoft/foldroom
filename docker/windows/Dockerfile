# syntax=docker/dockerfile:1
FROM foldroom-godot:latest
ARG GODOT_VERSION=4.7.2-stable
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends zip
ARG FFB_COMMIT=bcc8c0c75e416231e8ce9feaed13188d5f2835eb
RUN curl -fL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
    && unzip -qo /tmp/godot.zip -d /tmp/godot-windows-export \
    && install -m 755 "/tmp/godot-windows-export/Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot
RUN curl -fL -o /tmp/templates.tpz "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_export_templates.tpz" \
    && mkdir -p /opt/windows-templates \
    && unzip -jo /tmp/templates.tpz 'templates/windows_*x86_64*' -d /opt/windows-templates
RUN curl -fL -o /tmp/ffb.tar.gz "https://github.com/Drachbar/godot-force-feedback/archive/${FFB_COMMIT}.tar.gz" \
    && mkdir /opt/windows-ffb \
    && tar -xzf /tmp/ffb.tar.gz --strip-components=1 -C /opt/windows-ffb
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends wine64 libc6-i386 lib32gcc-s1 lib32stdc++6
RUN curl -fL -o /tmp/godot-windows.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_win64.exe.zip" \
    && mkdir /opt/windows-godot \
    && unzip -qo /tmp/godot-windows.zip -d /opt/windows-godot
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends xvfb xauth
RUN dpkg --add-architecture i386
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    libfreetype6:i386 libfontconfig1:i386 libx11-6:i386 libxext6:i386 \
    libxrender1:i386 libxrandr2:i386 libxcursor1:i386 libxi6:i386 libxinerama1:i386 \
    libvulkan1:i386 libgl1:i386 libgnutls30t64:i386
ENV WINEPREFIX=/tmp/foldroom-wine WINEDEBUG=-all
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends python3
COPY docker/windows/build.sh /usr/local/bin/build-windows
WORKDIR /work
ENTRYPOINT ["bash", "/usr/local/bin/build-windows"]
