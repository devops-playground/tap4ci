# Dockerfile: docker(1) container build file.

ARG DEB_DIST=stretch
FROM debian:${DEB_DIST}
ARG DEB_DIST=stretch

LABEL maintainer="Laurent Vallar <val@zbla.net>"
LABEL organization="DevOps Playground"

# Configured account
ARG DOCKER_USER=dev
ARG DOCKER_USER_UID=8888
ARG DOCKER_USER_GID=8888

# Set some build environment variables
ARG DEB_COMPONENTS="main contrib non-free"
ARG DEB_MIRROR_URL=http://deb.debian.org/debian
ARG DEB_PACKAGES="\
acl \
apt-transport-https \
bash-completion \
bison \
build-essential \
ca-certificates \
coreutils \
curl \
dirmngr \
figlet \
git-core \
gnupg \
less \
libbison-dev \
libffi-dev \
libgdbm-dev \
libncurses5-dev \
libreadline-dev \
libsigsegv2 \
libsodium18 \
libssl-dev \
libtinfo-dev \
libyaml-dev \
locales \
m4 \
make \
man-db \
ncurses-base \
ncurses-term \
openssh-client \
pass \
procps \
rsync \
ruby \
ruby-dev \
ssh \
sudo \
tmate \
tmux \
vim-nox \
zlib1g-dev \
"
ARG DEB_SECURITY_MIRROR_URL=http://security.debian.org

# NB processors
ARG NB_PROC=1

# Docker env
ARG DEB_DOCKER_GPGID=7EA0A9C3F273FCD8
ARG DEB_DOCKER_URL=https://download.docker.com/linux/debian

# If behind an HTTP proxy
ARG HTTP_PROXY=
ENV http_proxy "${HTTP_PROXY}"
ENV https_proxy "${HTTP_PROXY}"

# Tell debconf to run in non-interactive mode
ENV DEBIAN_FRONTEND noninteractive

# Set neutral language
ENV LC_ALL C.UTF-8
ENV LANG C.UTF-8

# Fix TERM
ENV TERM linux

# Ruby env
ARG RUBY_RELEASE=
ARG RUBY_LEVEL=
ARG CHRUBY_VERSION=
ARG RUBY_INSTALL_VERSION=
ARG RUBIES_TARBALL_CACHE_BASE_URL=
ARG RUBY_TARBALL_SHA256=

# Create and configure DOCKER_USER
RUN groupadd -g "${DOCKER_USER_GID}" "${DOCKER_USER}" \
  && useradd -m "${DOCKER_USER}" \
             -u "${DOCKER_USER_UID}" \
             -g "${DOCKER_USER}" \
             -G sudo \
             -s /bin/bash \
  && ( echo "${DOCKER_USER}:${DOCKER_USER}" | chpasswd ) \
  && echo 'gem: --no-ri --no-rdoc --no-document --suggestions' \
          > "/home/${DOCKER_USER}/.gemrc" \
  && chown "${DOCKER_USER}.${DOCKER_USER}" "/home/${DOCKER_USER}/.gemrc"

# Initialize sources.list & update all
RUN echo "deb ${DEB_MIRROR_URL} ${DEB_DIST} ${DEB_COMPONENTS}" \
         > /etc/apt/sources.list \
  && echo "deb ${DEB_MIRROR_URL} ${DEB_DIST}-updates ${DEB_COMPONENTS}" \
         >> /etc/apt/sources.list \
  && echo "deb ${DEB_MIRROR_URL} ${DEB_DIST}-proposed-updates ${DEB_COMPONENTS}" \
         >> /etc/apt/sources.list \
  && echo "deb ${DEB_MIRROR_URL} ${DEB_DIST}-backports ${DEB_COMPONENTS}" \
         >> /etc/apt/sources.list \
  && echo "deb ${DEB_SECURITY_MIRROR_URL} ${DEB_DIST}/updates ${DEB_COMPONENTS}" \
         >> /etc/apt/sources.list \
  && sed -e 's|#\(precedence\s\s*::ffff:0:0/96\s\s*100\).*$|\1|' \
         -ri /etc/gai.conf \
  && if [ -n "${HTTP_PROXY}" ]; then \
       echo "Acquire::http::proxy \"${HTTP_PROXY}\";" \
            > /etc/apt/apt.conf.d/11http-proxy; \
       echo "Acquire::https::proxy \"${HTTP_PROXY}\";" \
            >> /etc/apt/apt.conf.d/11http-proxy; \
     fi \
  && apt update \
  && apt -y dist-upgrade \
  && if [ "x${RUBY_RELEASE}" = 'x' ]; then \
    DEB_PACKAGES="${DEB_PACKAGES} ruby-bundler"; \
  fi \
  && apt install --no-install-recommends -y $DEB_PACKAGES \
  && apt -y autoremove \
  && apt clean \
  && if [ -f /etc/apt/apt.conf.d/11http-proxy ]; then \
       rm -f /etc/apt/apt.conf.d/11http-proxy; \
     fi \
  && echo 'if which figlet > /dev/null 2>&1; then figlet "$(hostname)"; fi' \
          >> /etc/bash.bashrc

# Set default Timezone
RUN echo Etc/UTC > /etc/timezone && dpkg-reconfigure -f noninteractive tzdata

# Set default locale
RUN echo LANG=C.UTF-8 > /etc/default/locale \
  && echo C.UTF-8 UTF-8 > /etc/locale.gen \
  && dpkg-reconfigure -f noninteractive locales

# Install Docker
RUN echo "deb ${DEB_DOCKER_URL} ${DEB_DIST} stable" \
         >> /etc/apt/sources.list.d/docker-ce.list \
  && if [ -n "${HTTP_PROXY}" ] ; then \
       GPG_HTTP_PROXY="--keyserver-options http-proxy=${HTTP_PROXY}"; \
     else \
       GPG_HTTP_PROXY='' ; \
     fi \
  && while ! ( \
       ok=1 ; \
       for server in $( \
         shuf -e hkp://ha.pool.sks-keyservers.net:80 \
                 hkp://ipv4.pool.sks-keyservers.net:80 \
                 hkp://keyserver.pgp.com:80 \
                 hkp://p80.sks-keyservers.net:80 \
                 hkp://pgp.mit.edu:80 \
                 hkp://pool.sks-keyservers.net:80 \
                 hkps://ha.pool.sks-keyservers.net \
                 hkps://ipv4.pool.sks-keyservers.net \
                 hkps://keyserver.pgp.com \
                 hkps://pgp.mit.edu \
                 hkps://pool.sks-keyservers.net \
       ) ; do \
         apt-key adv --no-tty \
                     ${GPG_HTTP_PROXY} \
                     --keyserver "${server}" \
                     --recv-keys "${DEB_DOCKER_GPGID}"; \
         ok=$? ; \
         if [ $ok -eq 0 ]; then \
           break ; \
         fi ; \
       done ; \
       if [ $ok -eq 0 ]; then \
         true ; \
       else \
         false ; \
       fi \
     ); do \
       sleep 1; \
     done \
  && if [ -n "${HTTP_PROXY}" ]; then \
       echo "Acquire::http::proxy \"${HTTP_PROXY}\";" \
         > /etc/apt/apt.conf.d/11http-proxy; \
       echo "Acquire::https::proxy \"${HTTP_PROXY}\";" \
         >> /etc/apt/apt.conf.d/11http-proxy; fi \
  && apt-get update \
  && apt-get install --no-install-recommends -y docker-ce \
  && apt install --no-install-recommends -y "ansible/${DEB_DIST}-backports" \
  && apt-get -y autoremove \
  && apt-get clean \
  && if [ -f /etc/apt/apt.conf.d/11http-proxy ]; then \
       rm -f /etc/apt/apt.conf.d/11http-proxy; \
     fi

# Install chruby
RUN if [ -n "${RUBY_RELEASE}" ]; then \
  curl -sL -o "/tmp/chruby-${CHRUBY_VERSION}.tar.gz" \
  "https://github.com/postmodern/chruby/archive/v${CHRUBY_VERSION}.tar.gz" && \
  tar -xzvf "/tmp/chruby-${CHRUBY_VERSION}.tar.gz" -C /tmp && \
  cd "/tmp/chruby-${CHRUBY_VERSION}" && \
  make install && \
  echo 'source /usr/local/share/chruby/chruby.sh' \
    >> /etc/profile.d/chruby.sh && \
  echo 'source /usr/local/share/chruby/auto.sh' \
    >> /etc/profile.d/chruby.sh ; \
  fi

# Install ruby-install
RUN if [ -n "${RUBY_RELEASE}" -a -n "${RUBY_INSTALL_VERSION}" ]; then \
  curl -sL -o "/tmp/ruby-install-${RUBY_INSTALL_VERSION}.tar.gz" \
    "https://github.com/postmodern/ruby-install/archive/\
v${RUBY_INSTALL_VERSION}.tar.gz" && \
  tar -xzvf "/tmp/ruby-install-${RUBY_INSTALL_VERSION}.tar.gz" -C /tmp && \
  cd "/tmp/ruby-install-${RUBY_INSTALL_VERSION}" && \
  make install ; \
  fi

# Install Ruby
RUN if [ -n "${RUBY_RELEASE}" -a -n "${RUBY_INSTALL_VERSION}" ]; then \
  mkdir -p /opt/rubies && \
  if curl -sL -o "/opt/rubies/ruby-${RUBY_RELEASE}.tar.xz" \
    "${RUBIES_TARBALL_CACHE_BASE_URL}/ruby-${RUBY_RELEASE}.tar.xz"; then \
    if [ "x${RUBY_TARBALL_SHA256}" = "x\
$(sha256sum /opt/rubies/ruby-${RUBY_RELEASE}.tar.xz|cut -f1 -d\ )" ]; then \
      tar --no-same-owner --owner=0 --group=0 \
          -xJf "/opt/rubies/ruby-${RUBY_RELEASE}.tar.xz" \
          -C /opt/rubies && \
      rm -f "/opt/rubies/ruby-${RUBY_RELEASE}.tar.xz" ; \
    else \
      echo "/opt/rubies/ruby-${RUBY_RELEASE}.tar.xz has a wrong sha256!" >&2 ; \
    fi ; \
  fi ; \
  if [ ! -x /opt/rubies/ruby-${RUBY_RELEASE}/bin/ruby ]; then \
    /usr/local/bin/ruby-install \
      -r /opt/rubies -c -j"${NB_PROC}" ruby "${RUBY_RELEASE}" ; \
  fi ; \
  /opt/rubies/ruby-${RUBY_RELEASE}/bin/gem uninstall \
    -i /opt/rubies/ruby-${RUBY_RELEASE}/lib/ruby/gems/${RUBY_LEVEL}@global \
    bundler && \
  /opt/rubies/ruby-${RUBY_RELEASE}/bin/gem install bundler ; \
fi

# Autoload chruby
COPY .bash_profile /home/${DOCKER_USER}/.bash_profile
RUN chown ${DOCKER_USER}:${DOCKER_USER} /home/${DOCKER_USER}/.bashrc

# Cleanups
RUN apt-get -y autoremove && apt-get clean && rm -rf /tmp/* /var/tmp/*
