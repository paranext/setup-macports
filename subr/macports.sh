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
: ${macports_rsync_options:='-rtzvl --delete-after --timeout=60'}
: ${macports_sync_mirrors:='rsync.macports.org bos.us.rsync.macports.org fra.de.rsync.macports.org'}

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
    local pathname
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

# The default ports tree source is a single mirror, and when it is
# unresponsive rsync otherwise hangs for as long as the connection is
# held open. The timeout below turns such a stall into a prompt
# failure, which is what makes retrying worthwhile.
#
# Only --timeout is used: macOS 14 ships rsync 2.6.9, which rejects the
# --contimeout added in rsync 3.1.0, while recent versions ship
# openrsync, which accepts it. A connection that is never established
# fails on its own through the TCP timeout anyway.
#
# The configuration file must already exist: MacPorts only installs its
# default configuration when there is none, so writing a file holding
# nothing but rsync_options would lose every other default setting.
write_rsync_options()
{
    local pathname stagedfile status

    pathname="${macports_prefix}/etc/macports/macports.conf"

    if [ ! -f "${pathname}" -o ! -r "${pathname}" ]; then
	failwith '%s: Not a regular and readable file.' "${pathname}"
    fi

    stagedfile=$(mktemp -t 'setup-macports-XXXXXX')\
	|| failwith 'Cannot create a temporary file.'

    grep -v -E '^[[:space:]]*#*[[:space:]]*rsync_options([[:space:]]|$)'\
	 "${pathname}" > "${stagedfile}"
    status="$?"

    # grep exits with 1 when it selects no line, which is fine, but
    # with 2 when it cannot read the file. Writing the staged file back
    # in that case would lose every other setting.
    if [ "${status}" -gt 1 ]; then
	rm -f "${stagedfile}"
	failwith '%s: Cannot read the MacPorts configuration.' "${pathname}"
    fi

    printf 'rsync_options %s\n' "${macports_rsync_options}" >> "${stagedfile}"

    # A source installation leaves the configuration owned by root.
    # Copying over the existing file keeps its owner and mode.
    if ! sudo cp "${stagedfile}" "${pathname}"; then
	rm -f "${stagedfile}"
	failwith '%s: Cannot write the MacPorts configuration.' "${pathname}"
    fi
    rm -f "${stagedfile}"
}

sync_ports_diagnostic()
{
    printf 'MacPorts version:\n'
    port version || :
    printf 'Ports tree sources:\n'
    ls -la "${macports_prefix}/var/macports/sources" || :
}

ports_tarball_source()
{
    printf 'rsync://%s/macports/release/tarballs/ports.tar' "$1"
}

# The default source rsync.macports.org is a fixed alias for a single
# mirror, so retrying it does not help while that mirror is down.
# Fallback mirrors are only used when the sources were not configured.
sources_use_the_default_mirror()
{
    test "$(awk '!/^[[:space:]]*(#|$)/ { print $1, $2 }'\
		"${macports_prefix}/etc/macports/sources.conf" 2>/dev/null)"\
	 = "$(ports_tarball_source 'rsync.macports.org') [default]"
}

# Only official MacPorts mirrors are acceptable, and only for the
# signed tarball: rsync itself is unauthenticated, so the signature
# MacPorts checks on ports.tar is what protects the ports tree.
#
# The ports tree is stored per source, so after a successful
# synchronisation sources.conf must keep naming the mirror used.
write_ports_tree_mirror()
{
    case "$1" in
	*[!a-z0-9.-]*)
	    failwith '%s: Not an official MacPorts mirror.' "$1"
	    ;;
	rsync.macports.org|*.rsync.macports.org)
	    :
	    ;;
	*)
	    failwith '%s: Not an official MacPorts mirror.' "$1"
	    ;;
    esac

    printf '%s [default]\n' "$(ports_tarball_source "$1")"\
	| sudo tee "${macports_prefix}/etc/macports/sources.conf" > /dev/null\
	|| failwith '%s: Cannot write the ports tree sources.'\
		    "${macports_prefix}/etc/macports/sources.conf"
}

# Rotate through the mirrors, starting with the first.
select_mirror()
{
    local attempt
    attempt="$1"
    shift
    shift $(expr \( "${attempt}" - 1 \) % "$#")
    printf '%s' "$1"
}

# Synchronising the ports tree sometimes meets an unreachable or
# stalled mirror. Such failures are transient, so a handful of
# attempts, spread over several mirrors when the default source is
# used, is usually enough.
sync_ports()
{
    local attempt delay syncflag mirrors mirror

    # The loop only stops on a numeric comparison, so anything else
    # would make it retry forever.
    case "${macports_sync_attempts}" in
	''|*[!0-9]*)
	    failwith '%s: Not a valid number of synchronisation attempts.'\
		     "${macports_sync_attempts}"
	    ;;
    esac
    if [ "${macports_sync_attempts}" -lt 1 ]; then
	failwith '%s: Not a valid number of synchronisation attempts.'\
		 "${macports_sync_attempts}"
    fi
    case "${macports_sync_delay}" in
	''|*[!0-9]*)
	    failwith '%s: Not a valid synchronisation delay.'\
		     "${macports_sync_delay}"
	    ;;
    esac

    if sources_use_the_default_mirror; then
	mirrors="${macports_sync_mirrors}"
    else
	mirrors=''
    fi

    attempt='1'
    while :; do
	if [ "${attempt}" -ge "${macports_sync_attempts}" ]; then
	    # Ask for debug output on the last attempt, so that a
	    # persistent failure leaves something to triage without
	    # paying for an extra synchronisation.
	    syncflag='-d'
	else
	    # Verbose output keeps the reason rsync gives for a failure
	    # that a later attempt recovers from.
	    syncflag='-v'
	fi

	if [ -n "${mirrors}" ]; then
	    mirror=$(select_mirror "${attempt}" ${mirrors})
	    write_ports_tree_mirror "${mirror}"
	    wlog 'Info' 'Synchronising the ports tree from %s.' "${mirror}"
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
