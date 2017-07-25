# There are three ways to get a Git branch name
#  * git rev-parse --abbrev-ref HEAD 2>/dev/null
#  * git symbolic-ref --short HEAD 2>/dev/null
#  * git branch 2>/dev/null | sed -n '/\* /s///p'

__git_branch_name_bash () {
    type -P git &>/dev/null || return 0;
    git status &>/dev/null || return 0;
    branch1=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    branch2=$(git symbolic-ref --short HEAD 2>/dev/null)
    [[ $branch1 == $branch2 ]] && { echo $branch1; return 0; }
    [[ $branch1 == "HEAD" && -n $branch2 ]] && { echo "new repository | $branch2"; return 0; }
    branch3=$(git branch 2>/dev/null | sed -n '/\* /s///p')
    [[ $? == 0 ]] && {
        [[ $branch3 =~ "(HEAD detached at" ]] && echo "${branch3:1:${#branch3}-2}" || echo $branch3
        return 0;
    }
    echo "Failed to determine Git branch name in $(pwd)" >&2
    return 1
}

# Execute the function if the file is not sourced
if [[ "$(basename -- $0)" == "$(basename -- ${BASH_SOURCE[0]})" ]]; then
    __git_branch_name_bash
fi
