# ~/.bash_profile: executed by bash command interpreter for login shells.

__status() {
  if [ -z "$NO_STATUS" ] ; then
    printf '\r%s…\e[0K' ".bashrc load: $*"
  fi
}

# load chruby environment
if [ -f /usr/local/share/chruby/chruby.sh \
  -a -f /usr/local/share/chruby/auto.sh ]; then
  source /usr/local/share/chruby/chruby.sh
  source /usr/local/share/chruby/auto.sh
  __status "chruby/auto $(chruby --version | cut -f 2 -d\ ) profile loaded."
fi

# prepend Ruby path if defined
if [ -n "${RUBY_PATH}" ]; then
  export PATH="${RUBY_PATH}:${PATH}"
  __status "Ruby path (${RUBY_PATH}) prepended to \$PATH."
fi

# configure tmate with ephemeral key
tmate_conf="${HOME}/.tmate.conf"
if [ ! -f "${tmate_conf}" ]; then
  echo 'set-option -g tmate-identity id_rsa_tmate' > "${tmate_conf}" \
    && __status "${tmate_conf} created"
  tmate_key="${HOME}/.ssh/id_rsa_tmate"
  if [ ! -f "${tmate_key}" ]; then
    yes '' | ssh-keygen -t rsa -b 4096 -f "${tmate_key}" -N "" > /dev/null \
      && __status "${tmate_key} created"
  fi
fi

# load .bashrc if present
bashrc="${HOME}/.bashrc"
if [ -f "${bashrc}" ]; then
  source "${bashrc}" && __status "${bashrc} sourced"
fi

[ -z "$NO_STATUS" ] && printf "\r\e[0K" || true
