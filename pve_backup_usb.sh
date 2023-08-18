################################################################################
# Simple backup script to mirror local Proxmox PVE dump backups to encrypted
# external USB drives, including proper logging and optional email
# notifications.
#
# Author(s): Andreas Haerter <ah@foundata.com>
################################################################################



################################################################################
# Environment
################################################################################
PATH='/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin'
LANG=en_US.UTF-8
LC_ALL="en_US.UTF-8"
set -u



################################################################################
# Command line arguments
################################################################################

# init
opt_backupcfg_list='' # -b
opt_checksums='0' # -c
opt_luks_target_uuid='' # -d
opt_email_to='' # -e
opt_email_from='' # -f
opt_email_cc='' # -g
opt_cryptsetup_keyfile_path='' # -k
opt_target_mappername='' # -l
opt_quiet='0' # -q
opt_source_paths_pvedumps_list='' # -s
opt_backup_user='' # -u

# parse options
opt=''
OPTIND='1'
while getopts ':qb:cd:e:f:g:l:s:u:h' opt
do
    case "${opt}" in
        # backup config
        'b')
            opt_backupcfg_list="${OPTARG}"
            if ! printf '%s' "${opt_backupcfg_list}" | grep -E -q -e "^[0-9][0-9:,]*$"
            then
                opt_backupcfg_list=''
                printf '%s: invalid value for "%s", ignoring it.\n' "$(basename "${0}")" "${opt}" 1>&2
                exit 2
            fi
            ;;

        # checksums flag
        'c')
            opt_checksums='1'
            ;;

        # disk UUID
        'd')
            opt_luks_target_uuid="${OPTARG}"
            if ! printf '%s' "${opt_luks_target_uuid}" | grep -E -q -e "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
            then
                opt_email_to=''
                printf '%s: invalid value for "%s", ignoring it.\n' "$(basename "${0}")" "${opt}" 1>&2
                exit 2
            fi
            ;;

        # email to
        'e')
            opt_email_to="${OPTARG}"
            if ! printf '%s' "${opt_email_to}" | grep -E -q -e "^.+@.+$"
            then
                opt_email_to=''
                printf '%s: invalid value for "%s", ignoring it.\n' "$(basename "${0}")" "${opt}" 1>&2
                exit 2
            fi
            ;;

        # email from
        'f')
            opt_email_from="${OPTARG}"
            if ! printf '%s' "${opt_email_from}" | grep -E -q -e "^.+@.+$"
            then
                opt_email_from=''
                printf '%s: invalid value for "%s", ignoring it.\n' "$(basename "${0}")" "${opt}" 1>&2
                exit 2
            fi
            ;;

        # email cc (CSV list)
        'g')
            opt_email_cc="${OPTARG}"
            if ! printf '%s' "${opt_email_cc}" | grep -E -q -e "^.+@.+$" # works for CSV, too
            then
                opt_email_cc=''
                printf '%s: invalid value for "%s", ignoring it.\n' "$(basename "${0}")" "${opt}" 1>&2
                exit 2
            fi
            ;;

        # key file
        'k')
            opt_cryptsetup_keyfile_path="${OPTARG}"
            if [ -z "${opt_cryptsetup_keyfile_path}" ]
            then
                opt_cryptsetup_keyfile_path=''
                printf '%s: invalid value for "%s", ignoring it.\n' "$(basename "${0}")" "${opt}" 1>&2
                exit 2
            fi
            ;;

        # name used for handling LUKS via /dev/mapper/ and creating a mountpoint at /media/
        'l')
            opt_target_mappername="${OPTARG}"
            if [ -z "${opt_target_mappername}" ] ||
               ! printf '%s' "${opt_target_mappername}" | grep -E -q -e "^[[:alnum:]_\-]{1,16}$"
            then
                opt_target_mappername=''
                printf '%s: invalid value for "%s", ignoring it.\n' "$(basename "${0}")" "${opt}" 1>&2
                exit 2
            fi
            ;;

        # source dirs
        's')
            opt_source_paths_pvedumps_list="${OPTARG}"
            if [ -z "${opt_source_paths_pvedumps_list}" ]
            then
                opt_source_paths_pvedumps_list=''
                printf '%s: invalid value for "%s", ignoring it.\n' "$(basename "${0}")" "${opt}" 1>&2
                exit 2
            fi
            ;;

        # user
        'u')
            opt_backup_user="${OPTARG}"
            if [ -z "${opt_backup_user}" ]
            then
                opt_backup_user=''
                printf '%s: invalid value for "%s", ignoring it.\n' "$(basename "${0}")" "${opt}" 1>&2
                exit 2
            fi
            ;;

        # quiet mode
        'q')
            opt_quiet='1'
            ;;

        # show help
        'h')
            filename="$(basename "${0}")"
            mantext="$(cat <<-DELIM
.TH ${filename} 1
.SH NAME
${filename} - Simple script to mirror local Proxmox PVE dump backups
to encrypted USB drives, including proper logging and optional email
notifications.

.SH SYNOPSIS
.B ${filename}
.PP
.BI "-b " "PveID[:maxCount[,PveID:maxCount[,...]]]" ""
.B [-c]
.BI "[-d " "UUID of a disk to decrypt" "]"
.BI "[-e " "email@example.com" "]"
.BI "[-f " "email@example.org" "]"
.BI "[-g " "email@example.com[,email@example.net[,...]]" "]"
.BI "[-k " "/path/to/keyfile" "]"
.BI "[-l " "mapper and mount point name" "]"
.BI "[-s " "/pve1/dumps[:/pve2/dumps:...]" "]"
.BI "[-u " "username" "]"
.B [-q]

.SH DESCRIPTION
See the inline documentation at the top of the script file for
a detailled description.

.SH OPTIONS
.TP
.B -b
Defines which backups of wich PVE dumps will be copied. Format:
A CSV list of "PveId:maxCount" value tuples. ":maxCount" is
optional, all backups for PveId will be copied if maxCount is not
given. Example: "123:2,456:4,789" will copy the last two backups
of machine 123, the last four of machine 456 and all of machine
789.
.TP
.B -c
Enable checksum creation and verification of the copies (recommended
for safety but propably doubles the the time needed).
.B -d
A UUID of the target partition to decrypt. Will be used to search
it in /dev/disk/by-uuid/ (you might use 'blkid /dev/sdX1' to
determine the UUID). By default, the script is simply using the
first partition on the first USB disk it is able to find via
/dev/disk/by-path/. No worries: existing drives not used for
backups won't be destroyed as the decryption will fail. But this
automatism presumes that only one USB disk is connected during the
script run. Defining a UUID will work when there are more.
.B -e
Email address to send notifications to. Format: 'email@example.com'.
Has to be set for sending mails.
.B -f
Email address to send notifications from. Format: 'email@example.com'.
Has to be set for sending mails. Defaults to "do-not-reply@$(hostname -d)".
.B -g
Email address(es) to send notifications to (CC). Format: 'email@example.com'.
Separate multiple addresses via comma (CSV list).
.B -k
Path to a keyfile containing a passphrase to unlock the target
device. Defaults to "/etc/credentials/luks/pve_backup_usb".
.B -l
Name used for handling LUKS via /dev/mapper/ and creating a
mountpoint subdir with this name at /media/. Defaults to
"pve_backup_usb". 16 alphanumeric chars at max.
.B -s
List of one or more directories to search for PVE dumps, separated
by ":"; without trailing slash. Example: "/pve1/dumps:/pve2/dumps".
.B -u
Username of the account used to run the backups. Defaults to "root".
This script checks if the correct user is calling the script and
permission to e.g. the keyfile and sources are fitting for this
user.
.TP
.B -h
Print this help.
.TP
.B -q
Enable quiet mode: emails will be sent only on error.


.SH EXIT STATUS
This program returns an exit status of zero if it succeeds. Non zero
is returned in case of failure. 2 will be returned for command line
syntax errors (e.g. usage of an unknown option).

.SH AUTHOR
Andreas Haerter <ah@foundata.com>
DELIM
)"
            if command -v 'mandoc' > /dev/null 2>&1
            then
                printf '%s' "${mantext}" | mandoc -Tascii -man | more
            elif command -v 'groff' > /dev/null 2>&1
            then
                printf '%s' "${mantext}" | groff -Tascii -man | more
            else
                printf '%s: Neither "mandoc" nor "groff" is available, cannot display help.\n' "$(basename "${0}")" 1>&2
                exit 1
            fi
            unset filename mantext
            exit 0
            ;;

        # unknown/not supported -> kill script and inform user
        *)
            printf '%s: unknown option "-%c". Use "-h" to get usage instructions.\n' "$(basename "${0}")" "${OPTARG}" 1>&2
            exit 2
            ;;
    esac
done
unset opt OPTARG
shift $((${OPTIND} - 1)) && OPTIND='1' # delete processed options, reset index



################################################################################
# Config
################################################################################
if [ -z "${opt_backupcfg_list}" ]
then
    printf '%s: option "-b" is mandatory. Use "-h" to get usage instructions.\n' "$(basename "${0}")" 1>&2
    exit 2
fi
IFS=',' read -r -a backupcfg_array <<< "${opt_backupcfg_list}"
readonly backupcfg_array

if [ -z "${opt_luks_target_uuid}" ]
then
    readonly luks_target_uuid=""
else
    readonly luks_target_uuid="${opt_luks_target_uuid}"
fi

if [ -z "${opt_backup_user}" ]
then
    readonly backup_user="root"
else
    readonly backup_user="${opt_backup_user}"
fi

if [ -z "${opt_source_paths_pvedumps_list}" ]
then
    printf '%s: option "-s" is mandatory. Use "-h" to get usage instructions.\n' "$(basename "${0}")" 1>&2
    exit 2
fi
readonly source_paths_pvedumps_list="${opt_source_paths_pvedumps_list}"
IFS=':' read -r -a source_paths_pvedumps_array <<< "${source_paths_pvedumps_list}"
readonly source_paths_pvedumps_array

if [ -z "${opt_target_mappername}" ] # used for handling LUKS via /dev/mapper/ and creating a mountpoint at /media/
then
    readonly target_mappername="pve_backup_usb"
else
    readonly target_mappername="${opt_target_mappername}"
fi
readonly target_mountpoint_path="/media/${target_mappername}" # without trailing slash

if [ -z "${opt_cryptsetup_keyfile_path}" ]
then
    readonly cryptsetup_keyfile_path="/etc/credentials/luks/pve_backup_usb"
else
    readonly cryptsetup_keyfile_path="${opt_cryptsetup_keyfile_path}"
fi
readonly target_subdir="dump" # name of subdir on $target_mountpoint_path to copy the files into
readonly target_subdir_old="dump_old" # name of subdir on $target_mountpoint_path to copy to temporarily move old copies to

readonly hostname="$(hostname -f)"

if [ -z "${opt_email_to}" ]
then
    readonly email_to=""
else
    readonly email_to="${opt_email_to}"
fi
if [ -z "${opt_email_from}" ]
then
    domain="$(hostname -d)"
    if [ -z "${domain}" ]
    then
        domain="example.com"
    fi
    readonly email_from="do-not-reply@${domain}"
else
    readonly email_from="${opt_email_from}"
fi
if [ -z "${opt_email_cc}" ]
then
    readonly email_cc=""
else
    readonly email_cc="${opt_email_cc}"
fi




################################################################################
# Functions
################################################################################

###
# Helper to end the script, cleanup and inform/log/mail.
#
# @param string the message
# @param string optional, type to handle the message / environment during
#        exit ("error", "info", "success"). Unknown type will be handled as
#        "info". Defaults to "info".
# @return integer Zero if execution succeeds, non-zero in case of failure.
endScript() {
    local message="${1}"
    local type=""
    if [ -z "${2:-}" ]
    then
        type="info"
    else
        type="${2}"
    fi

    if [ "${type}" != "error" ] &&
       [ "${type}" != "info" ] &&
       [ "${type}" != "success" ]
    then
        message "Unknown message type "${type}". Using 'info'." "error"
        type="info"
    fi

    # write message on STDOUT or STDERR as well as the logfile
    message "${message}" "${type}"

    # create syslog entry
    syslog "${message}" "${type}"

    # clean up
    syncUmountAndClose

    # send email
    local mailmessage="${message}"
    if [ -r "${logfile_path}" ]
    then
        mailmessage=$(printf '%s\n\nContent of logfile follows:\n\n%s' "${mailmessage}" "$(cat "${logfile_path}")")
    fi
    sendEmail "${mailmessage}" "${type}"
    unset mailmessage

    if [ -f "${logfile_path}" ]
    then
        rm -f "${logfile_path}" > /dev/null 2>&1
    fi

    if [ "${type}" = "error" ]
    then
        exit 1
    fi
    exit 0
}


###
# Helper to create syslog entries
#
# @param string the message
# @param string optional, type / priority to syslog entry to handle
#        ("error" (maps to priority "err"), "info" (maps to priority "info")),
#        "success" (maps to "info")). Unknown type will be handled as
#        "info". Defaults to "info".
# @return integer Zero if execution succeeds, non-zero in case of failure.
syslog() {
    local message="${1}"
    local type=""
    if [ -z "${2:-}" ]
    then
        type="info"
    else
        type="${2}"
    fi

    if [ "${type}" != "error" ] &&
       [ "${type}" != "info" ] &&
       [ "${type}" != "success" ]
    then
        message "Unknown message type "${type}". Using 'info'." "error"
        type="info"
    fi

    if ! command -v "logger" > /dev/null 2>&1
    then
        message "'logger' could not be found (no syslogs will be written)." "error"
        return 1
    else
        if [ "${type}" = "success" ] ||
           [ "${type}" = "info" ]
        then
            logger_priority="info"
        else
            logger_priority="err"
        fi
        logger --tag "$(basename "${0}")" --priority "${logger_priority}" "${message}"
        exitcode_logger=$?
        if [ $exitcode_logger -ne 0 ]
        then
            message "'logger' exited with code "${exitcode_logger}"" "error"
            return 1
        else
            message "Syslog entry was created (priority: "${logger_priority}")"
        fi
    fi
    return 0
}


###
# Small handler to print messages to STDOUT, STDERR and write them into the logfile
# (created automatically when this script started, cf. $logfile_path) in parallel.
#
# @param string the message to print and write to logfile.
# @param string optional, type of the message ("error", "info", "success").
#        Unknown type will be handled as "info". Defaults to "info". "error"
#        will be written to STDERR, everything elso to STDOUT.
# @return no return, exit will be called with exit code 1 if type or result
#         was set to "error" and 0 when "success".
message() {
    local message="${1}"
    local type=""
    if [ -z "${2:-}" ]
    then
        type="info"
    else
        type="${2}"
    fi

    if [ "${type}" != "error" ] &&
       [ "${type}" != "info" ] &&
       [ "${type}" != "success" ]
    then
        message "Unknown message type "${type}". Using 'info'." "error"
        type="info"
    fi

    # print to STDOUT or STDERR
    if [ "${type}" = "success" ] ||
       [ "${type}" = "info" ]
    then
        printf '%s: %s\n' "$(basename "${0}")" "${message}"
    else
        printf '%s: %s\n' "$(basename "${0}")" "${message}" 1>&2
    fi

    # write into logfile
    if [ -w "${logfile_path}" ]
    then
        printf '%s\n' "${message}" >> "${logfile_path}"
    fi

    return 0
}


###
# Helper to send emails
#
# @param string the message
# @param string type / priority to syslog entry to handle ("error", "info", "success").
#        Unknown type will be handled as "info". Defaults to "info".
# @return integer Zero if execution succeeds, non-zero in case of failure.
sendEmail() {
    local message="${1}"
    local type=""
    if [ -z "${2:-}" ]
    then
        type="info"
    else
        type="${2}"
    fi

    if [ "${type}" != "error" ] &&
       [ "${type}" != "info" ] &&
       [ "${type}" != "success" ]
    then
        message "Unknown message type "${type}". Using 'info'." "error"
        type="info"
    fi

    # email
    if [ "${type}" = "error" ] ||
       [ "${opt_quiet}" != "1" ]
    then
        if ! command -v "mail" > /dev/null 2>&1
        then
            message "'mail' could not be found (email was not sent)." "error"
            return 1
        elif [ -z "${email_from}" ] ||
             [ -z "${email_to}" ]
        then
            message "Email receiver and/or sender is not defined (no email will be sent). Please set the parameters -e and/or -f." "error"
            return 1
        else
            local subject="[$(basename "${0}")] ${type} on ${hostname}"
            if [ -z "${email_cc}" ]
            then
                printf '%s' "${message}" | mail -s "${subject}" -r "${email_from}" "${email_to}"
                exitcode_mail=$?
            else
                printf '%s' "${message}" | mail -s "${subject}" -r "${email_from}" -c "${email_cc}" "${email_to}"
                exitcode_mail=$?
            fi
            unset subject
            if [ $exitcode_mail -ne 0 ]
            then
                message "'mail' command exited with code ${exitcode_mail}" "error"
                return 1
            else
                if [ -z "${email_cc}" ]
                then
                    message "Email to '${email_to}' was sent."
                else
                    message "Email to '${email_to}' (CC: ${email_cc}) was sent."
                fi
            fi
            unset exitcode_mail
        fi
    fi
    return 0
}


###
# Unmounts und closes the backup target device if needed (best effort)
#
# @return integer Zero if execution succeeds, non-zero in case of failure.
function syncUmountAndClose() {
    sync > /dev/null 2>&1

    if umount "${target_mountpoint_path}" > /dev/null 2>&1
    then
        message "Successfully unmounted '${target_mountpoint_path}'"
        if [ -d "${target_mountpoint_path}" ] &&
           [ -n "$(find "${target_mountpoint_path}" -maxdepth 0 -empty -exec echo {} is empty. \; 2>/dev/null)" ]
           rmdir "${target_mountpoint_path}" > /dev/null 2>&1
        then
            message "Successfully deleted mounpoint '${target_mountpoint_path}'."
        fi
    fi

    if cryptsetup luksClose "${target_mappername}" > /dev/null 2>&1
    then
        message "Successfully closed LUKS device '${target_mappername}'"
    fi
    sync > /dev/null 2>&1

    return 0
}



################################################################################
# Process
################################################################################

# fallback cleanup endScript should taking care of this
trap 'syncUmountAndClose' EXIT SIGINT SIGTERM


# securely create a temporary file
tempfile=''
: "${TMPDIR:=/tmp}" # if env var ${TMPDIR} is empty, set its value to /tmp
if command -v 'mktemp' > /dev/null 2>&1
then
    mask_save="$(umask)"; umask 077 # temporarily change mask
    tempfile="$(mktemp "${TMPDIR}/XXXXXXXXXXXXXX")" || tempfile='';
    umask "${mask_save}"; unset mask_save # restore mask
else
    mask_save="$(umask)"; umask 077 # temporarily change mask
    tempfile="${TMPDIR}/$(awk -v p="$$" 'BEGIN { srand(); s = rand(); sub(/^0./, "", s); printf("%X%X", p, s) }')"
    touch "${tempfile}" > /dev/null 2>&1 || tempfile='';
    umask "${mask_save}"; unset mask_save # restore mask
fi
if [ -z "${tempfile}" ] || ! [ -f "${tempfile}" ]
then
    endScript "Creation of temporary file failed:\n${tempfile}"
    exit 1 # endScript should exit, this is just a fallback
fi


# set new tempfile as logfile
logfile_path="${tempfile}"


# check if there is another instance of this script
if [ $(lsof -t "${0}" | wc -l) -gt 1 ]; then
    endScript "'losof' check failed, another instance of ${0} seems to be running (this might be a false positive if another process is accessing the script). Exiting." "error"
    exit 1 # endScript should exit, this is just a fallback
fi


# make sure the script is executed by the correct user
if [ "$(id -u -n)" != "${backup_user}" ]
then
    endScript "Wrong user '$(id -u -n)'. Script has to be executed as user '${backup_user}'." "error"
    exit 1 # endScript should exit, this is just a fallback
fi


# check if needed commands and tools are available
for cmd in "cut" "cryptsetup" "date" "df" "du" "fold" "hostname" "hdparm" "logger" "lsblk" "lsof" "mail" "mountpoint" "numfmt" "rmdir" "stat" "sum"
do
    if ! command -v "${cmd}" > /dev/null 2>&1
    then
        endScript "'${cmd}' could not be found but is needed for execution." "error"
        exit 1 # endScript should exit, this is just a fallback
    fi
done
unset cmd


# check if key file is available and its permissions are restrictive
if ! [ -f "${cryptsetup_keyfile_path}" ]
then
    endScript "Key file to unlock targets is not accessible or no file: '${cryptsetup_keyfile_path}'." "error"
    exit 1 # endScript should exit, this is just a fallback
fi
if [ "$(stat --printf '%U' "${cryptsetup_keyfile_path}")" != "${backup_user}" ]
then
    endScript "Key file '${cryptsetup_keyfile_path}' is not owned by '${backup_user}'." "error"
    exit 1 # endScript should exit, this is just a fallback
fi
filepermission="$(stat --printf '%a' "${cryptsetup_keyfile_path}")"
filepermission_owner="${filepermission:0:1}"
filepermission_group="${filepermission:1:1}"
filepermission_world="${filepermission:2:1}"
if [ $(($filepermission_world+0)) -gt 0 ] ||
   [ -x "${cryptsetup_keyfile_path}" ]
then
    endScript "Access rights for '${cryptsetup_keyfile_path}' are too permissive. Please make sure the file is owned by '${backup_user}', not executable and not world-readable." "error"
    exit 1 # endScript should exit, this is just a fallback
fi
unset filepermission filepermission_owner filepermission_group filepermission_world


# check if source dir(s) are available
for path_pvedumps_source in "${source_paths_pvedumps_array[@]}"
do
    if ! [ -d "${path_pvedumps_source}" ]
    then
        endScript "Backup source is not accessible or no dir: '${path_pvedumps_source}'." "error"
        exit 1 # endScript should exit, this is just a fallback
    fi
done
unset path_pvedumps_source


# take care about stale or previously interrupted execs
message "#### $(basename "${0}") ####"
message "CSV list of 'PveMachineID[:MaxBackupCount]' entries (defines what to copy): '${opt_backupcfg_list}'"
message "Sync, unmount and close of LUKS device (upfront safeguard against stale or previously interrupted execs)."
syncUmountAndClose


# create target mountpoint if needed
if ! [ -d "${target_mountpoint_path}" ] &&
   ! [ -f "${target_mountpoint_path}" ]
then
    message "Creating mountpoint at '${target_mountpoint_path}'"
    mkdir -p "${target_mountpoint_path}"
fi


# check if target mountpoint is accessible and empty
if ! [ -d "${target_mountpoint_path}" ] ||
   ! [ -n "$(find "${target_mountpoint_path}" -maxdepth 0 -empty -exec echo {} is empty. \; 2>/dev/null)" ]
then
    endScript "Mount point for taget disk is no directory or not empty: '${target_mountpoint_path}'." "error"
    exit 1 # endScript should exit, this is just a fallback
fi


# unlock target device
luks_target=""
if [ -n "${luks_target_uuid}" ]
then
    luks_target="/dev/disk/by-uuid/${luks_target_uuid}"
else
    luks_target="/dev/$(ls -l /dev/disk/by-path/*usb*part1 | cut -f 7 -d "/" | head -n 1)"
fi
message "Going to unlock '${luks_target}', using using keyfile '${cryptsetup_keyfile_path}'"
if ! cryptsetup open --key-file "${cryptsetup_keyfile_path}" "${luks_target}" "${target_mappername}"
then
    endScript "Could not unlock device '${luks_target}' (wrong device?), using keyfile "${cryptsetup_keyfile_path}" (wrong key?)." "error"
    exit 1 # endScript should exit, this is just a fallback
else
    message "Successfully unlocked '${luks_target}', should be available at '/dev/mapper/${target_mappername}' now."
fi
unset luks_target


# mount
if ! mount "/dev/mapper/${target_mappername}" "${target_mountpoint_path}"
then
    endScript "Could not mount '/dev/mapper/${target_mappername}' at '${target_mountpoint_path}'." "error"
    exit 1 # endScript should exit, this is just a fallback
fi


# inform about elapsed time
time_elapsed=""
if ! [ -z "${SECONDS:-}" ] # $SECONDS is a bash internal var
then
    time_elapsed=$SECONDS
    time_elapsed="$(printf '%02dh:%02dm:%02ds\n' $((time_elapsed/3600)) $((time_elapsed%3600/60)) $((time_elapsed%60)))"
fi
message "Elapsed time: ${time_elapsed}."
unset time_elapsed


# disk info (best effort)
device_name="$(lsblk -l -i -s "/dev/mapper/${target_mappername}" | tail -1 | cut -f1 -d' ' 2>/dev/null)"
if [ -n "${device_name}" ]
then
    output_hdparm="$(hdparm -I "/dev/${device_name}" 2>/dev/null)"
    exitcode_hdparm=$?
    if [ $exitcode_hdparm -eq 0 ] &&
       [ -n "${output_hdparm}" ]
    then
        output_hdparm="$(printf '%s' "${output_hdparm}" | grep -i "number" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        if [ -n "${output_hdparm}" ]
        then
            message ""
            message "#### Info about physical disk (mounted at ${target_mountpoint_path}) ####"
            ifs_save="${IFS}"; IFS="$(printf '\n+')"; IFS="${IFS%?}" # temporarily change IFS to "\n" (LF)
            for line in ${output_hdparm}
            do
                message "${line}"
            done
            IFS="${ifs_save}"; unset ifs_save # restore IFS
            unset line output_hdparm
        fi
    fi
    unset exitcode_hdparm output_hdparm
fi
unset device_name


# init bash array to store backup sources for the cp and find commands
unset backup_sources_cp
backup_sources_cp=()

for cfgvalues in "${backupcfg_array[@]}"
do
    # parse config data for the PVE item
    unset tuple
    IFS=':' read -r -a tuple <<< "${cfgvalues}"
    cfg_pve_id="${tuple[0]}"
    if [ -v "tuple[1]" ]
    then
        cfg_maxLastCopies="${tuple[1]}"
    else
        cfg_maxLastCopies="unlimited"
    fi
    unset tuple

    # detect filename prefixes (to easily search fot all files belonging to a
    # certain backup (dump, log, notes ...) of the defined VMs)
    backuplist=() # init bash array to store these backup filename prefixes
    message ""
    message "#### Checking for existing backups to copy for PVE ID ${cfg_pve_id} ####"
    for path_pvedumps_source in "${source_paths_pvedumps_array[@]}"
    do
        last_found_backup_prefix=""
        ifs_save="${IFS}"; IFS="$(printf '\n+')"; IFS="${IFS%?}" # temporarily change IFS to "\n" (LF)
        for resource in $(find "${path_pvedumps_source}" -iname "vzdump-*-${cfg_pve_id}-*" -type f | sort -r)
        do
            resource_dir="$(dirname "${resource}"; printf '+')"; resource_dir="${resource_dir%??}"
            resource_filename="$(basename "${resource}"; printf '+')"; resource_filename="${resource_filename%??}"
            # Example filenames of a backup (many parts are non-static, e.g.
            # extension depend on backup type):
            # - vzdump-qemu-120-2023_08_04-21_00_04.vma.zst
            # - vzdump-qemu-120-2023_08_04-21_00_04.vma.zst.notes
            # - vzdump-qemu-120-2023_08_09-21_00_05.log
            backup_date=$(printf "%s" "${resource_filename}" | awk -F- '{print $(NF-1)}')
            backup_time=$(printf "%s" "${resource_filename}" | awk -F- '{print $(NF)}' | awk -F. '{print $1}')
            backup_prefix=$(printf "%s" "${resource_filename}" | awk -F"${cfg_pve_id}-${backup_date}-${backup_time}" '{print $1}')
            backup_prefix="${backup_prefix}${cfg_pve_id}-${backup_date}-${backup_time}"
            if [ "${backup_prefix}" != "${last_found_backup_prefix}" ]
            then
                message "Found backup '${backup_prefix}' in '${resource_dir}'"
                backuplist[${#backuplist[@]}]="${backup_prefix}:${resource_dir}"
                last_found_backup_prefix="${backup_prefix}"
            fi
        done
        IFS="${ifs_save}"; unset ifs_save # restore IFS
        unset last_found_backup_prefix resource resource_dir resource_filename backup_date backup_time backup_prefix
    done
    unset path_pvedumps_source

    # sort and keep only the newest cfg_maxLastCopies
    IFS=$'\n' backuplist_sorted=($(sort -r <<<"${backuplist[*]}"))
    unset backuplist

    addedCopies="0"
    for item in "${backuplist_sorted[@]}"
    do
        unset tuple
        IFS=':' read -r -a tuple <<< "${item}"
        if [ "${cfg_maxLastCopies}" = "unlimited" ] ||
           [ $(($addedCopies+0)) -lt $(($cfg_maxLastCopies+0)) ]
        then
            message "Added backup '${tuple[0]}' to the list for processing."
            backup_sources_cp[(${#backup_sources_cp[@]})]="${tuple[1]}/${tuple[0]}" # no complete path, but can be used with globbing / *
            addedCopies="$((${addedCopies}+1))"
        else
            message "Skipped backup '${tuple[0]}' as max backup count ${cfg_maxLastCopies} for ID '${cfg_pve_id}' was reached."
        fi
    done
    unset item tuple addedCopies
done
unset cfg_pve_id cfg_maxLastCopies tuple


message ""
message "#### Miscellaneous preparation ####"


# determine size of data (in bytes) to be copied
bytes_needed=0
for source_item in "${backup_sources_cp[@]}"
do
    ifs_save="${IFS}"; IFS="$(printf '\n+')"; IFS="${IFS%?}" # temporarily change IFS to "\n" (LF)
    for resource in $(find "$(dirname ${source_item})" -iname "$(basename ${source_item})*" -type f)
    do
        bytes_needed="$((${bytes_needed}+$(stat --printf '%s' ${resource})))"
    done
    IFS="${ifs_save}"; unset ifs_save # restore IFS
done
bytes_needed_human="$(numfmt --to=iec-i --suffix=B --format='%.2f' ${bytes_needed})"
message "Copying the backup files will need ${bytes_needed_human} of space on the target device."


# analyze target device
bytes_target_size=$(($(df --output=avail -B 1 "${target_mountpoint_path}" | tail -n 1)+0))
bytes_target_size=$((${bytes_target_size} - 1074000000)) # ~ roughly 1 GiB buffer
bytes_target_size_human="$(numfmt --to=iec-i --suffix=B --format='%.2f' ${bytes_target_size})"
message "The target device mounted at '${target_mountpoint_path}' has a size of about ${bytes_target_size_human}."
if [ $(($bytes_needed+0)) -gt  $(($bytes_target_size+0)) ]
then
    endScript "The target device '${target_mountpoint_path}' is not big enough (size of ${bytes_target_size_human} but ${bytes_needed_human} needed)." "error"
    exit 1 # endScript should exit, this is just a fallback
fi


# check if there is old backup data existing on the target
if [ -d "${target_mountpoint_path}/${target_subdir}" ] &&
   ! [ -n "$(find "${target_mountpoint_path}/${target_subdir}" -maxdepth 0 -empty -exec echo {} is empty. \; 2>/dev/null)" ]
then
    message "There seems to be older backup data on the target device, moving it from '${target_mountpoint_path}/${target_subdir}' to '${target_mountpoint_path}/${target_subdir_old}'"
    if [ -d "${target_mountpoint_path}/${target_subdir_old}" ]
    then
        # fallback if last clean-up operation was not successful
        message "There is arleady old backup data at '${target_mountpoint_path}/${target_subdir_old}', going to delete it..."
        rm -rf "${target_mountpoint_path}/${target_subdir_old}" > /dev/null 2>&1
    fi
    if mv -f "${target_mountpoint_path}/${target_subdir}" "${target_mountpoint_path}/${target_subdir_old}" > /dev/null 2>&1
    then
        message "Successfully moved '${target_mountpoint_path}/${target_subdir}' to '${target_mountpoint_path}/${target_subdir_old}'."
    else
        endScript "Could not move old backup data from '${target_mountpoint_path}/${target_subdir}' to "${target_subdir_old}/${target_subdir_old}")." "error"
        exit 1 # endScript should exit, this is just a fallback
    fi
fi


# analyze target dir
bytes_available=$(($(df --output=avail -B 1 "${target_mountpoint_path}" | tail -n 1)+0))
bytes_available=$((${bytes_available} - 1074000000)) # ~ roughly 1 GiB buffer
bytes_available_human="$(numfmt --to=iec-i --suffix=B --format='%.2f' ${bytes_available})"
message "There is about ${bytes_available_human} of free space available on the target device."
if [ $(($bytes_needed+0)) -gt  $(($bytes_available+0)) ]
then
    # handle existing data on the target (if any)
    if [ -d "${target_mountpoint_path}/${target_subdir_old}" ]
    then
        bytes_oldcopy=$(($(du -cs "${target_mountpoint_path}/${target_subdir_old}" | tail -n 1 | cut -f1)+0))
        bytes_oldcopy=$((${bytes_oldcopy} + 1074000000)) # ~ roughly 1 GiB buffer
        bytes_oldcopy_human="$(numfmt --to=iec-i --suffix=B --format='%.2f' ${bytes_oldcopy})"
        bytes_afterdel=$(($(($bytes_available+0))+$(($bytes_oldcopy+0))))
        bytes_afterdel_human="$(numfmt --to=iec-i --suffix=B --format='%.2f' ${bytes_afterdel})"
        message "The old backup data takes about ${bytes_oldcopy_human} of space."
        if [ $(($bytes_needed+0)) -gt $(($(($bytes_available+0))+$(($bytes_oldcopy+0)))) ]
        then
            endScript "Aborted. There is not enough space available on '${target_mountpoint_path}', even when the old backup data gets deleted (${bytes_afterdel_human} (estimate) available after delete, ${bytes_needed_human} needed)." "error"
            exit 1 # endScript should exit, this is just a fallback
        else
            message "Going to delete the old backup data at '${target_mountpoint_path}/${target_subdir_old}' to allow the new data to be copied..."
            rm -rf "${target_mountpoint_path}/${target_subdir_old}" > /dev/null 2>&1
        fi
        unset bytes_oldcopy bytes_oldcopy_human bytes_afterdel bytes_afterdel_human

        # analyze target dir again
        bytes_available=$(($(df --output=avail -B 1 "${target_mountpoint_path}" | tail -n 1)+0))
        bytes_available=$((${bytes_available} - 1074000000)) # ~ roughly 1 GiB buffer
        bytes_available_human="$(numfmt --to=iec-i --suffix=B --format='%.2f' ${bytes_available})"
        message "There is about '${bytes_available_human}' of space available on the target device."
    fi

    if [ $(($bytes_needed+0)) -gt  $(($bytes_available+0)) ]
    then
        endScript "There is not enough space available on the target device '${target_mountpoint_path}' (${bytes_available_human} available, ${bytes_needed_human} needed)." "error"
        exit 1 # endScript should exit, this is just a fallback
    fi
fi


# inform about elapsed time
time_elapsed=""
if ! [ -z "${SECONDS:-}" ] # $SECONDS is a bash internal var
then
    time_elapsed=$SECONDS
    time_elapsed="$(printf '%02dh:%02dm:%02ds\n' $((time_elapsed/3600)) $((time_elapsed%3600/60)) $((time_elapsed%60)))"
fi
message "Elapsed time: ${time_elapsed}."
unset time_elapsed


# handle the files
if [ ${#backup_sources_cp[@]} -eq 0 ]
then
    endScript "There were no backups to mirror to '${target_mountpoint_path}'." "success"
    exit 0 # endScript should exit, this is just a fallback
fi
if ! mountpoint -q "${target_mountpoint_path}" > /dev/null 2>&1
then
    endScript "'${target_mountpoint_path}' is no mountpoint (unexpected error)." "error"
    exit 1 # endScript should exit, this is just a fallback
fi
message "Going to process the created list of backups to copy now."
for source_item in "${backup_sources_cp[@]}"
do
    if ! [ -d "${target_mountpoint_path}/${target_subdir}" ]
    then
        message "Creating copy target directory at '${target_mountpoint_path}/${target_subdir}'."
        mkdir "${target_mountpoint_path}/${target_subdir}" # no "-p" as additional safeguard to prevent writing much data on the wrong partition: propably fails if mounting did not work a
    fi

    message ""
    message "#### Handling backup '$(basename "${source_item}")' ####"

    # create checksums
    #
    # SHA1 was chosen as it is by far the fastest on large datasets (even faster then CRC32
    # and MD5) on modern hardware. This is especially true on CPUs like EPYC and RYZEN) we
    # usually got on PVE hosts. See the following for more information or to benchmark your
    # machine:
    #   $ openssl speed md5 sha1
    #   https://stackoverflow.com/a/26682952
    # "sum" or "crc32" is also harder to handle as they do not provide built-in checking.
    if [ "${opt_checksums}" = "1" ]
    then
        pwd_save="${PWD}" # $OLDPWD is sometimes a bit strange to handle when subshells are included
        message "Creating checksums file"
        message   "cd "\"$(dirname "${source_item}")\"" && sha1sum "\"./$(basename "${source_item}")\""* > "\"${target_mountpoint_path}/${target_subdir}/$(basename "${source_item}").sha1\"" 2>&1" # indentation to easily compare if the message and real command are the same
                 $(cd   "$(dirname "${source_item}")"   && sha1sum   "./$(basename "${source_item}")"*   >   "${target_mountpoint_path}/${target_subdir}/$(basename "${source_item}").sha1"   2>&1) # indentation to easily compare if the message and real command are the same
        exitcode_sha1sum=$?
        cd "${pwd_save}"
        unset pwd_save

        # break on error
        if [ $exitcode_sha1sum -ne 0 ]
        then
            endScript "Creating checksums file failed." "error"
            exit 1 # endScript should exit, this is just a fallback
        fi
        unset exitcode_sha1sum

        # inform about elapsed time
        time_elapsed=""
        if ! [ -z "${SECONDS:-}" ] # $SECONDS is a bash internal var
        then
            time_elapsed=$SECONDS
            time_elapsed="$(printf '%02dh:%02dm:%02ds\n' $((time_elapsed/3600)) $((time_elapsed%3600/60)) $((time_elapsed%60)))"
        fi
        message "Elapsed time: ${time_elapsed}."
        unset time_elapsed
    fi

    # copy
    message "Starting copy of backup"
    message    "cp -r -f -v "\"${source_item}\""* "\"${target_mountpoint_path}/${target_subdir}\"" 2>&1" # indentation to easily compare if the message and real command are the same
    output_cp=$(cp -r -f -v   "${source_item}"*     "${target_mountpoint_path}/${target_subdir}"   2>&1) # indentation to easily compare if the message and real command are the same
    exitcode_cp=$?
    sync > /dev/null 2>&1

    # log
    ifs_save="${IFS}"; IFS="$(printf '\n+')"; IFS="${IFS%?}" # temporarily change IFS to "\n" (LF)
    for line in ${output_cp}
    do
        if [ $exitcode_cp -ne 0 ]
        then
            message "  ${line}" "error"
        else
            message "  ${line}"
        fi
    done
    IFS="${ifs_save}"; unset ifs_save # restore IFS
    unset line output_cp

    # inform about elapsed time
    time_elapsed=""
    if ! [ -z "${SECONDS:-}" ] # $SECONDS is a bash internal var
    then
        time_elapsed=$SECONDS
        time_elapsed="$(printf '%02dh:%02dm:%02ds\n' $((time_elapsed/3600)) $((time_elapsed%3600/60)) $((time_elapsed%60)))"
    fi
    message "Elapsed time: ${time_elapsed}."
    unset time_elapsed

    # break on error
    if [ $exitcode_cp -ne 0 ]
    then
        endScript "Copying '${source_item}'* to '${target_mountpoint_path}/${target_subdir}' failed." "error"
        exit 1 # endScript should exit, this is just a fallback
    fi
    unset exitcode_cp

    # verify checksums
    if [ "${opt_checksums}" = "1" ]
    then
        pwd_save="${PWD}" # $OLDPWD is sometimes a bit strange to handle when subshells are included
        message "Verify checksums of file copies"
        message         "cd "\"${target_mountpoint_path}/${target_subdir}\"" && sha1sum -c "\"./$(basename "${source_item}").sha1\"" 2>&1" # indentation to easily compare if the message and real command are the same
        output_sha1sum=$(cd   "${target_mountpoint_path}/${target_subdir}"   && sha1sum -c   "./$(basename "${source_item}").sha1"   2>&1) # indentation to easily compare if the message and real command are the same
        exitcode_sha1sum=$?
        cd "${pwd_save}"
        unset pwd_save

        # log
        ifs_save="${IFS}"; IFS="$(printf '\n+')"; IFS="${IFS%?}" # temporarily change IFS to "\n" (LF)
        for line in ${output_sha1sum}
        do
            if [ $exitcode_sha1sum -ne 0 ]
            then
                message "  ${line}" "error"
            else
                message "  ${line}"
            fi
        done
        IFS="${ifs_save}"; unset ifs_save # restore IFS
        unset line output_sha1sum

        # break on error
        if [ $exitcode_sha1sum -ne 0 ]
        then
            endScript "Checksum verification failed." "error"
            exit 1 # endScript should exit, this is just a fallback
        fi
        unset exitcode_sha1sum
        message "Verification was successful."

        # inform about elapsed time
        time_elapsed=""
        if ! [ -z "${SECONDS:-}" ] # $SECONDS is a bash internal var
        then
            time_elapsed=$SECONDS
            time_elapsed="$(printf '%02dh:%02dm:%02ds\n' $((time_elapsed/3600)) $((time_elapsed%3600/60)) $((time_elapsed%60)))"
        fi
        message "Elapsed time: ${time_elapsed}."
        unset time_elapsed
    fi
done
message "All file operations were finished successfully."
unset source_item


# backup was sucessful, clean up old backup data (best effort)
if [ -d "${target_mountpoint_path}/${target_subdir_old}" ]
then
    message "Going to clean up the old backup at '${target_mountpoint_path}/${target_subdir_old}' data on the target device."
    rm -rf "${target_mountpoint_path}/${target_subdir_old}" 2>/dev/null
fi


time_elapsed=""
if ! [ -z "${SECONDS:-}" ] # $SECONDS is a bash internal var
then
    time_elapsed=$SECONDS
    time_elapsed="$(printf '%02dh:%02dm:%02ds\n' $((time_elapsed/3600)) $((time_elapsed%3600/60)) $((time_elapsed%60)))"
    time_elapsed=" Elapsed time: ${time_elapsed}."
fi

endScript "Mirroring backups to '${target_mountpoint_path}' was successful.${time_elapsed}" "success"
exit 0 # endScript should exit, this is just a fallback
