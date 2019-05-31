# Shell 脚本结合Git实现增量部署项目

> 应用部署是开发、测试、上线必须面对的一个过程，尤其是微服务架构的出现，运维部署从单体的部署逐渐脱离出，并且越显复杂。
>
> 然而，抛开多语言，多环境，集群，分布式的部署之外。就单单讨论增量部署和全量部署

## 1. 增量和全量部署

部署，除却项目初始化部署，最理想的情况即为：**新版本更改哪些内容则更新哪些内容**

### 1.1 增量部署

#### 1.1.1 增量部署简介

​		增量部署一般指在每次部署过程中首先提取当前版本和即将部署版本之间的增量（包括代码、可执行文件或者配置等），并在部署过程中仅更新增量部分。

#### 1.1.2 常见部署流程

1. 利用代码管理工具（SVN、GIT等）提取两个版本之间的增量，并结合其他方面的增量变化。
2. 按照增量部分制定具体的部署方式，编写部署脚本，并准备增量部署包（包括混淆代码等）。
3. 分发和部署增量部署包到已经运行上一版本的目标环境，完成系统的版本升级。

#### 1.1.3 增量部署优点

1. 部署速度快。每次只对增量部分进行更新，缩短部署时间
2. 减少变化量。减少对整个系统的变化幅度，有些配置内容是不需要每次都更新迭代的
3. 提高安全性。由于每次支队增量进行更新，避免全部代码的泄露

#### 1.1.4 增量部署缺点

1. 增量部署 若存在其他外在部署环境依赖，则降低部署效率

   增量部署不像

2. 部署环境多的情况下，对可重复性要求高

3. 增量部署对回滚操作变得不友好

### 1.2 如何选择增量还是全量

​		现有的自动化部署，大多数都 全量部署，但全量部署也有一些弊端。但可以通过一些策略进行筛选：

- 提前准全量部署的所有配置和材料（部署包，外在配置文件等）在进行部署，可以提高效率和速度
- 使用灰度发布或负载均衡等方法降低全量部署对应用可用性的影响

​      对于现代系统中绝大部分状态无关的部署单元（应用、模块，微服务等），**全量部署一般应是最优的选择**。而状态相关的部署单元（数据库等）则依然适合增量部署逻辑。



## 2. 进入主题

​	前面讲述了一些关于增量和全量部署的情况。接下来讲述如何通过shell脚本结合Git Log进行增量部署

### 2.1 前提环境

- Java项目

- Maven进行管理

- Git作为代码仓库

### 2.2 shell 脚本

shell新手，写得不够完美，轻喷。

#### 2.2.1 整个shell脚本的模块

- Git环境准备
- Maven对欲构建项目进行编译
- 创建增量部署文件夹
- 检索项目 target目录
- 通过 git diff 检索两次commit之间的差异，再通过检索将对应文件拷贝到“增量文件夹”中



#### 2.2.2 Git环境准备

```shell
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
```

##### 2.2.2.1 校验是否git仓库代码

```shell
if [[ ! -d ".git" ]]; then
    ECHO error: please init  Git Repository
    exit 1;
fi
```

##### 2.2.2.2 检查是否需要切换分支

```shell
if [[ ! -z ${branch} ]]; then
    git checkout ${branch}
fi
```

##### 2.2.2.3 是否需要设置默认构建的commit值

若执行构建时，没给添加 --begin_hash=  和 --end_hash= 进行赋值，则默认使用最新的两次commit来进行增量部署。

通过 git log --pretty=oneline -2  获取最近两次commit的hash

```shell
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
```

##### 2.2.2.4  校验传参的begin_hash值是否为当前分支最新commit hash

若非当前分支最新commit hash，则需要回滚到对应commit，进行项目构建编译

```shell
if [[ $(git log --pretty=oneline -1) == *${begin_hash}* ]]; then
    is_begin_has=true
fi
```

##### 2.2.2.5 若begin_hash非当前最新commit hash

若传参begin_hash的值非当前最新commit hash。则需要回滚到对应commit进行构建编译。

1. 将现有项目进行拷贝到新的目录环境
2. 到新目录环境对项目进行reset，用于构建项目

```shell
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
```



### 2.2.3 Maven对欲构建项目进行编译

对项目进行编译，生成对应class文件以及相关配置文件

```shell
mvn clean compile -q -DskipTest
```

若历史版本中存在使用本地仓库，而maven中没有配置好的情况可以重新配置,通过scope以及systemPath进行引入，如：

```xml
<dependency>
    <groupId>cn.catalpaflat</groupId>
    <artifactId>core</artifactId>
    <version>1.0.0</version>
    <scope>system</scope>
    <systemPath>${project.basedir}/lib/core-1.0.jar</systemPath>
</dependency>
```

#### 2.2.4 创建增量部署文件夹

为了防止增量文件夹被删除或者被commit到git仓库，可以统一化到一个目录中，并通过 .gitignore 对其进行忽略。可以比对每次增量部署的差异

```shell
build_path=build-path/
current_date=`date +%Y%m%d%H%m%s`

if [[ ! -d "$build_path$current_date" ]]; then
    mkdir -p ${build_path}${current_date}
else
    rm -rf ${build_path}${current_date}
    mkdir -p ${build_path}${current_date}
fi
```

#### 2.2.5 检索项目 target目录

若项目为Maven项目，并且是Java项目，由于存在Maven多模块情况，需要检索每个模块下的编译后的代码路径，用于后续进行class等文件的拷贝。

```shell
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
```



#### 2.2.6 检索并拷贝变更文件到增量文件夹

1. git diff --name-only 排查两次commit之间文件差异
2. 并将begin_hash的commit 编译后的代码拷贝到增量文件夹中，以备后续打包进行部署

```shell
# 通过git diff --name-only实现两次commit之间文件差异，并且将begin_hash的代码进行编译后，将差异的文件拷贝到“增量文件夹”中，以备后续进行增量部署

for file_path in $(git diff --name-only ${begin_hash} ${end_hash}) ; do
    package_path=${file_path%/*}
    file_name=${file_path##*/}
    file_type=${file_name##*.}
	# 文件所在校验文件夹是否创建
    if [[ ${package_path} != *.* ]]; then
          if [[ ! -d "./${build_path}${current_date}/$package_path" ]] ; then
                mkdir -p ./${build_path}${current_date}/${package_path}
           fi
    fi
	# 是否java
    if [[ ${file_type} = ${default_java_file} ]]; then
        module_path=${package_path##*java}
        file_class_name=${file_name%.*}
        module_type=${package_path%%/*}
		# 排查在哪个maven模块路径下
        for default_target_path in ${default_target_paths[@]}; do
            target_module_path=$(echo ${default_target_path} | awk -F '/target/' '{print $1}')
            file_target_module_path=$(echo ${package_path} | awk -F '/src/' '{print $1}')
            file_target_package_path=$(echo ${package_path} | awk -F '/src/main/java/' '{print $2}')
            default_module_type=${default_target_path%%/*}
            if [[ ${target_module_path} = ${file_target_module_path} ]]; then
            	# 排查到对应maven模块的target目录，进行cp操作
                cp -afx ${default_target_path}/${file_target_package_path}/${file_class_name}* ./${build_path}${current_date}/${package_path}
            fi
        done

    else
    # 非java文件，直接拷贝文件到对应目录下
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
```





**到此为止，1.0版本的简陋版本初步完成，目测可以使用，哈哈哈哈**