if [ -f /usr/local/share/chruby/chruby.sh \
  -a -f /usr/local/share/chruby/auto.sh ]; then
  source /usr/local/share/chruby/chruby.sh
  source /usr/local/share/chruby/auto.sh
  echo "chruby/auto $(chruby --version | cut -f 2 -d\ ) profile loaded."
fi

source ${HOME}/.bashrc && echo "${HOME}/.bashrc sourced"
