#!/bin/bash
#
# Stop, refresh and remove what Batizado puts on this Mac. Called by the Makefile; inputs come from the
# environment. Never runs sudo: what needs the administrator password is printed for the user to run.
#
#   quit              quit the running app and wait for it to revert what it turned on
#   restart-guardian  restart the loaded guardian so it runs the binary that is on disk now
#   uninstall         remove the app, both LaunchAgents, the shared state folder and the preferences
#
#   APP_NAME     executable and bundle name   (Batizado)
#   BUNDLE_ID    reverse-DNS bundle identifier
#   INSTALL_DIR  folder holding the installed .app (uninstall only)

set -uo pipefail

: "${APP_NAME:?}" "${BUNDLE_ID:?}"

UID_NUM="$(id -u)"
DOMAIN="gui/$UID_NUM"
AGENTS_DIR="$HOME/Library/LaunchAgents"
GUARDIAN_LABEL="$BUNDLE_ID.guardian"
LOGIN_LABEL="$BUNDLE_ID.login"
GUARDIAN_NAME="${APP_NAME}Guardian"
SUPPORT_DIR="$HOME/Library/Application Support/$APP_NAME"
HELPER_RULE=/etc/sudoers.d/batizado

is_loaded() { launchctl print "$DOMAIN/$1" >/dev/null 2>&1; }
is_running() { pgrep -x -U "$UID_NUM" "$1" >/dev/null; }
sleep_disabled() { pmset -g | awk '$1 == "SleepDisabled" { print $2 }'; }

app_running() { is_running "$APP_NAME"; }
armed() { [ -f "$SUPPORT_DIR/armed.json" ]; }

# Waits up to $2 tenths of a second for the check $1 to fail; false if it never did.
wait_while() {
  local tries=0
  while "$1"; do
    [ "$tries" -ge "$2" ] && return 1
    sleep 0.1
    tries=$((tries + 1))
  done
}

# SIGTERM makes the app quit through its normal path, which turns Closed lid off and disarms the guardian.
quit_app() {
  is_running "$APP_NAME" || return 0
  echo "Quitting $APP_NAME"
  pkill -TERM -x -U "$UID_NUM" "$APP_NAME"
  if ! wait_while app_running 100; then
    echo "$APP_NAME did not quit in 10 s; killing it (the guardian reverts Closed lid)" >&2
    pkill -KILL -x -U "$UID_NUM" "$APP_NAME"
    wait_while app_running 50
  fi
}

# Rebuilding a bundle in place leaves the old guardian process running: same plist, so launchd keeps it.
restart_guardian() {
  is_loaded "$GUARDIAN_LABEL" || return 0
  launchctl kickstart -k "$DOMAIN/$GUARDIAN_LABEL" && echo "Restarted the guardian"
}

agent_bundle() {
  local plist="$AGENTS_DIR/$1.plist" index="$2"
  [ -f "$plist" ] || return 0
  plutil -extract "ProgramArguments.$index" raw "$plist" 2>/dev/null | sed -E 's#(\.app)/.*#\1#'
}

remove_agent() {
  local label="$1"
  if is_loaded "$label"; then
    launchctl bootout "$DOMAIN/$label" && echo "Unloaded $label"
  fi
  if [ -e "$AGENTS_DIR/$label.plist" ]; then
    rm -f "$AGENTS_DIR/$label.plist" && echo "Removed $AGENTS_DIR/$label.plist"
  fi
}

uninstall() {
  : "${INSTALL_DIR:?}"
  local installed="$INSTALL_DIR/$APP_NAME.app" other_copies=()
  local copy
  for copy in "$(agent_bundle "$GUARDIAN_LABEL" 0)" "$(agent_bundle "$LOGIN_LABEL" 1)"; do
    case " ${other_copies[*]-} " in *" $copy "*) continue ;; esac
    [ -n "$copy" ] && [ "$copy" != "$installed" ] && other_copies+=("$copy")
  done

  # First nothing may start the app again, then the app turns Closed lid off, then the guardian goes.
  remove_agent "$LOGIN_LABEL"
  quit_app
  if armed && is_loaded "$GUARDIAN_LABEL"; then
    echo "Waiting for the guardian to turn Closed lid off"
    wait_while armed 50
  fi
  remove_agent "$GUARDIAN_LABEL"
  if is_running "$GUARDIAN_NAME"; then
    pkill -TERM -x -U "$UID_NUM" "$GUARDIAN_NAME" && echo "Stopped a $GUARDIAN_NAME started by hand"
  fi

  if [ -d "$SUPPORT_DIR" ]; then
    rm -rf "$SUPPORT_DIR" && echo "Removed $SUPPORT_DIR"
  fi
  if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
    defaults delete "$BUNDLE_ID" && echo "Removed the preferences ($BUNDLE_ID)"
  fi
  local leftover
  for leftover in "$HOME/Library/Preferences/$BUNDLE_ID.plist" "$HOME/Library/Caches/$BUNDLE_ID" \
    "$HOME/Library/HTTPStorages/$BUNDLE_ID" "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"; do
    if [ -e "$leftover" ]; then
      rm -rf "$leftover" && echo "Removed $leftover"
    fi
  done
  if [ -e "$installed" ]; then
    rm -rf "$installed" && echo "Removed $installed"
  fi

  local status=0
  echo
  if [ "$(sleep_disabled)" = "1" ]; then
    status=1
    cat >&2 <<EOF
!!! WARNING: SleepDisabled is still 1 and no guardian is left to turn it off.
!!! This Mac will not sleep, even with the lid closed in a bag. Turn it off now:
!!!
!!!     sudo pmset -a disablesleep 0
!!!     pmset -g | grep SleepDisabled      # must print 0

EOF
  fi
  if [ -e "$HELPER_RULE" ]; then
    cat <<EOF
The helper rule $HELPER_RULE is still installed. Removing it needs your administrator password
(next time, use "Remove helper rule" in the app before uninstalling). Remove it with:

    sudo rm -f $HELPER_RULE

EOF
  fi
  for copy in "${other_copies[@]+"${other_copies[@]}"}"; do
    [ -e "$copy" ] && echo "Another copy of the app is still at $copy; delete it if you no longer want it."
  done
  if [ "$status" -eq 0 ]; then
    echo "$APP_NAME is uninstalled."
  else
    echo "$APP_NAME is uninstalled, but read the warning above." >&2
  fi
  return "$status"
}

case "${1:-}" in
  quit) quit_app ;;
  restart-guardian) restart_guardian ;;
  uninstall) uninstall ;;
  *) echo "usage: $0 quit|restart-guardian|uninstall" >&2; exit 2 ;;
esac
