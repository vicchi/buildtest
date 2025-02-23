ARG UBUNTU_RELEASE=22.04
ARG VERSION
FROM ubuntu:${UBUNTU_RELEASE} AS build

### --------------------------------------------------------------------------------
### Start - build prep

SHELL ["/bin/sh", "-exc"]
ENV DEBIAN_FRONTEND=noninteractive

# - install Python 3.10 including installer tools
# - install Git and SSH to allow access to private GitHub repos as dependencies

RUN <<EOT
apt-get update -qy
apt-get install -qyy \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    git \
    openssh-client \
    python3 \
    python3-setuptools
mkdir -p "${HOME}"/.ssh
chmod 0600 "${HOME}"/.ssh
ssh-keyscan github.com >> "${HOME}"/.ssh/known_hosts
EOT

# - install uv, but just for this layer
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# - copy instead of hard linking (which uv will complain about)
# - compile to bytecode after installation for faster startup times
# - use the just installed Python version and don't (un-helpfully) download one
# - tell uv which Python binary to use
# - tell uv sync where to sync to

ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_DOWNLOADS=never \
    UV_PYTHON=/usr/bin/python3.10 \
    UV_PROJECT_ENVIRONMENT=/opt/vicchi

### End - build prep

### --------------------------------------------------------------------------------
### Start - dependencies prep

# - install runtime dependencies only, without the application itself
# - this layer will be cached until either uv.lock or pyproject.toml
#   change, these are mounted here into the build layer as we
#   don't need them at runtime

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=ssh \
    uv sync \
        --locked \
        --no-dev \
        --no-install-project

# - install everything else (the application itself), without dependencies
# - /src is temporary to this layer and won't be copied into the runtime layer

COPY . /src
WORKDIR /src

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=ssh \
    uv sync \
        --locked \
        --no-dev \
       --no-editable

### End - dependencies prep

### --------------------------------------------------------------------------------
### Start - runtime

ARG UBUNTU_RELEASE
FROM ubuntu:${UBUNTU_RELEASE}
ARG UBUNTU_RELEASE
ARG VERSION

SHELL ["/bin/sh", "-exc"]
ENV DEBIAN_FRONTEND=noninteractive

# - optional: don't run as root
# RUN <<EOT
# groupadd --system vicchi
# useradd --system --home-dir /opt/vicchi --gid vicchi --no-user-group vicchi
# EOT

# - setup runtime search paths

ENV PYTHONPATH=/opt/vicchi
ENV PATH=/opt/vicchi/bin:${PATH}
ENV VIRTUAL_ENV=/opt/vicchi

# - install software-properties-common to get add-apt-repository
# - install curl for health checks
# - install Python 3.10 without installer or development tools
# - install tini as a container init to allow signals to be correctly propagated

RUN <<EOT
apt-get update -qy
apt-get install -qyy \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    curl \
    python3 \
    tini
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOT

COPY ./docker/buildtest/files/docker-entrypoint.sh /opt/vicchi/
COPY --from=build /opt/vicchi /opt/vicchi
# - optional: don't run as root
# COPY --from=build --chown-vicchi:vicchi /opt/vicchi /opt/vicchi

WORKDIR /opt/vicchi

ENTRYPOINT ["/usr/bin/tini", "-v", "--", "/opt/vicchi/docker-entrypoint.sh"]
CMD ["testbed"]
STOPSIGNAL SIGINT
HEALTHCHECK CMD curl --silent --fail http://localhost:80/ping || exit 1

LABEL org.opencontainers.image.url="https://github.com/vicchi/buildtest"
LABEL org.opencontainers.image.documentation="https://github.com/vicchi/buildtest/blob/master/README.md"
LABEL org.opencontainers.image.source="https://github.com/vicchi/buildtest"
LABEL org.opencontainers.image.version=${VERSION}
LABEL org.opencontainers.image.revision=${VERSION}
LABEL org.opencontainers.image.vendor="Gary Gale"
LABEL org.opencontainers.image.licenses="BSD-3"
LABEL org.opencontainers.image.title="Docker and uv build test setup"
LABEL org.opencontainers.image.base.name=docker.io/ubuntu:${UBUNTU_RELEASE}

### End - runtime

### --------------------------------------------------------------------------------
### Start - smoke test

# - check that the installed Python version is what we expect
# - check that one of the dependencies can be imported
# - check that what we've installed can actually be imported

RUN <<EOT
python3 --version
python3 -Ic 'import whoami'
python3 -Ic 'import buildtest'
EOT

### End - smoke test
