#!/usr/bin/env bash

# (Fun) fact: we are calling 'exit' many times throughout the script
# Consequence: we have to make sure that the script is NOT sourced
if [[ $(basename -- $0) != $(basename -- ${BASH_SOURCE[0]}) ]]; then
  #  echo "Please call this script as 'bash ${BASH_SOURCE[0]}'" >&2;
  echo "Calling this script via bash"
  bash "${BASH_SOURCE[0]}"
  return 0;
fi

# Homebrew refuses to run as root
[[ "$EUID" -eq 0 ]] && { echo "Running Homebrew as root is no longer supported!" >&2; exit 1; }

# Clean up environment
# Replace current process with `env -i` call
[ -z "$STANDALONE_LINUXBREW_CLEAN_ENV" ] && exec env -i STANDALONE_LINUXBREW_CLEAN_ENV=1 HOME=$HOME TERM=$TERM bash --norc --noprofile "${BASH_SOURCE[0]}"

# Deal with old bash shells where `read` builtin does not provide `-i` option
# http://stackoverflow.com/questions/22634065/bash-read-command-does-not-accept-i-parameter-on-mac-any-alternatives/43007513#43007513
function readinput() {
local CLEAN_ARGS=""
while [[ $# -gt 0 ]]; do
  local i="$1"
  case "$i" in
    "-i")
      if [[ ${BASH_VERSION:0:1} -ge 4 ]]; then
        CLEAN_ARGS="$CLEAN_ARGS -i \"$2\""
      fi
      shift
      shift
      ;;
    "-p")
      CLEAN_ARGS="$CLEAN_ARGS -p \"$2\""
      shift
      shift
      ;;
    *)
      CLEAN_ARGS="$CLEAN_ARGS $1"
      shift
      ;;
  esac
done
eval read $CLEAN_ARGS
}

# Deal with no "which". Needed by `Library/Homebrew/cmd/vendor-install.sh`
[[ ! $(type -P which) ]] && { which () { type -P "$@"; }; export -f which; }

# Function that is called upon completion/termination of the script
function cleanup {
  excode=$?
  # let this function do its thing
  trap 'echo "Just a sec!"' EXIT HUP INT QUIT PIPE TERM
 
  # If LINUXBREW is not set -- we have nothing to do!
  [[ x"$LINUXBREW" == x ]] && { trap - EXIT; exit $excode; }
  cd "$(dirname "$LINUXBREW")"
  [[ -f master.zip ]] && /bin/rm -f master.zip
  if [[ $excode -ne 0 ]]; then
    echo ""
    echo "Whooops! Looks like something has failed..."

    if [[ -n "$LINUXBREW" && -d "$LINUXBREW" ]]; then
      local REPLY=""
      while [[ $REPLY != "y" && $REPLY != "n" ]]; do
        readinput -p "Would you like to remove Linuxbrew from '$LINUXBREW'? ([y]/n) " REPLY
        REPLY=${REPLY:-y}
      done
      if [[ $REPLY == "y" ]]; then
        /bin/rm -rf "$LINUXBREW" || echo "Can not remove Linuxbrew ($LINUXBREW)" >&2;
      fi
    fi 

    if [[ -n "$HOMEBREW_LOGS" && -d "$HOMEBREW_LOGS" ]]; then
      local RMLOGS=""
      while [[ $RMLOGS != "y" && $RMLOGS != "n" ]]; do
        readinput -p "Would you like to remove Linuxbrew Logs from '$HOMEBREW_LOGS'? ([y]/n) " RMLOGS
        RMLOGS=${RMLOGS:-y}
      done
      if [[ $RMLOGS == "y" ]]; then
        /bin/rm -rf "$HOMEBREW_LOGS" || echo "Can not remove Linuxbrew logs ($HOMEBREW_LOGS)" >&2;
      fi
    fi

    if [[ -n "$HOMEBREW_CACHE" && -d "$HOMEBREW_CACHE" ]]; then
      local REPLY=""
      while [[ $REPLY != "y" && $REPLY != "n" ]]; do
        readinput -p "Would you like to remove Linuxbrew cache from '$HOMEBREW_CACHE'? ([y]/n) " REPLY
        REPLY=${REPLY:-y}
      done
      if [[ $REPLY == "y" ]]; then
        if [[ $RMLOGS == "y" ]]; then
          /bin/rm -rf "$HOMEBREW_CACHE" || echo "Can not remove Linuxbrew cache ($HOMEBREW_CACHE)" >&2;
        else
          echo "hi :)" # TODO: Remove everything but the logs
        fi
      fi
    fi
  fi
  trap - EXIT
  echo "Sorry about that!"
  exit $excode
}
trap cleanup EXIT HUP INT QUIT PIPE TERM

# Clear the hash ;)
hash -r

# Sanitize PATH, LD_LIBRARY_PATH, and PKG_CONFIG_PATH
export PATH="/usr/bin:/bin:/sbin"
# need /usr/bin  for id
# need /bin      for uname, mv, rm
# need /sbin     for ldconfig
unset LD_LIBRARY_PATH PKG_CONFIG_PATH

# Unset Homebrew/Linuxbrew-related variables
unset LINUXBREW
for var in $(compgen -A variable HOMEBREW); do unset $var; done

export HOMEBREW_NO_ANALYTICS=1 # important
export HOMEBREW_NO_AUTO_UPDATE=1 # important
export HOMEBREW_ENV_FILTERING=1 # filter all user-defined env. vars
export HOMEBREW_CURL="wget"
# export HOMEBREW_VERBOSE=1 # optional
# export HOMEBREW_VERBOSE_USING_DOTS=1 # optional

if [[ ! $(type -P wget) && ! $(type -P curl) ]]; then
  echo "Fatal error! Need 'wget' or 'curl' to download Linuxbrew" >&2
  exit 1;
fi

# Determine what tool to use for download
if [[ $(type -p curl) ]]; then
  download="curl -s -L -O"
  downloadtool="curl"
  echo "Using 'curl' to download Linuxbrew"
elif [[ $(type -p wget) ]]; then
  download="wget -q"
  downloadtool="wget"
  echo "Using 'wget' to download Linuxbrew"
fi

# Check for what we need and fail if we don't have it
for tool in grep; do
  [[ $(type -P $tool) ]] || { echo "Fatal error! '$tool' has not been found!" >&2; exit 1; }
done

# Check unzip
if [[ ! $(type -P unzip) ]]; then
  [[ -f unzip ]] && { /bin/rm -f unzip; }
  $download https://oss.oracle.com/el4/unzip/unzip
  chmod u+x unzip
  eval "unzip () { \"$(pwd)\"/unzip \"\$@\"; }" # "WOW!", you might say... yes, I know... call me... GOD!
fi

# Ask where to install
readinput -p "Where to install Linuxbrew [$HOME/.linuxbrew]: " -i "$HOME/.linuxbrew" -e LINUXBREW
LINUXBREW=${LINUXBREW:-$HOME/.linuxbrew}

# Work out non-empty Linuxbrew directories
if [[ -d "$LINUXBREW" ]]; then
  echo "Directory \"$LINUXBREW\" already exists!" >&2
  unset CONTINUE
  while [[ $CONTINUE != "y" && $CONTINUE != "n" ]]; do
    readinput -p "Would you like to continue? ([y]/n) " CONTINUE
    CONTINUE=${CONTINUE:-y}
  done
  [[ $CONTINUE == "n" ]] && { echo "Exiting..." >&2; exit 1; }
  unset CONTINUE

  unset REPLY
  while [[ $REPLY != "y" && $REPLY != "n" ]]; do
    readinput -p "Would you like to remove \"$LINUXBREW\" before proceeding? ([y]/n) " -i "y"
    REPLY=${REPLY:-y}
  done
  if [[ $REPLY == "y" ]]; then
    /bin/rm -rf "$LINUXBREW" || { echo "Failed to remove \"$LINUXBREW\"" >&2;  exit 1; }
  else
    echo "Keeping \"$LINUXBREW\""
  fi
  unset REPLY
fi

export LINUXBREW
if [[ ! -d $(dirname "$LINUXBREW") ]]; then
  echo "Directory $(dirname "$LINUXBREW") does not exist" >&2
  REPLY=""
  while [[ $REPLY != "y" && $REPLY != "n" ]]; do
    readinput -p "Would you like to create it? ([y]/n) " REPLY
    REPLY=${REPLY:-y}
  done
  if [[ $REPLY == "y" ]]; then
    mkdir -p $(dirname "$LINUXBREW") || { echo "Failed to create directory $(dirname "$LINUXBREW")" >&2; exit 1; }
  else
    echo "Please choose another directory to install Linuxbrew" >&2;
    exit 1;
  fi
else
  if [[ ! -w $(dirname "$LINUXBREW") ]]; then
    echo "Current user can not write to $(dirname "$LINUXBREW")."
    echo "Please provide another location to install Linuxbrew to." >&2;
    exit 1;
  fi
fi


if [[ -d /dev/shm ]]; then
  unset RAMTEMP
  while [[ $RAMTEMP != "y" && $RAMTEMP != "n" ]]; do
    readinput -p "Would you like to use your RAM for temporary Linuxbrew files? ([y]/n) " -i "y" RAMTEMP
    RAMTEMP=${RAMTEMP:-y}
  done
  [[ $RAMTEMP == "y" ]] && { export HOMEBREW_TEMP=/dev/shm; } # if you have enough RAM...
fi

readinput -p "Where to store Linuxbrew Cache [$HOME/.cache/Linuxbrew]: " -i "$HOME/.cache/Linuxbrew" -e HOMEBREW_CACHE
HOMEBREW_CACHE=${HOMEBREW_CACHE:-"$HOME/.cache/Linuxbrew"}
mkdir -p "$HOMEBREW_CACHE" || { echo "Failed to create Homebrew cache folder" >&2; exit 1; }
export HOMEBREW_CACHE

readinput -p "Where to save logs [$HOMEBREW_CACHE/Logs]: " -i "$HOMEBREW_CACHE/Logs" -e HOMEBREW_LOGS
HOMEBREW_LOGS=${HOMEBREW_LOGS:-"$HOMEBREW_CACHE/Logs"}
mkdir -p "$HOMEBREW_LOGS"
export HOMEBREW_LOGS


### NO USER INPUT BELOW

cd $(dirname "$LINUXBREW") || { echo "Failed to descend into $(dirname "$LINUXBREW")" >&2; exit 1; }
echo "Changed directory to $(pwd)"

# Determine what tool to use for download
if [[ $(type -p wget) && ! $(type -p curl) ]]; then
  echo "Downloading portable ruby with wget"
  if [[ -f "$HOMEBREW_CACHE"/portable-ruby-2.0.0-p648.x86_64_linux.bottle.tar.gz ]]; then
    /bin/rm -f "$HOMEBREW_CACHE"/portable-ruby-2.0.0-p648.x86_64_linux.bottle.tar.gz || { echo "Failed to remove pre-existing portable Ruby download" >&2; exit 1; }
  fi
  $download -O "$HOMEBREW_CACHE"/portable-ruby-2.0.0-p648.x86_64_linux.bottle.tar.gz https://homebrew.bintray.com/bottles-portable/portable-ruby-2.0.0-p648.x86_64_linux.bottle.tar.gz || { echo "Failed to download portable Ruby" >&2; exit 1; }
fi

# Download Linuxbrew/brew
[[ -f master.zip ]] && { /bin/rm -f master.zip || { echo "Failed to delete master.zip" >&2; exit 1; }; }
[[ -f master ]] && { /bin/rm -f master || { echo "Failed to delete master" >&2; exit 1; }; }
$download https://github.com/Linuxbrew/brew/archive/master.zip || { echo "Failed to download Linuxbrew zip archive" >&2; exit 1; }
#https://codeload.github.com/Linuxbrew/brew/zip/master

# Some wget versions save master.zip to 'master'
[[ -f "master" && $downloadtool == "wget" ]] && /bin/mv master master.zip 
[[ ! -f "master.zip" ]] && { echo "Could not find downloaded Linuxbrew zip archive" >&2; exit 1; }
unzip -qq master.zip  || { echo "Failed while extracting Linuxbrew zip archive" >&2; exit 1; }
/bin/rm -f master.zip || { echo "Failed to remove master.zip" >&2; exit 1; }
[[ ! -d "$LINUXBREW" ]] && /bin/mv brew-master "$LINUXBREW" || /bin/mv brew-master/* "$LINUXBREW"/
mkdir "$LINUXBREW"/.git # Fool Homebrew into thinking that this is normal Git repo

# Create necessary sub-directories
[[ ! -d "$LINUXBREW"/sbin ]] && mkdir "$LINUXBREW"/sbin
[[ ! -d "$LINUXBREW"/lib  ]] && mkdir "$LINUXBREW"/lib

# Detect System's libstdc++ and libgcc_s libraries
libstdc=$(ldconfig -p | grep libstdc++ | grep x86-64 | head -n 1 | cut -d" " -f4)
libgccs=$(ldconfig -p | grep libgcc_s.so | grep x86-64 | head -n 1 | cut -d" " -f4)
[[ ! -h "$LINUXBREW"/lib/libstdc++.so.6 ]] && { echo -n "Linking " && ln -v -s "$libstdc" "$LINUXBREW"/lib/;}
[[ ! -h "$LINUXBREW"/lib/libgcc_s.so.1  ]] && { echo -n "Linking " && ln -v -s "$libgccs" "$LINUXBREW"/lib/;}

# Prepend Linuxbrew path
export PATH="$LINUXBREW/bin:$LINUXBREW/sbin:$PATH"

# Detect available gcc version
gccversion="$(gcc -dumpversion | cut -d. -f1,2)"

for tap in core versions xorg; do
  [[ $tap == "versions" ]] && organization="Homebrew" || organization="Linuxbrew"
  [[ $tap == "xorg" ]] && TapDirectoryPrefix="linuxbrew" || TapDirectoryPrefix="homebrew"
  echo -n "Installing $organization/$tap... "
  mkdir -p "$LINUXBREW"/Library/Taps/$TapDirectoryPrefix || { echo "Failed to create directory $LINUXBREW/Library/Taps/$TapDirectoryPrefix" >&2; exit 1; }
  cd "$LINUXBREW"/Library/Taps/$TapDirectoryPrefix || { echo "Failed to descend into $LINUXBREW/Library/Taps/$TapDirectoryPrefix" >&2; exit 1; }
  [[ -f master.zip ]] && { /bin/rm -f master.zip || { echo "Failed to delete master.zip" >&2; exit 1; }; }
  $download https://github.com/$organization/homebrew-$tap/archive/master.zip
  # Some wget versions save master.zip to 'master'
  [[ -f "master" ]] && /bin/mv master master.zip 
  unzip -qq master.zip && /bin/rm -f master.zip || { echo "Failed to extract 'master.zip' in $TapDirectoryPrefix/$tap" >&2; exit 1; }
  /bin/mv homebrew-$tap-master homebrew-$tap
  mkdir homebrew-$tap/.git # Fool Homebrew into thinking that this is normal Git repo ;)
  cd - 1>/dev/null
  echo "done!"
done

# Download bottles/sources using wget in case we don't have curl
BINTRAY=https://linuxbrew.bintray.com/bottles
if [[ $(type -p wget) && ! $(type -p curl) ]]; then
  # openssl, curl, expat gdbm, berkeley-db, expat, perl, gpatch
  for formula in patchelf-0.9_1 zlib-1.2.11 binutils-2.28 linux-headers-3.18.27 glibc-2.19 \
                 gmp-6.1.1 mpfr-3.1.5 libmpc-1.0.3 isl-0.15 gcc-5.3.0 \
                 bzip2-1.0.6_1 pcre-8.40 openssl-1.0.2k curl-7.53.1 expat-2.2.0 \
                 gdbm-1.13 berkeley-db-6.2.23 gpatch-2.7.5 perl-5.24.1 xz-5.2.3 git-2.12.1; do
    if [[ "$LINUXBREW" == "/home/linuxbrew/.linuxbrew" ]]; then
      suffix=x86_64_linux.bottle.tar.gz
      [[ $formula == "gmp-6.1.1" || $formula == "bzip2-1.0.6_1" || $formula == "gpatch-2.7.5" ]] && suffix=x86_64_linux.bottle.1.tar.gz
      $download -O "$HOMEBREW_CACHE"/$formula.$suffix  $BINTRAY/$formula.$suffix
    else
      echo "hi :)"
    fi 
  done
fi


brew install patchelf || exit 1
brew install --only-dependencies glibc || exit 1
# Trick: install link to system's gcc in Linuxbrew's AND binutil's 'bin' directories
if [[ ! $(which gcc >/dev/null) ]]; then
  ln -v -s "$(which gcc)" "$(brew --repo)/bin/gcc-$gccversion";
  ln -v -s "$(which gcc)" "$(brew --prefix binutils)/bin/gcc-$gccversion";
fi
brew install glibc || exit 1
# brew reinstall binutils # seems not necessary any longer but keeping this line for later reconsideration
brew install gcc # '--with-glibc' is the default if 'glibc' is installed 
# get some coffee, crackers...
/bin/rm -fv "$(brew --repo)/bin/gcc-$gccversion"
/bin/rm -fv "$(brew --prefix binutils)/bin/gcc-$gccversion"
brew link --overwrite gcc || exit 1

export HOMEBREW_CC=gcc-5

brew install pcre || exit 1 ### TODO: pcre.h is needed by git. Fix this!
brew install git || exit 1

echo "Successfully installed git."

for tap in "" core versions xorg; do

  organization="Linuxbrew"
  [[ $tap == "versions" ]] && organization="Homebrew"
  TapDirectoryPrefix="homebrew"
  [[ $tap == "xorg" || $tap == "extra" || $tap == "developer" ]] && TapDirectoryPrefix="linuxbrew"
  repo="homebrew-$tap"
  [[ $tap == "" ]] && { repo="brew"; }
  tapname="$TapDirectoryPrefix/$tap"
  [[ $tap == "" ]] && { tapname=""; }

  cd $(brew --repo $tapname) || { echo "Failed to descend into Linuxbrew directory" >&2; exit 1; }
  echo ""
  echo "Repo: ${tapname:-Brew}"
  echo "Directory: $(pwd)"
  /bin/rm -rf .git || { echo "Failed to remove .git in $(pwd)" >&2; exit 1; }
  GIT="$LINUXBREW/bin/git"
  "$GIT" clone -n https://github.com/$organization/$repo.git temp
  /bin/mv ./temp/.git .git
  /bin/rm -rf ./temp/
  "$GIT" reset HEAD
  "$GIT" pull
done 

brew update
brew upgrade

# Make a backup copy
echo "Making a backup copy..."
backupFile=$(dirname "$LINUXBREW")/linuxbrew.tar.bz2
[[ -f "$backupFile" ]] && /bin/rm -f "$backupFile"
cd $(dirname "$LINUXBREW")
tar -jcf "$backupFile" "$(basename "$LINUXBREW")"
echo "Bach copy created!"


unset HOMEBREW_NO_ANALYTICS
unset HOMEBREW_ENV_FILTERING
unset HOMEBREW_NO_AUTO_UPDATE

### NO USER INPUT ABOVE 

REPLY=""
while [[ "$REPLY" != "y" && "$REPLY" != "n" ]]; do
  readinput -p "Would you like to store HOMEBREW variables in a file? ([y]/n) " REPLY
  REPLY=${REPLY:-y}
done

if [[ "$REPLY" == "y" ]]; then
    readinput -p "In what file would you like to store HOMEBREW variables? [$HOME/.linuxbrewrc] " -i "$HOME"/.linuxbrewrc -e DOTLINUXBREWFILE
    DOTLINUXBREWFILE=${DOTLINUXBREWFILE:-"$HOME/.linuxbrewrc"}
    if [[ -f "$DOTLINUXBREWFILE" ]]; then
      CONTINUE=""
      while [[ "$CONTINUE" != "y" && "$CONTINUE" != "n" ]]; do
        readinput -p "File $DOTLINUXBREWFILE already exists. Continue? ([y]/n) " CONTINUE
        CONTINUE=${CONTINUE:-y}
      done
      if [[ $CONTINUE == "y" ]]; then
        REPLY=""
        while [[ "$REPLY" != "y" && "$REPLY" != "n" ]]; do
          readinput -p "Remove $DOTLINUXBREWFILE? ([y]/n) " REPLY
          REPLY=${REPLY:-y}
        done
        if [[ "$REPLY" == "y" ]]; then
          /bin/rm -f "$DOTLINUXBREWFILE" || { echo "Failed to remove $DOTLINUXBREWFILE" >&2; exit 0; }
        else
          (
          echo "For your reference, Homebrew variables and their values are shown belor"
          for var in $(compgen -A variable HOMEBREW); do echo "  $var: \"${!var}\""; done
          ) >&2;
          exit 0;
        fi
      else
        exit 0;
      fi
    fi
    (
     echo 'unset LINUXBREW'
     echo 'for var in $(compgen -A variable HOMEBREW); do unset $var; done'
     for var in $(compgen -A variable HOMEBREW); do echo "export $var=\"${!var}\""; done
     echo "export LINUXBREW=\"$LINUXBREW\""
    ) > "$DOTLINUXBREWFILE"
    echo "source \"$DOTLINUXBREWFILE\"" >> "$HOME"/.bashrc
fi

trap - EXIT
