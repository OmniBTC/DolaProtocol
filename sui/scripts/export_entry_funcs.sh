#!/bin/bash

find ../ -name "*.move" | grep -v "build" | xargs grep -h -A 20 "entry" | xargs > entry_funcs.txt
grep -Eo "public entry fun [^{.]*? {" entry_funcs.txt > grep_entry_func.txt

OLD_IFS="$IFS"
IFS="{"
entry_funcs=($(< grep_entry_func.txt))
IFS="$OLD_IFS"


cat entry_func_template.sh > entry_funcs.sh
echo "" >> entry_funcs.sh

for func in "${entry_funcs[@]}"
do
  prefix_removed="${func#*public entry fun }"
  func_name="${prefix_removed%(*}"
  module_paths=$(find ../ -name "*.move" | grep -v "build" | xargs grep -l "public entry fun $func_name(")
  module_paths_array=($(echo "$module_paths" | xargs))
  for module_path in "${module_paths_array[@]}"
  do
    module_prefix_removed="${module_path##*/}"
    module_name="${module_prefix_removed%.*}"
    package_path_suffix="${module_path%/sources/*}"
    package_name="${package_path_suffix##*/}"
    callable_func_name="$package_name""_$module_name""_$func_name"
    # shellcheck disable=SC2001
    clear_callable_func_name=$(echo "$callable_func_name" | sed -e "s/<.*>//g")
    {
      echo "# $(echo "$func" | xargs)"
      echo "functions $clear_callable_func_name () {"
      echo "    package_module_function \"\$@\""
      echo "}"
      echo ""
    } >> entry_funcs.sh
  done
done

rm -rf entry_funcs.txt grep_entry_func.txt

