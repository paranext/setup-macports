# macports.sh — Functions for MacPorts

# Paranext Actions (https://github.com/paranext/setup-macports)
# This file is part of Paranext Actions.
#
# Copyright © 2022–2023 Michaël Le Barbier (original author)
# Copyright © 2025 SIL Global and United Bible Societies (subsequent changes)
# All rights reserved.

# This file must be used under the terms of the MIT License.
# This source file is licensed as described in the file LICENSE, which
# you should have received as part of this distribution. The terms
# are also available at https://opensource.org/licenses/MIT

: ${macports_owner:=$(id -u -n)}
: ${macports_group:=$(id -g -n)}
: ${macports_version:='2.12.5'}
: ${macports_prefix:='/opt/local'}
: ${macports_sync_attempts:='4'}
: ${macports_sync_delay:='10'}
: ${macports_rsync_options:='-rtzvl --delete-after --timeout=60 --contimeout=15'}

macports_install()
{
    install -o "${macports_owner}" -g "${macports_group}" "$@"
}

configuration_summary()
{
    cat <<SUMMARY
Package: $(make_package)
Prefix: ${macports_prefix}
Version: ${macports_version}
Variants: $(variants_document)
Ports: $(ports_document)
Sources: $(sources_document)
Path: ${PATH}
Parameter File: ${parameterfile}
SUMMARY
}

write_configuration()
{
    local pathname macos
    pathname="$2"

    macports_install -d -m 755 $(dirname "${pathname}")
    macports_install -m 644 /dev/null "${pathname}"

    if [ -f "$1" -a -r "$1" ]; then
	cp -f "$1" "${pathname}"
    elif [ "$1" = ':no-value' ]; then
	cat > "${pathname}" <<YAML
version: "${macports_version}"
prefix: "${macports_prefix}"
YAML
    else
	failwith '%s: Not a regular and readable file.' "$1"
    fi    

    with_group_presentation\
	'Configuration Summary'\
	configuration_summary
}

variants_document()
{
    if [ "$#" -eq 0 ]; then
	set -- "${macports_prefix}/etc/setup-macports.yaml"
    fi

    printf '# MacPorts system-wide global variants configuration file.\n'
    yq '
.variants // {}
| ( .select = .select // [] )
| ( .select = select(.select | type == "!!seq").select // [.select] )
| ( .deselect = .deselect // [] )
| ( .deselect = select(.deselect | type == "!!seq").deselect // [.deselect] ) 
| (
    (.select | .[] | "+" + . ),
    (.deselect | .[] | "-" + . )
  )
' < "$1"
}

ports_document()
{
    if [ "$#" -eq 0 ]; then
	set -- "${macports_prefix}/etc/setup-macports.yaml"
    fi

    yq '
.ports // {} | .[] 
| ( .select = .select // [] )
| ( .select = select(.select | type == "!!seq").select // [.select] )
| ( .select = (.select | map("+" + . ) | join(" ")))
| ( .deselect = .deselect // [] )
| ( .deselect = select(.deselect | type == "!!seq").deselect // [.deselect] ) 
| ( .deselect = (.deselect | map("-" + . ) | join(" ")))
| ( [ .name, .select, .deselect ] | join (" "))
' < "$1"
}

sources_document()
{
    if [ "$#" -eq 0 ]; then
	set -- "${macports_prefix}/etc/setup-macports.yaml"
    fi

    yq '
.sources // ["rsync://rsync.macports.org/macports/release/tarballs/ports.tar"]
| ( .[0] = .[0] + " [default]")
| .[]
' < "$1"
}

write_variants()
{
    macports_install -d -m 755 "${macports_prefix}/etc/macports"
    macports_install -m 644 /dev/null "${macports_prefix}/etc/macports/variants.conf"
    variants_document "$1" > "${macports_prefix}/etc/macports/variants.conf"
}

write_sources()
{
    macports_install -d -m 755 "${macports_prefix}/etc/macports"
    macports_install -m 644 /dev/null "${macports_prefix}/etc/macports/sources.conf"
    sources_document "$1" > "${macports_prefix}/etc/macports/sources.conf"
}

# The default ports tree source is served by a rotating pool of mirrors
# and an unresponsive mirror otherwise makes rsync hang for as long as
# the connection is held open. The timeouts below turn such a stall
# into a prompt failure, which is what makes retrying worthwhile.
write_rsync_options()
{
    local pathname stagedfile

    pathname="${macports_prefix}/etc/macports/macports.conf"
    stagedfile="${pathname}.setup-macports"

    if [ -f "${pathname}" ]; then
	grep -v '^[[:space:]]*#*[[:space:]]*rsync_options[[:space:]]'\
	     "${pathname}" > "${stagedfile}" || :
    else
	: > "${stagedfile}"
    fi
    printf 'rsync_options %s\n' "${macports_rsync_options}" >> "${stagedfile}"
    mv -f "${stagedfile}" "${pathname}"
}

sync_ports_diagnostic()
{
    printf 'MacPorts version:\n'
    port version || :
    printf 'Ports tree sources:\n'
    ls -la "${macports_prefix}/var/macports/sources" || :
}

# Synchronising the ports tree reaches out to a mirror pool where an
# individual mirror is sometimes unreachable or stalled. Such failures
# are transient, so a handful of attempts is usually enough to get a
# healthy mirror.
sync_ports()
{
    local attempt delay syncflag

    attempt='1'
    while :; do
	if [ "${attempt}" -ge "${macports_sync_attempts}" ]; then
	    # Ask for debug output on the last attempt, so that a
	    # persistent failure leaves something to triage without
	    # paying for an extra synchronisation.
	    syncflag='-d'
	else
	    syncflag=''
	fi

	if sudo port ${syncflag} sync; then
	    return 0
	fi

	wlog 'Warning'\
	     'Synchronisation of the ports tree failed on attempt %s of %s.'\
	     "${attempt}" "${macports_sync_attempts}"

	if [ "${attempt}" -ge "${macports_sync_attempts}" ]; then
	    break
	fi

	delay=$(expr "${attempt}" \* "${macports_sync_delay}")
	wlog 'Info' 'Retrying the synchronisation in %s seconds.' "${delay}"
	sleep "${delay}"
	attempt=$(expr "${attempt}" + 1)
    done

    with_group_presentation\
	'Ports Tree Synchronisation Diagnostic'\
	sync_ports_diagnostic
    failwith 'Cannot synchronise the ports tree after %s attempts.'\
	     "${macports_sync_attempts}"
}

make_package()
{
    local macos version

    case $# in
	0)
	    macos=$(probe_macos)
	    version=$(yq ".version // \"${macports_version}\"" < "${macports_prefix}/etc/setup-macports.yaml")
	    ;;
	1)
	    macos=$(probe_macos)
 	    version=$(yq ".version // \"${macports_version}\"" < "$1")
	    ;;
	2)
	    macos="$1"
	    version="$2"
	    ;;
    esac
    known_macos_db | awk -F'-' "-vmacos=${macos}" "-vversion=${version}" '
$2 == macos {
  printf("https://github.com/macports/macports-base/releases/download/v%s/MacPorts-%s-%s-%s.pkg", version, version, $1, $2)
}
'
}

# End of file `macports.sh'
