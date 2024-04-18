#!/bin/bash

# ---

# Script Name: EasyRSAGUI.bash
# Purpose: This script helps to use Easy-RSA with a GUI (with dialog command)
# Dependencies: Easy-RSA (GPLv2), dialog (LGPL)
# Author: DannyManual
# Created: 2024-04-15
# Last modified: 2024-04-15
# Version: 1.0.0
# Licence: GPLv2

# ---

# Easy-RSA is licensed under GPLv2. A copy of the license is available at:
# https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

# ---

# 'dialog' is a tool to display dialog boxes from shell scripts.
# It is licensed under the LGPL. For more information, visit:
# https://www.gnu.org/licences/lgpl-3.0.html
#

# ---

export NCURSES_NO_UTF8_ACS=1

# --- global variable setup
EASYRSA_PATH="."
VARS_FILE="$EASYRSA_PATH/vars"
EASYRSA_PKI="$EASYRSA_PATH/pki"
CRL_PATH="$EASYRSA_PKI/crl.pem"
CERT_CSV_LIST="$EASYRSA_PATH/certs.csv"
NEW_CERT_CSV_LIST="$EASYRSA_PATH/newcerts.csv"

CERT_RENEW_DAYS=1

# --- Important commands and paths
EASYRSA_CMD="./easyrsa"
DIALOG_CMD="dialog"

#  Make sure 'dialog' is installed
if ! command -v "$DIALOG_CMD" &>/dev/null; then
  echo "Das Paket 'dialog' ist nicht installiert. Bitte installiere 'dialog', um dieses Skript zu verwenden."
  exit 1
fi

# Make sure 'vars' exists
if [ ! -f "$VARS_FILE" ]; then
  "$DIALOG_CMD" --title "Fehler" --msgbox "Die Datei $VARS_FILE fehlt!" 6 50
  clear
  exit 1
fi

# Make sure folder 'pki' exists
if [ ! -d "$EASYRSA_PKI" ]; then
  "$DIALOG_CMD" --title "Fehler" --msgbox "Die Ordner pki fehlt!" 6 50
  clear
  exit 1
fi

# Make sure folder 'easyrsa' exists in current folder and is linked to correct script
if [ -L "$EASYRSA_CMD" ]; then
  TARGET=$(readlink -f "$EASYRSA_CMD")
  if [ ! -x "$TARGET" ]; then
    "$DIALOG_CMD" --title "Fehler" --msgbox "easyrsa Link fehlerhaft!" 6 50
    clear
    exit 1
  fi
fi

EASYRSA_CERT_RENEW=$(awk '/^set_var[[:space:]]+EASYRSA_CERT_RENEW[[:space:]]+/ {print $3}' "$VARS_FILE")

# check if EASYRSA_CERT_RENEW is a number
if [ -z "$EASYRSA_CERT_RENEW" ]; then
  "$DIALOG_CMD" --title "Fehler" --msgbox "EASYRSA_CERT_RENEW in vars nicht definiert." 6 50
  clear
  exit 1
fi

# check if EASYRSA_CERT_RENEW is a positive number
if [[ "$EASYRSA_CERT_RENEW" =~ ^[0-9]+$ ]] && [ "$EASYRSA_CERT_RENEW" -gt 0 ]; then
  CERT_RENEW_DAYS="$EASYRSA_CERT_RENEW"
  #echo "$CERT_RENEW_DAYS"
else
  "$DIALOG_CMD" --title "Fehler" --msgbox "EASYRSA_CERT_RENEW ist keine positive Zahl." 6 50
  clear
  exit 1
fi

trim() {
  local var="$*"

  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space]]}"}"
  echo -n "$var"
}

# Creates client certificate using easyrsa without setting passphrase. CA password is prompted.
new_cert() {
  local name
  local caps
  local ec_easyrsa

  # Ask for CName
  exec 3>&1
  name=$(dialog --title "Name" --inputbox "Bitte Zertifikat Namen eingeben" 10 30 2>&1 1>&3)
  exec 3>&-

  # Ask for CA password
  exec 3>&1
  caps=$(dialog --title "Passwort" --clear --insecure --passwordbox "Bitte Passwort eingeben" 10 30 2>&1 1>&3)
  exec 3>&-

  clear
  echo "$caps" | ./easyrsa --batch --passin=stdin build-client-full $name nopass
  ec_easyrsa=$?

  read -t 5 -n 1 -s -r -p "Taste drücken oder 5 Sekunden warten, um fortzufahren. "
  caps="laksjdlknlak dnqwd "
  return $ec_easyrsa
}

# Tries to renew every selected certificate
renew_certs() {
  local certs=$1
  local caps
  local ec_suc=255
  echo "CNAME">"$NEW_CERT_CSV_LIST"
  exec 3>&1
  caps=$(dialog --title "Passwort" --clear --insecure --passwordbox "Bitte Passwort eingeben" 10 30 2>&1 1>&3)
  exec 3>&-

  clear

  for cert in $certs; do
    echo "$caps" | ./easyrsa --batch --passin=stdin renew $cert nopass
    ec_suc=$?
    if [ "$ec_suc" -eq 0 ]; then
      echo "$cert">>"$NEW_CERT_CSV_LIST"
    fi
  done

  read -t 5 -n 1 -s -r -p "Taste drücken oder 5 Sekunden warten, um fortzufahren. "
  caps="laksjdlknlak dnqwd "
}

revoke_certs() {
  local certs=$1
  exec 3>&1
  local caps=$(dialog --title "Passwort" --clear --insecure --passwordbox "Bitte Passwort eingeben" 10 30 2>&1 1>&3)
  exec 3>&-

  exec 3>&1
  local reason=$(dialog \
    --backtitle "EasyRSA Verwaltung" \
    --title "Revokation Grund auswählen" \
    --clear \
    --cancel-label "Zurück" \
    --menu "Bitte wähle Revokation Grund:" 20 70 4 \
    "unspecified" "Kein spezifischer Grund" \
    "keyCompromise" "Schlüssel wurde kompromittiert" \
    "CACompromise" "Zertifizierungsstelle kompromittiert" \
    "affiliationChanged" "Zugehörigkeit geändert" \
    "superseded" "Zertifikat wurde ersetzt" \
    "cessationOfOperation" "Betrieb eingestellt" \
    "certificateHold" "Zertifikat zurückgehalten" \
    2>&1 1>&3)
  exec 3>&-

  returnValue=$?
  clear

  case $returnValue in
  0)
    echo "Sie haben gewählt: $reason"
    for cert in $certs; do
      echo "$caps" | ./easyrsa --batch --passin=stdin revoke $cert $reason
    done
    read -n 1 -s -r -p "Taste drücken, um fortzufahren"
    ;;
  1)
    echo "Keine Auswahl getroffen."
    ;;
  255)
    echo "Box geschlossen."
    ;;
  esac

  # Temporäre Datei löschen
  rm -f /tmp/dialogoutput

  caps="laksjdlknlak dnqwd "
}

# Generate CSV list containing all certificates
refresh_certs_list() {
  local certs=()
  echo "CNAME;CTYPE;CISSUED;CRENEW;CEXPIRE;CSN;CSELECTED">"$CERT_CSV_LIST"

  for cert in "$EASYRSA_PKI"/issued/*.crt; do
    local name="Unknown"
    local type="Unknown"
    local issue_date="Unknown"
    local renew_date="Unknown"
    local expire_date="Unknown"
    local serial="Unknown"
    local selected="off"

    name=$(basename "$cert" .crt)

    # Get text dump from certificate file
    OUTPUT=$(easyrsa show-cert "$name")

    # extract issue date, expire date and renew date
    issue_date_raw=$(echo "$OUTPUT" | grep 'Not Before:' | sed 's/Not Before: //g')
    issue_date=$(date -d "$issue_date_raw" +"%d.%m.%y" 2>/dev/null)
    expire_date_raw=$(echo "$OUTPUT" | grep 'Not After :' | sed 's/Not After : //g')
    expire_date=$(date -d "$expire_date_raw" +"%d.%m.%y" 2>/dev/null)
    renew_date_raw=$(date -d "$expire_date_raw -$CERT_RENEW_DAYS days" +"%F %R" 2>/dev/null)
    renew_date=$(date -d "$renew_date_raw" +"%d.%m.%y" 2>/dev/null)

    current_date_epoch=$(date +%s)
    renew_date_epoch=$(date -d "$renew_date_raw" +%s)

    if [ "$current_date_epoch" -gt "$renew_date_epoch" ]; then
      renew_date="renewable"
    fi

    # get extended key usage
    if echo "$OUTPUT" | grep -q 'TLS Web Server Authentication'; then
      type="Server"
    elif echo "$OUTPUT" | grep -q 'TLS Web Client Authentication'; then
      type="Client"
    fi

    # check if certificate is a ca certificate
    if echo "$OUTPUT" | grep -q 'CA:TRUE' && echo "$OUTPUT" | grep -q 'Certificate Sign' && echo "$OUTPUT" | grep -q 'CRL Sign'; then
      type="CA"
    fi

    serial_full=$(echo "$OUTPUT" | awk '/Serial Number:/ {getline; print}' | tr -d '[:space:]' | tr -d ':')
    serial=${serial_full: -4}

    echo -e "$name;$type;$issue_date;$renew_date;$expire_date;$serial;$selected" >>$CERT_CSV_LIST
  done

}

sort_certs_list() {
  local header
  header=$(head -n 1 "$CERT_CSV_LIST")
  tail -n +2 "$CERT_CSV_LIST" | sort -t ";" -k 4 -o "temp.csv"

  {
    echo "$header"
    cat "temp.csv"
  } > "$CERT_CSV_LIST"

  rm "temp.csv"
}

# Funktion, um Zertifikate zu listen und in dialog zu verwenden
list_certs() {
  local checklist
  local selected_certs

  refresh_certs_list
  sort_certs_list

  tail -n +2 "$CERT_CSV_LIST" | while IFS=';' read -r CNAME CTYPE CISSUED CRENEW CEXPIRE CSN CSELECTED; do
    checklist+=("$CNAME" "$CTYPE|$CISSUED|$CRENEW|$CEXPIRE|$CSN" "$CSELECTED")
  done

  dialog --checklist "Wähle Zertifikate (Name | Typ | Erstellt | Erneuerung | Ablauf | SN):" 20 90 15 "${checklist[@]}" 2>tempfile
  local exit_status=$?
  if [ $exit_status -eq 0 ]; then
    # Benutzer hat 'OK' gewählt, lies die Auswahl aus der Datei
    selected_certs=$(<tempfile)
    # Zeige ein weiteres Menü für die Aktionen
    action_menu "$selected_certs"
  fi
}

# Funktion, um Zertifikate zu listen und in dialog zu verwenden
list_crl() {
  local certs=()
  clear
  for cert in "$EASYRSA_PKI"/revoked/certs_by_serial/*.crt; do
    local serial="Unknown"
    local type="Unknown"
    local issue_date="Unknown"
    local renew_date="Unknown"
    local expire_date="Unknown"
    local name="Unknown"

    serial=$(basename $cert .crt)
    OUTPUT=$(openssl x509 -text -noout -in $cert)

    name=$(openssl x509 -noout -subject -in "$cert" | sed -n '/^subject/s/^.*CN\s*=\(.*\)/\1/p')

    # Extrahiere das Erstellungsdatum, Ablaufdatum und frühestes Erneuerungsdatum
    issue_date_raw=$(openssl x509 -noout -startdate -in "$cert" | cut -d= -f2)
    issue_date=$(date -d "$issue_date_raw" +"%d.%m.%y" 2>/dev/null)

    expire_date_raw=$(openssl x509 -noout -enddate -in "$cert" | cut -d= -f2)
    expire_date=$(date -d "$expire_date_raw" +"%d.%m.%y" 2>/dev/null)

    renew_date_raw=$(date -d "$expire_date_raw -$CERT_RENEW_DAYS days" +"%F %R" 2>/dev/null)
    renew_date=$(date -d "$renew_date_raw" +"%d.%m.%y" 2>/dev/null)
    renew_date=$(trim "$renew_date")

    current_date_epoch=$(date +%s)
    renew_date_epoch=$(date -d "$renew_date_raw" +%s)

    if [ $current_date_epoch -gt $renew_date_epoch ]; then
      renew_date="renewable"
    fi

    # Überprüfe auf Extended Key Usage
    if echo "$OUTPUT" | grep -q 'TLS Web Server Authentication'; then
      type="Server"
    elif echo "$OUTPUT" | grep -q 'TLS Web Client Authentication'; then
      type="Client"
    fi

    # Überprüfe auf CA Zertifikat
    if echo "$OUTPUT" | grep -q 'CA:TRUE' && echo "$OUTPUT" | grep -q 'Certificate Sign' && echo "$OUTPUT" | grep -q 'CRL Sign'; then
      type="CA"
    fi

    serial_full=$(echo "$OUTPUT" | awk '/Serial Number:/ {getline; print}' | tr -d '[:space:]' | tr -d ':')
    serial=${serial_full: -4}

    certs+=("$name" "$type $issue_date $renew_date $expire_date $serial")
  done

  dialog --menu "Wähle Zertifikate (Name | Typ | Erstellt | Erneuerung | Ablauf | SN):" 20 90 15 "${certs[@]}" 2>tempfile
  local exit_status=$?

}

# Funktion, um ein Menü für Aktionen anzuzeigen
action_menu() {
  local selected_certs=$1
  exec 3>&1
  local action=$(dialog \
    --backtitle "EasyRSA Verwaltung" \
    --title "Aktion wählen" \
    --clear \
    --cancel-label "Zurück" \
    --menu "Bitte wähle eine Aktion für die ausgewählten Zertifikate:" 20 70 4 \
    "1" "Erneuern" \
    "2" "Sperren" \
    2>&1 1>&3)
  local action_status=$?
  exec 3>&-
  case $action_status in
  0)
    case $action in
    1)
      renew_certs "$selected_certs"
      ;;
    2)
      revoke_certs "$selected_certs"
      ;;
    esac
    ;;
  *)
    return
    ;;
  esac
}

# Funktion, um Informationen zur CA anzuzeigen
show_ca_info() {
  # Hier müssten die entsprechenden Daten aus der CA extrahiert werden
  # Dies ist ein Platzhalter für die tatsächliche Implementierung
  dialog --msgbox "CA-Informationen: (Platzhalter)" 20 70
}

# Funktion, um gesperrte Zertifikate zu listen
list_revoked_certs() {
  # Hier müssten die entsprechenden Daten aus der CRL extrahiert werden
  # Dies ist ein Platzhalter für die tatsächliche Implementierung
  dialog --msgbox "Gesperrte Zertifikate: (Platzhalter)" 20 70
}

# Hauptmenü
while true; do
  exec 3>&1
  selection=$(dialog \
    --backtitle "EasyRSA Verwaltung" \
    --title "Hauptmenü" \
    --clear \
    --cancel-label "Exit" \
    --menu "Bitte wähle eine Aktion:" 20 70 4 \
    "1" "Zertifikate bearbeiten" \
    "2" "Neues Zertifikat erstellen" \
    "3" "Zeige CA-Informationen" \
    "4" "Liste gesperrte Zertifikate" \
    2>&1 1>&3)
  exit_status=$?
  exec 3>&-
  case $exit_status in
  1)
    clear
    echo "Programm beendet."
    exit
    ;;
  255)
    clear
    echo "Programm unerwartet beendet."
    exit 1
    ;;
  esac
  case $selection in
  1)
    list_certs
    ;;
  2)
    new_cert
    ;;
  3)
    show_ca_info
    ;;
  4)
    list_crl
    ;;
  esac
done
