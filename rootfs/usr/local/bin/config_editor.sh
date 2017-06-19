#!/bin/bash -x

#export ce_config_file="./cetest"
#export ce_value1="cetest1"
#export ce_operator=":"

for config_file in $(env | grep '_config_file'); do
    # remove prefix from variable
    prefix="${config_file%%_*}"

    # create directory and file
    file="${config_file#*=}"
    dir="$(dirname "${file}")"
    [[ -d "${dir}" ]] || mkdir -p "${dir}"
    [[ -f "${file}" ]] || touch "${file}"

    # assign file header/section
    hvar="${prefix}_header"
    [[ -z ${!hvar} ]] && header="" || header=${!hvar}

    # assign file operator (usually '=' or ' ')
    ovar="${prefix}_operator"
    [[ -z ${!ovar} ]] && operator="=" || operator=${!ovar}

    for matched in $(env | grep -v '_config_file\|_operator' | grep "^${prefix}_"); do
        var="${matched%=*}"
        var="${var#*_}"
        var=$(echo $var | sed 's/_dash_/-/g')
        val="${matched#*=}"
        if grep "^[ ]*${var}" "$file"; then
            sed -i "s/^([ ]*)${var}([ ]*){$operator}([ ]*)[^ ].*/\\\1${var}\\\2${operator}\\\3${val}/" "${file}"
        else
            echo "${var}${operator}${val}" >> $file
        fi
        echo $?
    done

    # clean up
    unset header operator
done
   
