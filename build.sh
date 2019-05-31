#!/bin/bash
# writen by CatalpaFlat at 2019.05.30


branch=''
begin_hash=''
end_hash=''

help=''
# help
print_help() {
cat <<EOF
    use ${program}

    --branch=<git branch> - 构建 git branch (default:当前分支)
    --begin_hash=<git commit hash> - 欲构建git起始commit hash值 (default:当前分支的最近hash)
    --end_hash=<git commit hash> - 希望构建的commit的hash值 (default:当前分支的最近hash的上一次commit)

    --help  - prints help screen
EOF
}
# 传参
parse_arguments() {
  local helperKey="";
  local helperValue="";
  local current="";

  while [[ "$1" != "" ]]; do
      current=$1;
      helperKey=${current#*--};
      helperKey=${helperKey%%=*};
      helperKey=$(echo "$helperKey" | tr '-' '_');
      helperValue=${current#*=};
      if [[ "$helperValue" == "$current" ]]; then
        helperValue="1";
      fi
       eval ${helperKey}=${helperValue};
      shift
  done
}

parse_arguments ${@};

if [[ "$help" == "1" ]]; then
    print_help;
    exit 1;
fi

ECHO Initstating Build Version Differences ......

ECHO Initstating Git Info ......

# git环境
if [[ ! -d ".git" ]]; then
    ECHO error: please init  Git Repository
    exit 1;
fi

if [[ ! -z ${branch} ]]; then
    git checkout ${branch}
fi

# 获取默认commit-hash
if [[ -z "$begin_hash" ]] && [[ -z "$end_hash" ]] ; then
    for p in $(git log --pretty=oneline -2) ; do
        if [[ ${#p} -eq 40 ]]; then
            if [[ -z ${begin_hash} ]]; then
                begin_hash=${p}
            else
                end_hash=${p}
                break
            fi
        fi
    done
fi

is_begin_has=false

# 是否当前最新commit
if [[ $(git log --pretty=oneline -1) == *${begin_hash}* ]]; then
    is_begin_has=true
fi

# 非当前最新分支commit，回滚到原始版本，可能当时maven原始配置不支持compile或会出现构建失败（如：使用本地仓/私有仓库等）
if [[ ${is_begin_has} = false ]]; then
    project_path=$(pwd)
    project_name=${project_path##*/}
    cd ..
    build_project_name=${project_name}_build_temp_project
    if [[ ! -d ${build_project_name} ]]; then
        mkdir ${build_project_name}
    fi
    \cp -rf  ${project_name}/.  ${build_project_name}
    cd ${build_project_name}
    git reset --hard ${begin_hash}
fi

ECHO Build Maven ......

mvn clean compile -q -DskipTest

ECHO Initstating to transport ......

# 创建增量部署文件夹

build_path=build-path/
current_date=`date +%Y%m%d`

if [[ ! -d "$build_path$current_date" ]]; then
    mkdir -p ${build_path}${current_date}
else
    rm -rf ${build_path}${current_date}
    mkdir -p ${build_path}${current_date}
fi

default_target_paths=()
default_java_file=java

module_index=0
# 检索当前项目是否maven多模块开发，递归检索，并设置其编译后的代码位置（暂只提供了java类型）
obtain_module(){
    for module in ` cat ./pom.xml | grep '<module>' | awk -F '>' '{print $2}' | awk -F '<' '{print $1}' `
    do
        cd ${module}

        if [[ ! -d "/pom.xml" ]]; then
           module_exist=`cat ./pom.xml | grep '<module>' | awk -F '>' '{print $2}' | awk -F '<' '{print $1}'`
           if [[ -z ${module_exist} ]]; then
                if [[ ! -d "/target" ]]; then
                    if [[ -z $1 ]]; then
                        default_target_paths[module_index]=${module}/target/classes
                    else
                        default_target_paths[module_index]=$1/${module}/target/classes
                    fi
                    ((module_index++))
                fi
           else
                 if [[ -z $1 ]]; then
                      obtain_module ${module}
                 else
                      obtain_module $1/${module}
                 fi
           fi
        fi
        cd ..
    done
}

obtain_module

# 通过git diff --name-only实现两次commit之间文件差异，并且将begin_hash的代码进行编译后，将差异的文件拷贝到“增量文件夹”中，以备后续进行增量部署

for file_path in $(git diff --name-only ${begin_hash} ${end_hash}) ; do
    package_path=${file_path%/*}
    file_name=${file_path##*/}
    file_type=${file_name##*.}

    if [[ ${package_path} != *.* ]]; then
          if [[ ! -d "./${build_path}${current_date}/$package_path" ]] ; then
                mkdir -p ./${build_path}${current_date}/${package_path}
           fi
    fi
#
    if [[ ${file_type} = ${default_java_file} ]]; then
        module_path=${package_path##*java}
        file_class_name=${file_name%.*}


        module_type=${package_path%%/*}

        for default_target_path in ${default_target_paths[@]}; do
            target_module_path=$(echo ${default_target_path} | awk -F '/target/' '{print $1}')
            file_target_module_path=$(echo ${package_path} | awk -F '/src/' '{print $1}')
            file_target_package_path=$(echo ${package_path} | awk -F '/src/main/java/' '{print $2}')
            default_module_type=${default_target_path%%/*}
            if [[ ${target_module_path} = ${file_target_module_path} ]]; then
                cp -afx ${default_target_path}/${file_target_package_path}/${file_class_name}* ./${build_path}${current_date}/${package_path}
            fi
        done

    else
        if [[ ${package_path} != *.* ]]; then
            if [[ ! -d "./${build_path}${current_date}/$package_path" ]] ; then
                mkdir -p ./${build_path}${current_date}/${package_path}
            fi
        else
             package_path=${package_path%/*}
        fi

        cp -afx ${file_path} ./${build_path}${current_date}/${package_path}

    fi
done
ECHO DONE