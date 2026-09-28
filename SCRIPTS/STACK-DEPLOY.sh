#!/usr/bin/env bash
# install.sh — réplique du poste de dev Fedora 44, en un seul script interactif.
#
# Au lancement, un menu propose de cocher :
#   [x] Stack de développement  paquets système, Docker CE, Go, Python (uv,
#                               ruff), Node (fnm, pnpm), outils Go et CLI
#   [x] Configuration ZSH       design complet : prompt RAM/CPU/Git, couleurs,
#                               complétion, plugins, zsh shell par défaut
#   [x] Mise à jour système     dnf upgrade --refresh avant l'installation
#
# Usage :
#   bash install.sh                      menu interactif
#   bash install.sh --stack --zsh        sans menu (options combinables)
#   bash install.sh --all                tout, sans menu
# Options : --stack, --zsh, --upgrade, --no-upgrade, --all, -h/--help.
# Sans menu, la mise à jour système est faite sauf --no-upgrade.
# Variable STRICT=1 : échoue si une version rpm épinglée n'est plus disponible
# (défaut : repli sur la version courante, signalé dans le rapport final).
#
# À lancer depuis le compte utilisateur, PAS en root : sudo est demandé une
# fois pour la partie système. Idempotent : relançable à volonté, chaque étape
# est sautée si l'état voulu est déjà en place. Les fichiers de config
# existants qui diffèrent sont sauvegardés dans le dossier du script.
#
# Référence : machine d'origine au 2026-09-28. Les fichiers zsh sont embarqués
# octet pour octet (contrôle sha256 à l'écriture).
set -euo pipefail

SETUP_DIR=${SETUP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
TS=$(date +%Y%m%d_%H%M%S)
STRICT=${STRICT:-0}

BIN_DIR=$HOME/.local/bin
export GOPATH=$HOME/.local/share/go
export GOBIN=$BIN_DIR
export FNM_DIR=$HOME/.local/share/fnm
export PNPM_HOME=$HOME/.local/share/pnpm
export PATH=$PNPM_HOME/bin:$FNM_DIR:$BIN_DIR:$PATH

# =============================================================================
# Versions de référence
# =============================================================================
# Paquets épinglés au format nom|EVR (epoch:version-release). Fedora ne garde
# dans ses dépôts que la version de sortie (fedora) et la dernière mise à jour
# (updates) : une version intermédiaire peut disparaître. Dans ce cas, repli
# sur la version courante (ou échec si STRICT=1).

# Socle commun aux deux choix (zsh pour le shell, git pour les plugins zsh et Go).
RPM_CORE_PINNED=(
  "zsh|5.9-21.fc44"
  "git|2.55.0-1.fc44"
)
RPM_STACK_PINNED=(
  "gcc|16.2.1-2.fc44"
  "gcc-c++|16.2.1-2.fc44"
  "make|1:4.4.1-12.fc44"
  "openssl-devel|1:3.5.8-1.fc44"
  "golang|1.26.8-2.fc44"
  "uv|0.12.15-1.fc44"
  "ruff|0.16.8-1.fc44"
  "gh|2.97.0-2.fc44"
  "postgresql|18.6-1.fc44"
  "yq|4.53.3-1.fc44"
  "ripgrep|15.2.0-1.fc44"
  "fd-find|10.4.2-4.fc44"
  "fzf|0.74.4-1.fc44"
  "just|1.57.0-1.fc44"
  "direnv|2.37.1-6.fc44"
  "ShellCheck|0.11.0-4.fc44"
  "webkit2gtk4.1-devel|2.54.0-2.fc44"
  "gtk3-devel|3.24.52-2.fc44"
)
# Docker CE : le dépôt docker.com garde toutes les versions, l'épinglage tient.
DOCKER_PINNED=(
  "docker-ce|3:29.8.1-1.fc44"
  "docker-ce-cli|1:29.8.1-1.fc44"
  "containerd.io|2.3.6-1.fc44"
  "docker-buildx-plugin|0.37.1-1.fc44"
  "docker-compose-plugin|5.5.1-1.fc44"
)
# Outils de base, présents sur l'édition Server : ils suivent les mises à jour
# du système (non épinglés). dnf5-plugins fournit `dnf config-manager`, requis
# pour ajouter le dépôt Docker (absent de certaines installations minimales).
RPM_STACK_BASE=(
  dnf5-plugins
  pkgconf-pkg-config curl wget jq bat rsync tree tar gzip xz unzip
  lsof nmap-ncat bind-utils iproute tcpdump
)
# Requis par le prompt zsh : LANG=fr_FR.UTF-8, calcul CPU (bc), top (procps-ng).
RPM_ZSH_BASE=(glibc-langpack-fr bc procps-ng)

GO_TOOLS=(
  "sqlc|github.com/sqlc-dev/sqlc/cmd/sqlc|github.com/sqlc-dev/sqlc|v1.31.1"
  "air|github.com/air-verse/air|github.com/air-verse/air|v1.67.4"
  "templ|github.com/a-h/templ/cmd/templ|github.com/a-h/templ|v0.3.1020"
  "goose|github.com/pressly/goose/v3/cmd/goose|github.com/pressly/goose/v3|v3.28.0"
  "lazygit|github.com/jesseduffield/lazygit|github.com/jesseduffield/lazygit|v0.65.1"
  "shfmt|mvdan.cc/sh/v3/cmd/shfmt|mvdan.cc/sh/v3|v3.14.1"
  "wails|github.com/wailsapp/wails/v2/cmd/wails|github.com/wailsapp/wails/v2|v2.16.0"
)
GOLANGCI_VERSION=v2.14.0
XH_VERSION=v0.26.2
XH_SHA256=8c53b6a23435754f9e2ea8ab8c0d0296a1921404b88132cf9b364ff6e8c22a6e
FNM_VERSION=v1.39.0
FNM_SHA256=7807664f39d39fc518da1c35ba0181e4b3267603c4b1dedeb4b5fc6ae440a224
NODE_VERSION=v24.21.0
PNPM_VERSION=12.6.0

# Plugins zsh : nom|dépôt|commit exact.
ZSH_PLUGINS=(
  "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting.git|0bfcb582e71d3abe604ce67bc0fe5a21f377507e"
  "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions|85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5"
  "zsh-completions|https://github.com/zsh-users/zsh-completions|b5e8e0a22deb05a807bb8655aef809a29f3cffed"
)

# =============================================================================
# Helpers
# =============================================================================
log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf 'ERREUR: %s\n' "$*" >&2; exit 1; }
DRIFT=()

# Nettoyage à la sortie : curseur réaffiché, ticket sudo relâché.
SUDO_KEEPALIVE=
cleanup() {
  [[ -t 1 ]] && printf '\e[?25h'
  [[ -z $SUDO_KEEPALIVE ]] || kill "$SUDO_KEEPALIVE" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# install_rpms <paquets nom|EVR...> : installe les absents dans la version
# épinglée, sans jamais rétrograder un paquet déjà présent. Tout écart de
# version est consigné dans DRIFT.
install_rpms() {
  local e name evr specs=() missing=() have
  for e in "$@"; do
    name=${e%%|*}
    rpm -q "$name" >/dev/null 2>&1 || specs+=("$name-${e#*|}")
  done
  if (( ${#specs[@]} )); then
    sudo dnf install -y --skip-unavailable "${specs[@]}"
  fi
  for e in "$@"; do
    name=${e%%|*}
    rpm -q "$name" >/dev/null 2>&1 || missing+=("$name")
  done
  if (( ${#missing[@]} )); then
    (( STRICT == 0 )) || die "versions épinglées indisponibles : ${missing[*]} (STRICT=1)"
    info "versions épinglées indisponibles, repli sur la version courante : ${missing[*]}"
    sudo dnf install -y "${missing[@]}"
  fi
  for e in "$@"; do
    name=${e%%|*}; evr=${e#*|}
    have=$(rpm -q --qf '%{EPOCH}:%{VERSION}-%{RELEASE}' "$name" | sed 's/^(none)://; s/^0://')
    [[ $have == "${evr#0:}" ]] || DRIFT+=("rpm $name : référence $evr, installé $have")
  done
}

backup() {
  local f=$1 dest
  dest="$SETUP_DIR/$(basename "$f" | sed 's/^\.//').backup.$TS"
  [[ -e $dest ]] && return 0   # une seule sauvegarde par fichier et par exécution
  cp -p -- "$f" "$dest"
  info "sauvegarde : $dest"
}

# write_file <destination> <sha256 attendu> : écrit stdin tel quel. Sauvegarde
# l'existant s'il diffère, puis contrôle l'empreinte du résultat.
write_file() {
  local dest=$1 sum=$2 tmp
  tmp=$(mktemp)
  cat > "$tmp"
  [[ $(sha256sum < "$tmp" | cut -d' ' -f1) == "$sum" ]] || die "empreinte embarquée invalide pour $dest (script corrompu ?)"
  mkdir -p "$(dirname "$dest")"
  if [[ -f $dest ]] && cmp -s "$tmp" "$dest"; then
    info "$dest : déjà à jour"
  else
    [[ ! -s $dest ]] || backup "$dest"
    cat "$tmp" > "$dest"
    info "$dest : écrit"
  fi
  rm -f -- "$tmp"
}

# upsert_block <fichier> <nom> <contenu> : bloc entre marqueurs
# « # >>> setup:<nom> >>> » / « # <<< setup:<nom> <<< », remplacé en place,
# jamais dupliqué. Sert à greffer les hooks de la stack dans un ~/.zshrc
# personnel quand la configuration ZSH n'est pas installée.
upsert_block() {
  local file=$1 name=$2 body=$3
  local begin="# >>> setup:$name >>>" end="# <<< setup:$name <<<"
  local tmp blk
  tmp=$(mktemp); blk=$(mktemp)
  printf '%s\n%s\n%s\n' "$begin" "$body" "$end" > "$blk"
  [[ -e $file ]] || : > "$file"
  if grep -qxF -- "$begin" "$file"; then
    awk -v b="$begin" -v e="$end" -v blk="$blk" '
      $0 == b { if (!done) { while ((getline l < blk) > 0) print l; done = 1 } skip = 1; next }
      skip && $0 == e { skip = 0; next }
      !skip' "$file" > "$tmp"
  else
    { cat "$file"; if [[ -s $file ]]; then echo; fi; cat "$blk"; } > "$tmp"
  fi
  if cmp -s "$tmp" "$file"; then
    info "$file : bloc '$name' déjà à jour"
  else
    [[ ! -s $file ]] || backup "$file"
    cat "$tmp" > "$file"
    info "$file : bloc '$name' écrit"
  fi
  rm -f -- "$tmp" "$blk"
}

# fetch <url> <sha256> <destination> : téléchargement vérifié.
fetch() {
  curl -fsSL -o "$3" "$1"
  [[ $(sha256sum < "$3" | cut -d' ' -f1) == "$2" ]] || die "sha256 inattendu pour $1"
}

# =============================================================================
# Sélection : options en ligne de commande ou menu interactif
# =============================================================================
DO_STACK=0; DO_ZSH=0; DO_UPGRADE=1; CLI=0

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

for arg in "$@"; do
  case $arg in
    --stack)      DO_STACK=1; CLI=1 ;;
    --zsh)        DO_ZSH=1; CLI=1 ;;
    --all)        DO_STACK=1; DO_ZSH=1; CLI=1 ;;
    --upgrade)    DO_UPGRADE=1 ;;
    --no-upgrade) DO_UPGRADE=0 ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "option inconnue : $arg (voir --help)" ;;
  esac
done

# Menu à cases à cocher, bash pur (aucune dépendance) : ↑/↓ ou j/k pour
# naviguer, Espace pour cocher, 1-3 en raccourci, Entrée pour valider, q pour
# quitter. Couleurs reprises du prompt zsh.
MENU_LABELS=(
  "Stack de développement"
  "Configuration ZSH"
  "Mise à jour complète du système"
)
MENU_DETAILS=(
  "gcc, Go, Python (uv, ruff), Node (fnm, pnpm), Docker CE, outils Go, CLI"
  "prompt RAM/CPU/Git, couleurs, complétion, plugins, zsh par défaut"
  "dnf upgrade --refresh avant l'installation"
)
MENU_SEL=(1 1 1)

# NB : les calculs passent par $(( )) et jamais par (( )) seul, qui renvoie
# un code d'erreur quand le résultat vaut 0 (fatal avec set -e).
menu_draw() {
  local i mark cursor bold
  for i in "${!MENU_LABELS[@]}"; do
    if [[ ${MENU_SEL[$i]} == 1 ]]; then mark=$'\e[38;5;71m[x]\e[0m'; else mark=$'\e[38;5;244m[ ]\e[0m'; fi
    if [[ $i == "$MENU_CUR" ]]; then cursor=$'\e[38;5;107m❯\e[0m'; bold=$'\e[1m'; else cursor=' '; bold=; fi
    printf '\e[K %s %s %s%s\e[0m\n' "$cursor" "$mark" "$bold" "${MENU_LABELS[$i]}"
    printf '\e[K       \e[38;5;137m%s\e[0m\n' "${MENU_DETAILS[$i]}"
  done
  printf '\e[K\n\e[K \e[38;5;101m↑/↓ naviguer · Espace cocher · Entrée valider · q quitter\e[0m\n'
}

menu() {
  local key rest n=${#MENU_LABELS[@]}
  local lines=$(( n * 2 + 2 ))
  MENU_CUR=0
  printf '\n \e[38;5;58m╭─\e[0m \e[1;38;5;107mInstallation du poste de dev Fedora 44\e[0m\n'
  printf ' \e[38;5;58m╰─\e[0m \e[38;5;137mcocher ce qu'"'"'il faut installer\e[0m\n\n'
  printf '\e[?25l'
  menu_draw
  while true; do
    IFS= read -rsn1 key </dev/tty
    case $key in
      $'\e')
        IFS= read -rsn2 -t 0.05 rest </dev/tty || rest=
        case $rest in
          '[A') MENU_CUR=$(( (MENU_CUR + n - 1) % n )) ;;
          '[B') MENU_CUR=$(( (MENU_CUR + 1) % n )) ;;
        esac ;;
      k) MENU_CUR=$(( (MENU_CUR + n - 1) % n )) ;;
      j) MENU_CUR=$(( (MENU_CUR + 1) % n )) ;;
      ' ') MENU_SEL[MENU_CUR]=$(( 1 - MENU_SEL[MENU_CUR] )) ;;
      [1-9]) if [[ $key -le $n ]]; then MENU_SEL[key - 1]=$(( 1 - MENU_SEL[key - 1] )); fi ;;
      q|Q) printf '\e[?25h\nAbandon, rien n'"'"'a été installé.\n'; exit 0 ;;
      '') if [[ ${MENU_SEL[0]}${MENU_SEL[1]} == *1* ]]; then break; fi ;;  # au moins stack ou ZSH
    esac
    printf '\e[%dA' "$lines"
    menu_draw
  done
  printf '\e[?25h'
  DO_STACK=${MENU_SEL[0]}; DO_ZSH=${MENU_SEL[1]}; DO_UPGRADE=${MENU_SEL[2]}
}

if (( ! CLI )); then
  [[ -t 0 && -t 1 ]] || die "pas de terminal interactif : utiliser --stack, --zsh ou --all (voir --help)"
  menu
fi
(( DO_STACK || DO_ZSH )) || die "rien à installer : cocher au moins la stack ou ZSH"

yesno() { (( $1 )) && echo oui || echo non; }
echo
echo "Sélection :"
echo "  Stack de développement : $(yesno "$DO_STACK")"
echo "  Configuration ZSH      : $(yesno "$DO_ZSH")"
echo "  Mise à jour système    : $(yesno "$DO_UPGRADE")"
if (( ! CLI )); then
  read -rp "Lancer l'installation ? [O/n] " ans </dev/tty
  [[ ${ans:-o} =~ ^[oOyY]$ ]] || { echo "Abandon, rien n'a été installé."; exit 0; }
fi

# =============================================================================
# Garde-fous
# =============================================================================
[[ $EUID -ne 0 ]] || die "lancer depuis le compte utilisateur, sans sudo : bash $0"
# shellcheck source=/dev/null
. /etc/os-release
[[ ${ID:-} == fedora && ${VERSION_ID:-} == 44 ]] || die "prévu pour Fedora 44 (détecté : ${PRETTY_NAME:-inconnu})"
[[ $(uname -m) == x86_64 ]] || die "prévu pour x86_64 (détecté : $(uname -m))"
if (( DO_STACK )); then
  for p in moby-engine podman-docker; do
    ! rpm -q "$p" >/dev/null 2>&1 || die "$p est installé et entre en conflit avec Docker CE : à retirer d'abord (sudo dnf remove $p)"
  done
  # Photo du home avant installation (utilisée par verify.sh), prise une seule fois.
  [[ -f $SETUP_DIR/home.before ]] || ls -A "$HOME" > "$SETUP_DIR/home.before"
fi

# sudo : mot de passe demandé une fois, puis ticket entretenu en tâche de fond
# pendant la partie système.
sudo -v
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE=$!

# =============================================================================
# 1. Système (sudo)
# =============================================================================
if (( DO_UPGRADE )); then
  log "Système — dnf upgrade --refresh"
  sudo dnf upgrade -y --refresh
fi

log "Système — paquets de base"
base=()
(( ! DO_STACK )) || base+=("${RPM_STACK_BASE[@]}")
(( ! DO_ZSH ))   || base+=("${RPM_ZSH_BASE[@]}")
if (( ${#base[@]} )); then sudo dnf install -y "${base[@]}"; fi

log "Système — paquets épinglés"
pinned=("${RPM_CORE_PINNED[@]}")
(( ! DO_STACK )) || pinned+=("${RPM_STACK_PINNED[@]}")
install_rpms "${pinned[@]}"

if (( DO_STACK )); then
  log "Système — Docker CE (dépôt officiel docker.com)"
  if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
    sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
  else
    info "dépôt docker-ce déjà configuré"
  fi
  install_rpms "${DOCKER_PINNED[@]}"
  sudo systemctl enable --now docker
  if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
    info "$USER déjà dans le groupe docker"
  else
    sudo usermod -aG docker "$USER"
    info "$USER ajouté au groupe docker (effectif à la prochaine connexion)"
  fi
fi

if (( DO_ZSH )); then
  log "Système — zsh comme shell de connexion"
  if [[ $(getent passwd "$USER" | cut -d: -f7) == /usr/bin/zsh ]]; then
    info "déjà /usr/bin/zsh"
  else
    sudo usermod -s /usr/bin/zsh "$USER"
    info "shell de connexion : /usr/bin/zsh"
  fi
fi

kill "$SUDO_KEEPALIVE" 2>/dev/null || true
SUDO_KEEPALIVE=

# =============================================================================
# 2. Stack : environnement et outils utilisateur (versions épinglées)
# =============================================================================
if (( DO_STACK )); then
  # Écrits avant les outils : GOPATH/GOBIN et GOTOOLCHAIN doivent être en place
  # avant le premier `go install`.
  log "Stack — ~/.zshenv (Go, fnm, pnpm pour tous les zsh)"
  write_file "$HOME/.zshenv" 7ddb2e05d8b153a3cdb9eb2ebe126f04c463b2e52a9d105b206bfd5f4ec4d155 <<'__ZSHENV_EOF__'
# >>> setup:go >>>
export GOPATH="$HOME/.local/share/go"
export GOBIN="$HOME/.local/bin"
typeset -U path PATH
path=("$HOME/.local/bin" $path)
# <<< setup:go <<<

# >>> setup:node >>>
export FNM_DIR="$HOME/.local/share/fnm"
export PNPM_HOME="$HOME/.local/share/pnpm"
typeset -U path PATH
path=("$PNPM_HOME/bin" "$FNM_DIR/aliases/default/bin" "$FNM_DIR" $path)
# <<< setup:node <<<
__ZSHENV_EOF__

  log "Stack — ~/.config/go/env (GOTOOLCHAIN=auto)"
  write_file "$HOME/.config/go/env" 68ac107393e093bc2017b0ffd85b3fc362f0cd4faf39daa403895d1f66624df7 <<'__GOENV_EOF__'
GOTOOLCHAIN=auto
__GOENV_EOF__

  mkdir -p "$BIN_DIR" "$HOME/.local/share"
  [[ $(go env GOTOOLCHAIN) == auto ]] || die "GOTOOLCHAIN n'est pas en auto"

  log "Stack — outils Go (go install)"
  for e in "${GO_TOOLS[@]}"; do
    IFS='|' read -r bin pkg mod ver <<<"$e"
    have=$(go version -m "$BIN_DIR/$bin" 2>/dev/null | awk -v m="$mod" '$1 == "mod" && $2 == m {print $3}' || true)
    if [[ $have == "$ver" ]]; then
      info "$bin $ver : déjà installé"
    else
      info "go install $pkg@$ver"
      # sqlc embarque un parseur C (cgo).
      CGO_ENABLED=1 go install "$pkg@$ver"
    fi
  done

  log "Stack — golangci-lint $GOLANGCI_VERSION (binaire officiel)"
  if grep -qF "version ${GOLANGCI_VERSION#v} " <<<"$("$BIN_DIR/golangci-lint" version 2>/dev/null || true)"; then
    info "déjà en $GOLANGCI_VERSION"
  else
    curl -sSfL https://golangci-lint.run/install.sh | sh -s -- -b "$BIN_DIR" "$GOLANGCI_VERSION"
  fi

  log "Stack — xh $XH_VERSION"
  if [[ $("$BIN_DIR/xh" --version 2>/dev/null | head -n1) == "xh ${XH_VERSION#v}" ]]; then
    info "déjà en $XH_VERSION"
  else
    tmp=$(mktemp -d)
    fetch "https://github.com/ducaale/xh/releases/download/$XH_VERSION/xh-$XH_VERSION-x86_64-unknown-linux-musl.tar.gz" "$XH_SHA256" "$tmp/xh.tgz"
    tar -xzf "$tmp/xh.tgz" -C "$tmp" --strip-components=1
    install -m 755 "$tmp/xh" "$BIN_DIR/xh"
    rm -rf -- "$tmp"
    info "xh installé"
  fi
  ln -sfn "$BIN_DIR/xh" "$BIN_DIR/xhs"

  log "Stack — fnm $FNM_VERSION"
  if [[ $("$FNM_DIR/fnm" --version 2>/dev/null) == "fnm ${FNM_VERSION#v}" ]]; then
    info "déjà en $FNM_VERSION"
  else
    tmp=$(mktemp -d)
    fetch "https://github.com/Schniz/fnm/releases/download/$FNM_VERSION/fnm-linux.zip" "$FNM_SHA256" "$tmp/fnm.zip"
    mkdir -p "$FNM_DIR"
    unzip -oq "$tmp/fnm.zip" -d "$tmp"
    install -m 755 "$tmp/fnm" "$FNM_DIR/fnm"
    rm -rf -- "$tmp"
    info "fnm installé"
  fi

  log "Stack — Node.js $NODE_VERSION (fnm)"
  if fnm ls | grep -qF "$NODE_VERSION"; then
    info "$NODE_VERSION déjà installé"
  else
    fnm install "$NODE_VERSION"
  fi
  fnm default "$NODE_VERSION"
  export PATH=$FNM_DIR/aliases/default/bin:$PATH
  info "node $(node --version), npm $(npm --version)"

  log "Stack — pnpm $PNPM_VERSION (installeur standalone)"
  if [[ $(pnpm --version 2>/dev/null) == "$PNPM_VERSION" ]]; then
    info "déjà en $PNPM_VERSION"
  else
    [[ ! -s $HOME/.zshrc ]] || backup "$HOME/.zshrc"
    curl -fsSL https://get.pnpm.io/install.sh | env PNPM_HOME="$PNPM_HOME" PNPM_VERSION="$PNPM_VERSION" SHELL=/usr/bin/zsh sh -
  fi
  # L'installeur pnpm ajoute son bloc « # pnpm … # pnpm end » à ~/.zshrc : il
  # ferait doublon avec ~/.zshenv, on le retire.
  if [[ -f $HOME/.zshrc ]] && grep -qxF '# pnpm' "$HOME/.zshrc"; then
    backup "$HOME/.zshrc"
    tmp=$(mktemp)
    awk '$0 == "# pnpm" { skip = 1; next } skip && $0 == "# pnpm end" { skip = 0; next } !skip' "$HOME/.zshrc" > "$tmp"
    cat "$tmp" > "$HOME/.zshrc"
    rm -f -- "$tmp"
    info "$HOME/.zshrc : bloc '# pnpm' (installeur) retiré"
  fi

  # Sans la configuration ZSH, les hooks interactifs de la stack sont greffés
  # dans le ~/.zshrc existant (avec la configuration ZSH, ils y sont déjà).
  if (( ! DO_ZSH )); then
    log "Stack — hooks fnm/direnv dans ~/.zshrc (bloc setup:dev)"
    upsert_block "$HOME/.zshrc" dev "$(cat <<'EOF'
if (( $+commands[fnm] )); then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi
if (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
fi
EOF
)"
  fi
fi

# =============================================================================
# 3. Configuration ZSH (design complet)
# =============================================================================
if (( DO_ZSH )); then
  log "ZSH — plugins (commits épinglés)"
  for e in "${ZSH_PLUGINS[@]}"; do
    IFS='|' read -r name url sha <<<"$e"
    dir=$HOME/.zsh/plugins/$name
    if [[ -d $dir/.git ]] && [[ $(git -C "$dir" rev-parse HEAD) == "$sha" ]]; then
      info "$name : déjà au commit ${sha:0:7}"
      continue
    fi
    [[ -d $dir/.git ]] || { mkdir -p "$dir"; git -C "$dir" init -q; git -C "$dir" remote add origin "$url"; }
    git -C "$dir" fetch -q --depth 1 origin "$sha"
    git -C "$dir" -c advice.detachedHead=false checkout -q --force FETCH_HEAD
    info "$name : ${sha:0:7}"
  done

  log "ZSH — plugin git (oh-my-zsh, copie autonome)"
  write_file "$HOME/.zsh/plugins/git/git.plugin.zsh" f83f37a98de566bb911f9bf70c48eeb28eae847a38f5817d675293656aba557e <<'__GITPLUGIN_EOF__'
# Git version checking
autoload -Uz is-at-least
git_version="${${(As: :)$(git version 2>/dev/null)}[3]}"

#
# Functions Current
# (sorted alphabetically by function name)
# (order should follow README)
#

# Check for develop and similarly named branches
function git_develop_branch() {
  command git rev-parse --git-dir &>/dev/null || return
  local branch
  for branch in dev devel develop development; do
    if command git show-ref -q --verify refs/heads/$branch; then
      echo $branch
      return 0
    fi
  done

  echo develop
  return 1
}

# Get the default branch name from common branch names or fallback to remote HEAD
function git_main_branch() {
  command git rev-parse --git-dir &>/dev/null || return
  
  local remote ref
  
  for ref in refs/{heads,remotes/{origin,upstream}}/{main,trunk,mainline,default,stable,master}; do
    if command git show-ref -q --verify $ref; then
      echo ${ref:t}
      return 0
    fi
  done
  
  # Fallback: try to get the default branch from remote HEAD symbolic refs
  for remote in origin upstream; do
    ref=$(command git rev-parse --abbrev-ref $remote/HEAD 2>/dev/null)
    if [[ $ref == $remote/* ]]; then
      echo ${ref#"$remote/"}; return 0
    fi
  done

  # If no main branch was found, fall back to master but return error
  echo master
  return 1
}

function gbcopy() {
  command git rev-parse --git-dir &>/dev/null || return

  local branch
  branch="$(git_current_branch)" || return
  [[ -n "$branch" ]] || return 1

  print -rn -- "$branch" | clipcopy
}

function grename() {
  if [[ -z "$1" || -z "$2" ]]; then
    echo "Usage: $0 old_branch new_branch"
    return 1
  fi

  # Rename branch locally
  git branch -m "$1" "$2"
  # Rename branch in origin remote
  if git push origin :"$1"; then
    git push --set-upstream origin "$2"
  fi
}

#
# Functions Work in Progress (WIP)
# (sorted alphabetically by function name)
# (order should follow README)
#

# Similar to `gunwip` but recursive "Unwips" all recent `--wip--` commits not just the last one
function gunwipall() {
  local _commit=$(git log --grep='--wip--' --invert-grep --max-count=1 --format=format:%H)

  # Check if a commit without "--wip--" was found and it's not the same as HEAD
  if [[ "$_commit" != "$(git rev-parse HEAD)" ]]; then
    git reset $_commit || return 1
  fi
}

# Warn if the current branch is a WIP
function work_in_progress() {
  command git -c log.showSignature=false log -n 1 2>/dev/null | grep -q -- "--wip--" && echo "WIP!!"
}

#
# Aliases
# (sorted alphabetically by command)
# (order should follow README)
# (in some cases force the alias order to match README, like for example gke and gk)
#

alias grt='cd "$(git rev-parse --show-toplevel || echo .)"'

function ggpnp() {
  if [[ $# == 0 ]]; then
    ggl && ggp
  else
    ggl "${*}" && ggp "${*}"
  fi
}
compdef _git ggpnp=git-checkout

alias ggpur='ggu'
alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gapa='git add --patch'
alias gau='git add --update'
alias gav='git add --verbose'
alias gwip='git add -A; git rm $(git ls-files --deleted) 2> /dev/null; git commit --no-verify --no-gpg-sign --message "--wip-- [skip ci]"'
alias gam='git am'
alias gama='git am --abort'
alias gamc='git am --continue'
alias gamscp='git am --show-current-patch'
alias gams='git am --skip'
alias gap='git apply'
alias gapt='git apply --3way'
alias gbs='git bisect'
alias gbsb='git bisect bad'
alias gbsg='git bisect good'
alias gbsn='git bisect new'
alias gbso='git bisect old'
alias gbsr='git bisect reset'
alias gbss='git bisect start'
alias gbl='git blame -w'
alias gb='git branch'
alias gba='git branch --all'
alias gbd='git branch --delete'
alias gbD='git branch --delete --force'

function gbda() {
  git branch --no-color --merged | command grep -vE "^([+*]|\s*($(git_main_branch)|$(git_develop_branch))\s*$)" | command xargs git branch --delete 2>/dev/null
}

# Copied and modified from James Roeder (jmaroeder) under MIT License
# https://github.com/jmaroeder/plugin-git/blob/216723ef4f9e8dde399661c39c80bdf73f4076c4/functions/gbda.fish
function gbds() {
  local default_branch
  default_branch=$(git_main_branch) \
    || default_branch=$(git_develop_branch)

  git for-each-ref refs/heads/ "--format=%(refname:short)" | \
    while read branch; do
      local merge_base=$(git merge-base $default_branch $branch)
      if [[ $(git cherry $default_branch $(git commit-tree $(git rev-parse $branch\^{tree}) -p $merge_base -m _)) = -* ]]; then
        git branch -D $branch
      fi
    done
}

alias gbgd='LANG=C git branch --no-color -vv | grep ": gone\]" | cut -c 3- | awk '"'"'{print $1}'"'"' | xargs git branch -d'
alias gbgD='LANG=C git branch --no-color -vv | grep ": gone\]" | cut -c 3- | awk '"'"'{print $1}'"'"' | xargs git branch -D'
alias gbm='git branch --move'
alias gbnm='git branch --no-merged'
alias gbr='git branch --remotes'
alias ggsup='git branch --set-upstream-to=origin/$(git_current_branch)'
alias gbg='LANG=C git branch -vv | grep ": gone\]"'
alias gco='git checkout'
alias gcor='git checkout --recurse-submodules'
alias gcb='git checkout -b'
alias gcB='git checkout -B'
alias gcd='git checkout $(git_develop_branch)'
alias gcm='git checkout $(git_main_branch)'
alias gcp='git cherry-pick'
alias gcpa='git cherry-pick --abort'
alias gcpc='git cherry-pick --continue'
alias gclean='git clean --interactive -d'
alias gcl='git clone --recurse-submodules'
alias gclf='git clone --recursive --shallow-submodules --filter=blob:none --also-filter-submodules'

function gccd() {
  setopt localoptions extendedglob

  # get repo URI from args based on valid formats: https://git-scm.com/docs/git-clone#URLS
  local repo="${${@[(r)(ssh://*|git://*|ftp(s)#://*|http(s)#://*|*@*)(.git/#)#]}:-$_}"

  # clone repository and exit if it fails
  command git clone --recurse-submodules "$@" || return

  # if last arg passed was a directory, that's where the repo was cloned
  # otherwise parse the repo URI and use the last part as the directory
  [[ -d "$_" ]] && cd "$_" || cd "${${repo:t}%.git/#}"
}
compdef _git gccd=git-clone

alias gcam='git commit --all --message'
alias gcas='git commit --all --signoff'
alias gcasm='git commit --all --signoff --message'
alias gcs='git commit --gpg-sign'
alias gcss='git commit --gpg-sign --signoff'
alias gcssm='git commit --gpg-sign --signoff --message'
alias gcmsg='git commit --message'
alias gcsm='git commit --signoff --message'
alias gc='git commit --verbose'
alias gca='git commit --verbose --all'
alias gca!='git commit --verbose --all --amend'
alias gcan!='git commit --verbose --all --no-edit --amend'
alias gcans!='git commit --verbose --all --signoff --no-edit --amend'
alias gcann!='git commit --verbose --all --date=now --no-edit --amend'
alias gc!='git commit --verbose --amend'
alias gcn='git commit --verbose --no-edit'
alias gcn!='git commit --verbose --no-edit --amend'
alias gcf='git config --list'
alias gcfu='git commit --fixup'
alias gdct='git describe --tags $(git rev-list --tags --max-count=1)'
alias gd='git diff'
alias gdca='git diff --cached'
alias gdcw='git diff --cached --word-diff'
alias gds='git diff --staged'
alias gdw='git diff --word-diff'

function gdv() { git diff -w "$@" | view - }
compdef _git gdv=git-diff

alias gdup='git diff @{upstream}'

function gdnolock() {
  git diff "$@" ":(exclude)package-lock.json" ":(exclude)*.lock"
}
compdef _git gdnolock=git-diff

alias gdt='git diff-tree --no-commit-id --name-only -r'
alias gf='git fetch'
# --jobs=<n> was added in git 2.8
is-at-least 2.8 "$git_version" \
  && alias gfa='git fetch --all --tags --prune --jobs=10' \
  || alias gfa='git fetch --all --tags --prune'
alias gfo='git fetch origin'
alias gg='git gui citool'
alias gga='git gui citool --amend'
alias ghh='git help'
alias glgg='git log --graph'
alias glgga='git log --graph --decorate --all'
alias glgm='git log --graph --max-count=10'
alias glods='git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset" --date=short'
alias glod='git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset"'
alias glola='git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset" --all'
alias glols='git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset" --stat'
alias glol='git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset"'
alias glolm='git log $(git_main_branch) --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset"'
alias glo='git log --oneline --decorate'
alias glog='git log --oneline --decorate --graph'
alias gloga='git log --oneline --decorate --graph --all'

# Pretty log messages
function _git_log_prettily(){
  if ! [ -z $1 ]; then
    git log --pretty=$1
  fi
}
compdef _git _git_log_prettily=git-log

alias glp='_git_log_prettily'
alias glg='git log --stat'
alias glgp='git log --stat --patch'
alias gignored='git ls-files -v | grep "^[[:lower:]]"'
alias gfg='git ls-files | grep'
alias gm='git merge'
alias gma='git merge --abort'
alias gmc='git merge --continue'
alias gms="git merge --squash"
alias gmff="git merge --ff-only"
alias gmom='git merge origin/$(git_main_branch)'
alias gmum='git merge upstream/$(git_main_branch)'
alias gmtl='git mergetool --no-prompt'
alias gmtlvim='git mergetool --no-prompt --tool=vimdiff'

alias gl='git pull'
alias gpr='git pull --rebase'
alias gprv='git pull --rebase -v'
alias gpra='git pull --rebase --autostash'
alias gprav='git pull --rebase --autostash -v'

function ggu() {
  local b
  [[ $# != 1 ]] && b="$(git_current_branch)"
  git pull --rebase origin "${b:-$1}"
}
compdef _git ggu=git-pull

alias gprom='git pull --rebase origin $(git_main_branch)'
alias gpromi='git pull --rebase=interactive origin $(git_main_branch)'
alias gprum='git pull --rebase upstream $(git_main_branch)'
alias gprumi='git pull --rebase=interactive upstream $(git_main_branch)'
alias ggpull='git pull origin "$(git_current_branch)"'

function ggl() {
  if [[ $# != 0 ]] && [[ $# != 1 ]]; then
    git pull origin "${*}"
  else
    local b
    [[ $# == 0 ]] && b="$(git_current_branch)"
    git pull origin "${b:-$1}"
  fi
}
compdef _git ggl=git-pull

alias gluc='git pull upstream $(git_current_branch)'
alias glum='git pull upstream $(git_main_branch)'
alias gp='git push'
alias gpd='git push --dry-run'

function ggf() {
  local b
  [[ $# != 1 ]] && b="$(git_current_branch)"
  git push --force origin "${b:-$1}"
}
compdef _git ggf=git-push

alias gpf!='git push --force'
is-at-least 2.30 "$git_version" \
  && alias gpf='git push --force-with-lease --force-if-includes' \
  || alias gpf='git push --force-with-lease'

function ggfl() {
  local b
  [[ $# != 1 ]] && b="$(git_current_branch)"
  git push --force-with-lease origin "${b:-$1}"
}
compdef _git ggfl=git-push

alias gpsup='git push --set-upstream origin $(git_current_branch)'
is-at-least 2.30 "$git_version" \
  && alias gpsupf='git push --set-upstream origin $(git_current_branch) --force-with-lease --force-if-includes' \
  || alias gpsupf='git push --set-upstream origin $(git_current_branch) --force-with-lease'
alias gpv='git push --verbose'
alias gpoat='git push origin --all && git push origin --tags'
alias gpod='git push origin --delete'
alias ggpush='git push origin "$(git_current_branch)"'

function ggp() {
  if [[ $# != 0 ]] && [[ $# != 1 ]]; then
    git push origin "${*}"
  else
    local b
    [[ $# == 0 ]] && b="$(git_current_branch)"
    git push origin "${b:-$1}"
  fi
}
compdef _git ggp=git-push

alias gpu='git push upstream'
alias grb='git rebase'
alias grba='git rebase --abort'
alias grbc='git rebase --continue'
alias grbi='git rebase --interactive'
alias grbo='git rebase --onto'
alias grbs='git rebase --skip'
alias grbd='git rebase $(git_develop_branch)'
alias grbm='git rebase $(git_main_branch)'
alias grbom='git rebase origin/$(git_main_branch)'
alias grbum='git rebase upstream/$(git_main_branch)'
alias grf='git reflog'
alias gr='git remote'
alias grv='git remote --verbose'
alias gra='git remote add'
alias grrm='git remote remove'
alias grmv='git remote rename'
alias grset='git remote set-url'
alias grup='git remote update'
alias grh='git reset'
alias gru='git reset --'
alias grhh='git reset --hard'
alias grhk='git reset --keep'
alias grhs='git reset --soft'
alias gpristine='git reset --hard && git clean --force -dfx'
alias gwipe='git reset --hard && git clean --force -df'
alias groh='git reset origin/$(git_current_branch) --hard'
alias grs='git restore'
alias grss='git restore --source'
alias grst='git restore --staged'
alias gunwip='git rev-list --max-count=1 --format="%s" HEAD | grep -q "\--wip--" && git reset HEAD~1'
alias grev='git revert'
alias greva='git revert --abort'
alias grevc='git revert --continue'
alias grm='git rm'
alias grmc='git rm --cached'
alias gcount='git shortlog --summary --numbered'
alias gsh='git show'
alias gsps='git show --pretty=short --show-signature'
alias gstall='git stash --all'
alias gstaa='git stash apply'
alias gstc='git stash clear'
alias gstd='git stash drop'
alias gstl='git stash list'
alias gstp='git stash pop'
# use the default stash push on git 2.13 and newer
is-at-least 2.13 "$git_version" \
  && alias gsta='git stash push' \
  || alias gsta='git stash save'
alias gsts='git stash show --patch'
alias gst='git status'
alias gss='git status --short'
alias gsb='git status --short --branch'
alias gsi='git submodule init'
alias gsu='git submodule update'
alias gsd='git svn dcommit'
alias git-svn-dcommit-push='git svn dcommit && git push github $(git_main_branch):svntrunk'
alias gsr='git svn rebase'
alias gsw='git switch'
alias gswc='git switch --create'
alias gswd='git switch $(git_develop_branch)'
alias gswm='git switch $(git_main_branch)'
alias gta='git tag --annotate'
alias gts='git tag --sign'
alias gtv='git tag | sort -V'
alias gignore='git update-index --assume-unchanged'
alias gunignore='git update-index --no-assume-unchanged'
alias gwch='git log --patch --abbrev-commit --pretty=medium --raw'
alias gwt='git worktree'
alias gwta='git worktree add'
alias gwtls='git worktree list'
alias gwtmv='git worktree move'
alias gwtrm='git worktree remove'
alias gstu='gsta --include-untracked'
alias gtl='gtl(){ git tag --sort=-v:refname -n --list "${1}*" }; noglob gtl'
alias gk='\gitk --all --branches &!'
alias gke='\gitk --all $(git log --walk-reflogs --pretty=%h) &!'

unset git_version

# Logic for adding warnings on deprecated aliases or functions
local old_name new_name
for old_name new_name (
  current_branch  git_current_branch
); do
  aliases[$old_name]="
    print -Pu2 \"%F{yellow}[oh-my-zsh] '%F{red}${old_name}%F{yellow}' is deprecated, using '%F{green}${new_name}%F{yellow}' instead.%f\"
    $new_name"
done
unset old_name new_name
__GITPLUGIN_EOF__

  # Prompt full/light, monitoring RAM/CPU, état Git, couleurs, complétion,
  # syntax highlighting, autosuggestions, aide zsh_help, hooks fnm/direnv
  # (inactifs tant que fnm/direnv sont absents).
  log "ZSH — ~/.zshrc"
  write_file "$HOME/.zshrc" 122893e07d12ed5c9587a61efba77e9c7eae849c969e382e81f3205ac61f5a96 <<'__ZSHRC_EOF__'
# Configuration ZSH — RAM/CPU/Git temps réel
# ========================================
# CONFIGURATION DE BASE
# ========================================

autoload -U colors && colors
setopt PROMPT_SUBST AUTO_CD CORRECT EXTENDED_GLOB

HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS HIST_SAVE_NO_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS

autoload -U compinit && compinit -u

# ========================================
# CONFIGURATION VISUELLE DES FICHIERS
# ========================================

export CLICOLOR=1
export LSCOLORS=ExGxBxDxCxEgEdxbxgxcxd
export LS_COLORS='rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arc=01;31:*.arj=01;31:*.taz=01;31:*.lha=01;31:*.lz4=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.tzo=01;31:*.t7z=01;31:*.zip=01;31:*.z=01;31:*.dz=01;31:*.gz=01;31:*.lrz=01;31:*.lz=01;31:*.lzo=01;31:*.xz=01;31:*.zst=01;31:*.tzst=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.war=01;31:*.ear=01;31:*.sar=01;31:*.rar=01;31:*.alz=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.cab=01;31:*.wim=01;31:*.swm=01;31:*.dwm=01;31:*.esd=01;31:*.jpg=01;35:*.jpeg=01;35:*.mjpg=01;35:*.mjpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.ogv=01;35:*.ogx=01;35:*.py=01;33:*.js=01;33:*.json=01;33:*.yml=01;33:*.yaml=01;33:*.toml=01;33:*.ini=01;33:*.cfg=01;33:*.conf=01;33:*.log=00;37:*.md=01;37:*.txt=00;37:*.sh=01;32:*.bash=01;32:*.zsh=01;32:*.fish=01;32'

zstyle ':completion:*' menu select
zstyle ':completion:*' group-name ''
zstyle ':completion:*' verbose yes
zstyle ':completion:*:descriptions' format '%B%F{107}── %d ──%f%b'
zstyle ':completion:*:messages' format '%F{180}%d%f'
zstyle ':completion:*:warnings' format '%F{196}No matches for: %d%f'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*:sudo:*' command-path /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin

# ========================================
# FONCTIONS SYSTÈME TEMPS RÉEL
# ========================================

ram_usage() {
    local ram_used ram_total
    if [[ "$OSTYPE" == "darwin"* ]]; then
        local page_size=$(vm_stat | awk '/page size of/ {print $8}')
        [[ -z "$page_size" ]] && page_size=4096
        local pages_used=$(vm_stat | grep "Pages active\|Pages inactive\|Pages speculative\|Pages wired down" | awk '{sum += $3} END {print sum}' | sed 's/\.//')
        if [[ -n "$pages_used" && $pages_used -gt 0 ]]; then
            ram_used=$(awk -v p="$pages_used" -v s="$page_size" 'BEGIN {printf("%.1f", p * s / 1073741824)}')
        else
            ram_used="0.0"
        fi
        ram_total=$(awk -v b="$(sysctl -n hw.memsize 2>/dev/null)" 'BEGIN {printf("%.1f", b / 1073741824)}')
    else
        if command -v free >/dev/null 2>&1; then
            read -r ram_used ram_total <<< "$(free -m | awk '/^Mem:/ {printf("%.1f %.1f", $3 / 1024, $2 / 1024)}')"
        fi
        [[ -z "$ram_used" ]] && ram_used="0.0"
        [[ -z "$ram_total" ]] && ram_total="0.0"
    fi
    echo "%F{107}RAM: %F{113}${ram_used}%F{94}/%F{137}${ram_total}Go%f"
}

cpu_usage() {
    local cpu_percent
    if [[ "$OSTYPE" == "darwin"* ]]; then
        cpu_percent=$(top -l 1 -n 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')
        [[ -z "$cpu_percent" ]] && cpu_percent="0"
    else
        if command -v top >/dev/null 2>&1; then
            cpu_percent=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
        else
            local load_avg=$(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | xargs)
            local num_cores=$(nproc 2>/dev/null || echo 1)
            cpu_percent=$(echo "scale=1; $load_avg * 100 / $num_cores" | bc 2>/dev/null || echo "0")
        fi
    fi
    local cpu_color="71"
    (( $(echo "$cpu_percent > 70" | bc -l 2>/dev/null || echo 0) )) && cpu_color="196"
    (( $(echo "$cpu_percent > 40" | bc -l 2>/dev/null || echo 0) )) && [[ "$cpu_color" != "196" ]] && cpu_color="178"
    echo "%F{$cpu_color}CPU: ${cpu_percent}%%%f"
}

command_status() {
    echo "%(?:%F{71}✓:%F{196}✗)%f"
}

current_time() {
    echo "%F{180}%D{%H:%M:%S}%f"
}

# Informations Git : projet + branche + légende d'état à 3 niveaux
#   À COMMIT (orange pâle)  → des changements locaux non commités (staged/unstaged/untracked)
#   À PUSH   (ocre)         → dépôt propre mais désynchronisé de la remote (ahead et/ou behind)
#   À JOUR   (vert nature)  → dépôt propre et synchronisé avec la remote
git_info() {
    git rev-parse --git-dir >/dev/null 2>&1 || return

    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    [[ -z "$branch" ]] && return

    local project
    project=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")

    local git_status
    git_status=$(git status --porcelain 2>/dev/null)

    local ahead behind
    ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
    behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo 0)

    local legend legend_color
    if [[ -n "$git_status" ]]; then
        legend="À COMMIT"; legend_color="215"
    elif [[ $ahead -gt 0 || $behind -gt 0 ]]; then
        legend="À PUSH"; legend_color="178"
    else
        legend="À JOUR"; legend_color="71"
    fi

    echo "%F{94}[%F{137}${project} %F{$legend_color}${legend}%f %F{137}${branch}%F{94}]%f"
}

# ========================================
# THÈMES
# ========================================

change_prompt() {
    case $1 in
        "light")
            PROMPT='%F{37}%1~%f$(git_info) %F{107}❯%f '
            RPROMPT='$(current_time)'
            ;;
        "full")
            PROMPT='%F{58}╭─%f %F{64}%n%f%F{100}@%f%F{107}%m%f %F{94}in%f %F{37}%~%f $(ram_usage) $(cpu_usage)
%F{58}╰─%f$(command_status)$(git_info) %F{107}❯%f '
            RPROMPT='$(current_time)'
            ;;
        *)
            echo "Usage: change_prompt [light|full]"
            ;;
    esac
}

# ========================================
# PLUGINS EXTERNES
# ========================================

[[ -d ~/.zsh/plugins/zsh-completions ]] && fpath=(~/.zsh/plugins/zsh-completions/src $fpath)

[[ -f ~/.zsh/plugins/git/git.plugin.zsh ]] && source ~/.zsh/plugins/git/git.plugin.zsh

if [[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern cursor)
    ZSH_HIGHLIGHT_STYLES[default]=none
    # Commandes : valide → vert · chemin incomplet → jaune · inconnue → rouge
    ZSH_HIGHLIGHT_STYLES[unknown-token]=fg=196,bold
    ZSH_HIGHLIGHT_STYLES[path_prefix]=fg=226,bold
    ZSH_HIGHLIGHT_STYLES[command]=fg=40,bold
    ZSH_HIGHLIGHT_STYLES[builtin]=fg=40,bold
    ZSH_HIGHLIGHT_STYLES[alias]=fg=40,bold
    ZSH_HIGHLIGHT_STYLES[suffix-alias]=fg=40,bold
    ZSH_HIGHLIGHT_STYLES[global-alias]=fg=40,bold
    ZSH_HIGHLIGHT_STYLES[function]=fg=40,bold
    ZSH_HIGHLIGHT_STYLES[hashed-command]=fg=40,bold
    ZSH_HIGHLIGHT_STYLES[reserved-word]=fg=40,bold
    ZSH_HIGHLIGHT_STYLES[precommand]=fg=40,underline
    ZSH_HIGHLIGHT_STYLES[commandseparator]=fg=94,bold
    ZSH_HIGHLIGHT_STYLES[path]=fg=80,underline
    ZSH_HIGHLIGHT_STYLES[globbing]=fg=137,bold
    ZSH_HIGHLIGHT_STYLES[single-quoted-argument]=fg=180
    ZSH_HIGHLIGHT_STYLES[double-quoted-argument]=fg=180
    ZSH_HIGHLIGHT_STYLES[comment]=fg=101,italic
    ZSH_HIGHLIGHT_STYLES[arg0]=fg=40,bold
fi

if [[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
    source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=101,italic"
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
    ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
    ZSH_AUTOSUGGEST_USE_ASYNC=true
fi

# ========================================
# ENVIRONNEMENT
# ========================================

export EDITOR=nano
export PAGER=less
export LANG=fr_FR.UTF-8
export LC_ALL=fr_FR.UTF-8

# ========================================
# PROMPT PAR DÉFAUT (full)
# ========================================

PROMPT='%F{58}╭─%f %F{64}%n%f%F{100}@%f%F{107}%m%f %F{94}in%f %F{37}%~%f $(ram_usage) $(cpu_usage)
%F{58}╰─%f$(command_status)$(git_info) %F{107}❯%f '
RPROMPT='$(current_time)'

# ========================================
# AIDE
# ========================================

zsh_help() {
    echo "🟢 ZSH (secondaire) — monitoring temps réel + Git"
    echo ""
    echo "📋 Commandes:"
    echo "  change_prompt light   Prompt minimaliste"
    echo "  change_prompt full    Prompt complet RAM/CPU (défaut)"
    echo "  zsh_help              Cette aide"
    echo ""
    echo "🌿 Git (automatique dans le prompt) :"
    echo "  [projet LÉGENDE branche]"
    echo "  À COMMIT (orange pâle)  → changements locaux non commités (staged/unstaged/untracked)"
    echo "  À PUSH   (ocre)         → dépôt propre mais désynchronisé de la remote (ahead et/ou behind)"
    echo "  À JOUR   (vert nature)  → dépôt propre et synchronisé avec la remote"
    echo "  Aliases git chargés : ga gst gco gp gl gd gcmsg…"
    echo ""
    echo "📊 Monitoring :"
    echo "  RAM: utilisé/totalGo (ex: 5.2/15.6Go)   CPU: XX%   HH:MM:SS (droite)"
    echo "  CPU: vert nature <40% · ocre <70% · rouge vif >70%"
    echo ""
    echo "🔧 Plugins :"
    [[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] \
        && echo "  ✅ Syntax Highlighting" || echo "  ❌ Syntax Highlighting"
    [[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] \
        && echo "  ✅ Autosuggestions"    || echo "  ❌ Autosuggestions"
    [[ -d ~/.zsh/plugins/zsh-completions ]] \
        && echo "  ✅ Enhanced Completions" || echo "  ❌ Enhanced Completions"
    [[ -f ~/.zsh/plugins/git/git.plugin.zsh ]] \
        && echo "  ✅ Git aliases"        || echo "  ❌ Git aliases"
}

echo "🟢 ZSH (secondaire) prêt — 'zsh_help' pour l'aide"

# >>> setup:dev >>>
if (( $+commands[fnm] )); then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi
if (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
fi
# <<< setup:dev <<<
__ZSHRC_EOF__
fi

# =============================================================================
# 4. Contrôle final
# =============================================================================
log "Contrôle des versions"
check_ver() { # <libellé> <attendu> <commande...>
  local label=$1 want=$2 got; shift 2
  got=$("$@" 2>&1 | head -n1 || true)
  if grep -qF -- "$want" <<<"$got"; then info "OK  $label $want"
  else info "KO  $label : attendu $want, obtenu '$got'"; DRIFT+=("$label : attendu $want, obtenu '$got'"); fi
}
if (( DO_STACK )); then
  for e in "${GO_TOOLS[@]}"; do
    IFS='|' read -r bin _ mod ver <<<"$e"
    check_ver "$bin" "$ver" bash -c "go version -m '$BIN_DIR/$bin' | awk '\$1 == \"mod\" && \$2 == \"$mod\" {print \$3}'"
  done
  check_ver golangci-lint "${GOLANGCI_VERSION#v}" "$BIN_DIR/golangci-lint" version
  check_ver xh "${XH_VERSION#v}" "$BIN_DIR/xh" --version
  check_ver fnm "${FNM_VERSION#v}" "$FNM_DIR/fnm" --version
  check_ver node "$NODE_VERSION" node --version
  check_ver pnpm "$PNPM_VERSION" pnpm --version
  check_ver GOTOOLCHAIN auto go env GOTOOLCHAIN
fi
if (( DO_ZSH )); then
  for e in "${ZSH_PLUGINS[@]}"; do
    IFS='|' read -r name _ sha <<<"$e"
    check_ver "plugin $name" "$sha" git -C "$HOME/.zsh/plugins/$name" rev-parse HEAD
  done
  check_ver "shell de connexion" /usr/bin/zsh getent passwd "$USER"
  if zsh -n "$HOME/.zshrc" 2>/dev/null; then info "OK  syntaxe ~/.zshrc"
  else info "KO  syntaxe ~/.zshrc"; DRIFT+=("$HOME/.zshrc : erreur de syntaxe (zsh -n)"); fi
fi

log "Terminé"
if (( ${#DRIFT[@]} )); then
  echo "Écarts avec la machine de référence :"
  printf '  - %s\n' "${DRIFT[@]}"
else
  echo "Aucun écart avec la machine de référence."
fi
echo
echo "Suite :"
echo "  - se déconnecter / reconnecter (shell zsh, groupe docker), ou : exec zsh -l"
(( ! DO_STACK )) || echo "  - vérifier la stack : zsh -ic 'bash $SETUP_DIR/verify.sh'"
