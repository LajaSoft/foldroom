# syntax=docker/dockerfile:1
FROM ubuntu:24.04 AS base
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 libx11-6 libxcursor1 libxinerama1 libxrandr2 libxi6 libgl1 libasound2t64

FROM base AS tools
ARG GODOT_VERSION=4.4.1
RUN curl -fL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && unzip -q /tmp/godot.zip -d /tmp \
    && install -m 755 "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot
RUN curl -fL -o /tmp/templates.tpz "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" \
    && mkdir -p "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable" \
    && unzip -j /tmp/templates.tpz 'templates/web_nothreads_release.zip' -d "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable"

FROM base
COPY --from=tools /usr/local/bin/godot /usr/local/bin/godot
COPY --from=tools /root/.local/share/godot/export_templates /root/.local/share/godot/export_templates
COPY godot /source/godot
COPY docker/web/build.sh /build.sh
WORKDIR /work
CMD ["bash", "/build.sh"]
