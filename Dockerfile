# ============================================================
# ai-relay-hub — 三反代 + 一聚合层，单镜像 All-in-One
#
# 策略：不重建上游，全部 COPY --from= 官方镜像成品 / 官方 Release 二进制：
#   - wb-proxy   : ghcr.io/ardeyouxipianyi/workbuddy2api-hub (Alpine+Py3.11)  ← 底座
#   - oc-gate    : ghcr.io/guji08233/opencode-free-gate      (Go 单二进制 /app/gate)
#   - new-api    : QuantumNous/new-api GitHub Release 二进制（绕开 Docker Hub）
#   - qoder-proxy: 源码 tar + npm ci（无官方镜像；Node 由 apk 提供）
#
# 网络说明：GitHub 直连受限环境可传 --build-arg GH_PROXY_PREFIX=https://gh-proxy.com/
# ============================================================

ARG WB_IMAGE=ghcr.io/ardeyouxipianyi/workbuddy2api-hub:latest
ARG OC_IMAGE=ghcr.io/guji08233/opencode-free-gate:latest
ARG NEWAPI_VERSION=v1.0.0-rc.44
ARG QODER_REF=main
ARG GH_PROXY_PREFIX=

FROM ${WB_IMAGE} AS wb
FROM ${OC_IMAGE} AS oc

# ---------- 最终镜像 ----------
FROM ${WB_IMAGE}
ARG NEWAPI_VERSION
ARG QODER_REF
ARG GH_PROXY_PREFIX
ARG TARGETARCH

# 系统件：Node(qoder) + supervisor(进程编排) + tini(PID1) + curl(取件) + tzdata
# gcompat + libc6-compat：new-api 的 GitHub Release 是 glibc 动态链接 ELF，Alpine(musl) 靠它兼容
RUN apk add --no-cache nodejs npm supervisor bash curl tzdata tini gcompat libc6-compat

# oc-gate：直接拿官方镜像里的静态 Go 二进制
COPY --from=oc /app/gate /opt/ocgate/gate

# new-api：GitHub Release 官方二进制（amd64/arm64 双架构）
RUN set -e; \
    case "$TARGETARCH" in \
      amd64) NA="new-api" ;; \
      arm64) NA="new-api-arm64" ;; \
      *) echo "[build] unsupported TARGETARCH=$TARGETARCH"; exit 1 ;; \
    esac; \
    mkdir -p /opt/agg; \
    curl -fsSL "${GH_PROXY_PREFIX}https://github.com/QuantumNous/new-api/releases/download/${NEWAPI_VERSION}/${NA}-${NEWAPI_VERSION}" \
      -o /opt/agg/new-api; \
    chmod +x /opt/agg/new-api; \
    /opt/agg/new-api --version || true

# qoder-proxy：源码 + 依赖 + CN 后端 CLI（Global 的 qodercli 交互登录容器内不可用，见 README）
RUN set -e; \
    mkdir -p /opt/qoder; \
    curl -fsSL "${GH_PROXY_PREFIX}https://github.com/avaritiachaos/qoder-proxy/archive/refs/heads/${QODER_REF}.tar.gz" \
      -o /tmp/qoder.tar.gz; \
    tar xzf /tmp/qoder.tar.gz -C /opt/qoder --strip-components=1; \
    rm /tmp/qoder.tar.gz; \
    cd /opt/qoder && npm ci --omit=dev --no-audit --no-fund; \
    npm i -g @qodercn-ai/qoderclicn --no-audit --no-fund

# 装配层
COPY build/supervisord.conf /etc/supervisord.conf
COPY build/entrypoint.sh /opt/hub/entrypoint.sh
COPY wirer/wire.py /opt/hub/wire.py
RUN chmod +x /opt/hub/entrypoint.sh && mkdir -p /data/logs

ENV AGG_PORT=8080 \
    WB_PORT=8788 \
    QODER_PORT=3000 \
    OC_PORT=13339 \
    TZ=Asia/Shanghai

EXPOSE 8080
# 8788 = wb 面板（OAuth 加账号），compose 默认只绑宿主 127.0.0.1
EXPOSE 8788
VOLUME ["/data"]

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/opt/hub/entrypoint.sh"]
