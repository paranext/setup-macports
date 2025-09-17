# stdlib.sh — Shell Standard Library

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

eprintf()
{
    1>&2 printf "$@"
}

wlog()
{
    {
	printf '%s: ' "$1"
	shift
	printf "$@"
	printf '\n'
    } 1>&2
}

failwith()
{
    local status

    status='1'
    case "$1" in
	[0-9][0-9][0-9]|[0-9][0-9]|[0-9])
	    status="$1"
	    shift
	    ;;
	*)
	    :
    esac

    wlog 'Error' "$@"
    exit "${status}"
}


with_group_presentation()
(
    if [ "${GITHUB_ACTIONS}" = 'true' ]; then    
	trap "printf '::endgroup::\n'" INT TERM EXIT 
	printf '::group::%s\n' "$1"
    fi
    shift
    "$@"
)

# End of file `stdlib.sh'
