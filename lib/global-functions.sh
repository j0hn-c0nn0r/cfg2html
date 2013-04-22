# global-functions.sh
#

function read_and_strip_file {
# extracts content from config files. In other words: strips the comments and new lines
	if test -s "$1" ; then
		sed -e '/^[[:space:]]/d;/^$/d;/^#/d' "$1"
	fi
}

######
### Functions for dealing with URLs
######

function url_scheme {
    url=$1
    scheme=${url%%://*}
    # rsync scheme does not have to start with rsync:// it can also be scp style
    echo $scheme | grep -q ":" && echo rsync || echo $scheme
}

function url_host {
    url=$1
    host=${url#*//}
    echo ${host%%/*}
}

function url_path {
    url=$1
    path=${url#*//}
    echo /${path#*/}
}

### Mount URL $1 at mountpoint $2[, with options $3]
function mount_url {
    url=$1
    mountpoint=$2
    defaultoptions="rw"
    options=${3:-"$defaultoptions"}

    ### Generate a mount command
    mount_cmd=""
    case $(url_scheme $url) in
        (tape|file|rsync|fish|ftp|ftps|hftp|http|https|sftp)
            ### Don't need to mount anything for these
            return 0
            ;;
        (var)
            ### The mount command is given by variable in the url host
            var=$(url_host $url)
            mount_cmd="${!var} $mountpoint"
            ;;
        (cifs)
            if [ x"$options" = x"$defaultoptions" ];then
                mount_cmd="mount $v -o $options,guest //$(url_host $url)$(url_path $url) $mountpoint"
            else
                mount_cmd="mount $v -o $options //$(url_host $url)$(url_path $url) $mountpoint"
            fi
            ;;
        (usb)
            mount_cmd="mount $v -o $options $(url_path $url) $mountpoint"
            ;;
	(sshfs)
	    mount_cmd="sshfs $(url_host $url):$(url_path $url) $mountpoint -o $options"
	    ;; 
        (*)
            #mount_cmd="mount $v -t $(url_scheme $url) -o $options $(url_host $url):$(url_path $url) $mountpoint"
            mount_cmd="mount $v -o $options $(url_host $url):$(url_path $url) $mountpoint"
            ;;
    esac

    Log "Mounting with '$mount_cmd'"
    $mount_cmd >&2
    StopIfError "Mount command '$mount_cmd' failed."
}

### Unmount url $1 at mountpoint $2
function umount_url {
    url=$1
    mountpoint=$2

    case $(url_scheme $url) in
        (tape|file|rsync|fish|ftp|ftps|hftp|http|https|sftp)
            ### Don't need to umount anything for these
            return 0
            ;;
	(sshfs)
	    umount_cmd="fusermount -u $mountpoint"
	    ;;
        (var)
            var=$(url_host $url)
            umount_cmd="${!var} $mountpoint"

            Log "Unmounting with '$umount_cmd'"
            $umount_cmd
            StopIfError "Unmounting failed."

            return 0
            ;;
    esac

    umount_mountpoint $mountpoint
    StopIfError "Unmounting '$mountpoint' failed."
}

### Unmount mountpoint $1
function umount_mountpoint {
    mountpoint=$1

    ### First, try a normal unmount,
    Log "Unmounting '$mountpoint'"
    umount $v $mountpoint >&2
    if [[ $? -eq 0 ]] ; then
        return 0
    fi

    ### otherwise, try to kill all processes that opened files on the mount.
    # TODO: actually implement this

    ### If that still fails, force unmount.
    Log "Forced unmount of '$mountpoint'"
    umount $v -f $mountpoint >&2
    if [[ $? -eq 0 ]] ; then
        return 0
    fi

    Log "Unmounting '$mountpoint' failed."
    return 1
}

function CopyFilesAccordingOutputUrl {
    # check if OUTPUT_URL variable has been defined
    [[ -z "$OUTPUT_URL" ]] && return 0
    temp_mntpt=$(mktemp -d /tmp -p cfg2html_${MASTER_PID})
    mkdir -m 755 -p $temp_mntpt
    target_dir="$temp_mntpt/cfg2html/$(hostname)"
    mount_url "$OUTPUT_URL" $temp_mntpt
    [[ ! -d $target_dir ]] && mkdir -m 755 -p $target_dir
    cp $HTML_OUTFILE $target_dir
    LogIfError "Could not copy $HTML_OUTFILE to remote $target_dir directory"
    cp $TEXT_OUTFILE $target_dir
    cp $ERROR_LOG $target_dir
    chmod 644 $target_dir/*
    umount_url "$OUTPUT_URL" $temp_mntpt
    rmdir -f $temp_mntpt
}

