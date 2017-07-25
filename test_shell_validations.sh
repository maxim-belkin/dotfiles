# 
# Test syntax validation in your Bash shell
# 
# Do not specify #!/path/to/your/shell at the beginning of this file
# Instead, call this script as `bash test_syntax.sh`
# or
# source it and call `__test_shell_validations_bash` function
#
# Based on https://github.com/l0b0/tilde/blob/master/examples/syntax.sh
#

__test_shell_validations_bash () {
    echo "Bash version: echo $BASH_VERSION"
    set -o errexit -o noclobber -o nounset -o pipefail 2>/dev/null

    local options
    for options in "" "-o noexec"; do
        echo "$SHELL $options"

        echo -n '* '
        if bash $options <<< 'does_not_exist' 2>/dev/null
        then
            echo -n "Doesn't check"
        else
            echo -n "Checks"
        fi
        echo ' whether commands exist.'

        echo -n '* '
        if bash $options <<< 'source does_not_exist' 2>/dev/null
        then
            echo -n "Doesn't check"
        else
            echo -n "Checks"
        fi
        echo ' whether files exist.'

        echo -n '* '
        if bash $options <<< '`' 2>/dev/null
        then
            echo -n "Doesn't check"
        else
            echo -n "Checks"
        fi
        echo ' whether backticks match up.'

        echo -n '* '
        if bash $options <<< '"$(foo")' 2>/dev/null
        then
            echo -n "Doesn't check"
        else
            echo -n "Checks"
        fi
        echo ' whether $( and ) match up.'

        echo -n '* '
        if bash $options <<< '#"$(foo")' 2>/dev/null
        then
            echo -n "Doesn't check"
        else
            echo -n "Checks"
        fi
        echo ' inside comments.'
    done
}

if [[ "$(basename -- $0)" == "$(basename -- ${BASH_SOURCE[0]})" ]]; then
   __test_shell_validations_bash
fi
